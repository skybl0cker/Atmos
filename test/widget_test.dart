import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weatherapp/models/alert.dart';
import 'package:weatherapp/models/weather.dart';
import 'package:weatherapp/screens/alerts_screen.dart';
import 'package:weatherapp/screens/forecast_screen.dart';
import 'package:weatherapp/screens/home_screen.dart';
import 'package:latlong2/latlong.dart';
import 'package:weatherapp/services/nearby_threats.dart';
import 'package:weatherapp/services/usgs_service.dart';
import 'package:weatherapp/services/weather_service.dart';
import 'package:weatherapp/state/app_state.dart';

import 'fixtures.dart';

const knox = Place(name: 'Knoxville', lat: 35.96, lon: -83.92);

/// AppState with notifications off and no selected place, so init() makes
/// no plugin or network calls; tests then inject data directly.
Future<AppState> makeState({Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues({'notifications': false, ...prefs});
  final s = AppState(sunClock: false);
  await s.init();
  return s;
}

Widget host(AppState s, Widget child) => ChangeNotifierProvider.value(
  value: s,
  child: MaterialApp(
    theme: ThemeData(useMaterial3: true, fontFamily: 'Poppins'),
    home: child,
  ),
);

void main() {
  testWidgets('home renders the forecast, tips and the Weather Today sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final s = await makeState();
    s.selected = knox;
    s.data = WeatherService.parse(
      jsonEncode(
        forecastJson(
          currentTemp: 21,
          currentFeels: 6,
          hourlyProb: (h) => 80,
          minutelyPrecip: (q) => q >= 2 ? 0.4 : 0,
        ),
      ),
      airBody,
    );

    await tester.pumpWidget(host(s, const HomeScreen()));
    // Let entrance animations run (the particle layer never settles, so
    // pump fixed time instead of pumpAndSettle).
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Knoxville'), findsOneWidget);
    expect(find.text('Weather Today'), findsOneWidget);
    expect(find.text('NOW'), findsOneWidget);
    expect(find.text("It's Sunny"), findsOneWidget);
    expect(find.text('70'), findsOneWidget); // 21 °C, counted up
    expect(find.textContaining('Rain likely in ~30 min'), findsOneWidget);
    for (final a in ['Radar', '14-Day', 'Radio']) {
      expect(find.text(a), findsOneWidget);
    }

    // Expanded content lives in the sheet's list; open it fully.
    await tester.tap(find.text('Weather Today'));
    await tester.pump();
    await tester.drag(find.text('Weather Today'), const Offset(0, -600));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Bring an umbrella'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('42 AQI'), findsOneWidget);
    expect(find.textContaining('% lit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home lays out without overflow on a small phone (320×568)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final s = await makeState();
    s.selected = const Place(
      name: 'Llanfairpwllgwyngyll, United Kingdom',
      lat: 53.2,
      lon: -4.2,
    );
    s.saved = [s.selected!, knox];
    s.data = WeatherService.parse(
      jsonEncode(
        forecastJson(
          currentTemp: -12,
          currentFeels: -20,
          windKmh: 70,
          hourlyProb: (h) => 90,
          minutelyPrecip: (q) => q >= 1 ? 3.0 : 0,
          uv: [9, 1, 1],
        ),
      ),
      airBody,
    );
    s.error = 'No internet connection.';

    await tester.pumpWidget(host(s, const HomeScreen()));
    await tester.pump(const Duration(seconds: 2));
    await tester.drag(find.text('Weather Today'), const Offset(0, -500));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('active alerts screen shows cards and expands instructions', (
    tester,
  ) async {
    final s = await makeState();
    s.selected = knox;
    s.alerts = [
      WeatherAlert(
        id: 'x1',
        event: 'Tornado Warning',
        severity: 'Extreme',
        headline: 'Tornado Warning issued',
        description: 'A confirmed tornado was located near Oak Ridge.',
        instruction: 'TAKE COVER NOW!',
        expires: DateTime(2026, 11, 5, 15),
        areas: 'Knox; Anderson',
      ),
      const WeatherAlert(
        id: 'x2',
        event: 'Wind Advisory',
        severity: 'Moderate',
        headline: '',
        description: 'Gusts to 45 mph.',
        instruction: '',
        expires: null,
        areas: 'Knox',
      ),
    ];
    await tester.pumpWidget(host(s, const AlertsScreen(refreshOnOpen: false)));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Tornado Warning'), findsOneWidget);
    expect(find.text('Wind Advisory'), findsOneWidget);
    // First card starts open with its "What to do" box.
    expect(find.text('TAKE COVER NOW!'), findsOneWidget);
    expect(find.text('Gusts to 45 mph.'), findsNothing);
    await tester.tap(find.text('Wind Advisory'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Gusts to 45 mph.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('alerts screen: all clear explains what was checked', (
    tester,
  ) async {
    final s = await makeState();
    s.selected = knox;
    await tester.pumpWidget(host(s, const AlertsScreen(refreshOnOpen: false)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('All clear'), findsOneWidget);
    expect(find.textContaining('within 500 mi'), findsOneWidget);
    expect(find.text('Nearby'.toUpperCase()), findsNothing);
  });

  testWidgets('alerts screen shows a nearby quake even with no NWS alerts', (
    tester,
  ) async {
    final s = await makeState();
    s.selected = knox;
    s.nearby = NearbyThreats(
      quakes: [
        NearbyQuake(
          Earthquake(
            mag: 5.4,
            place: '10 km S of Maryville, TN',
            time: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
            location: const LatLng(35.6, -83.97),
            tsunami: 0,
            url: '',
          ),
          24,
        ),
      ],
    );
    expect(s.hasAlerts, isTrue); // drives the badge on the home button
    await tester.pumpWidget(host(s, const AlertsScreen(refreshOnOpen: false)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('NEARBY'), findsOneWidget);
    expect(find.text('Earthquake · 24 mi away'), findsOneWidget);
    expect(find.textContaining('3 hr ago'), findsOneWidget);
    expect(
      find.text('No watches or warnings for this location.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('home Alerts button is always labelled "Alerts"', (tester) async {
    final s = await makeState();
    s.selected = knox;
    s.data = WeatherService.parse(forecastBody(), null);
    await tester.pumpWidget(host(s, const HomeScreen()));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Alerts'), findsOneWidget);
    expect(find.text('Quake'), findsNothing);
  });

  testWidgets('home shows a retry notice when a refresh fails over old data', (
    tester,
  ) async {
    final s = await makeState();
    s.selected = knox;
    s.data = WeatherService.parse(forecastBody(), null);
    s.error = 'No internet connection.';

    await tester.pumpWidget(host(s, const HomeScreen()));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining("Couldn't update"), findsOneWidget);
  });

  testWidgets('14-day screen lists 14 days', (tester) async {
    tester.view.physicalSize = const Size(1170, 5000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final s = await makeState();
    s.selected = knox;
    final j = forecastJson();
    final daily = j['daily'] as Map;
    // Stretch the 3-day fixture to 14 days (fresh, loosely typed map).
    List<dynamic> rep(String k) => [
      for (var i = 0; i < 14; i++) (daily[k] as List)[i % 3],
    ];
    final days = [
      for (var i = 0; i < 14; i++)
        DateTime(2026, 11, 5 + i).toIso8601String().substring(0, 10),
    ];
    j['daily'] = <String, dynamic>{
      'time': days,
      'sunrise': [for (final d in days) '${d}T07:03'],
      'sunset': [for (final d in days) '${d}T17:35'],
      for (final k in [
        'weather_code',
        'temperature_2m_max',
        'temperature_2m_min',
        'uv_index_max',
        'precipitation_probability_max',
      ])
        k: rep(k),
    };
    s.data = WeatherService.parse(jsonEncode(j), null);

    await tester.pumpWidget(host(s, const ForecastScreen()));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('14-Day Forecast'), findsOneWidget);
    expect(find.textContaining('°'), findsAtLeastNWidgets(28));
  });

  test('saved forecast is restored on the next launch', () async {
    final s1 = await makeState(
      prefs: {
        'last': jsonEncode(knox.toJson()),
        'wxLast': jsonEncode({
          'place': knox.key,
          'forecast': forecastBody(),
          'air': airBody,
          'at': DateTime(2026, 11, 5, 14, 5).millisecondsSinceEpoch,
        }),
      },
    );
    // init() restored synchronously before kicking off the (failing, in
    // tests) network refresh.
    expect(s1.data, isNotNull);
    expect(s1.data!.air?.usAqi, 42);
    expect(s1.updatedAt, DateTime(2026, 11, 5, 14, 5));
  });

  test('a cache for a different place is ignored', () async {
    final s = await makeState(
      prefs: {
        'last': jsonEncode(knox.toJson()),
        'wxLast': jsonEncode({
          'place': '0.00,0.00',
          'forecast': forecastBody(),
          'air': null,
          'at': 0,
        }),
      },
    );
    expect(s.data, isNull);
  });

  group('day / night theme', () {
    WeatherData at(String time) {
      final j = forecastJson();
      (j['current'] as Map)['time'] = time;
      return WeatherService.parse(jsonEncode(j), null);
    }

    test('light by day, dark at night, from the place\'s sun times', () async {
      final s = await makeState();
      s.selected = knox;
      s.data = at('2026-11-05T14:00'); // sunset 17:35
      s.recheckDaytime();
      expect(s.isDaytime, isTrue);
      expect(s.themeMode, ThemeMode.light);

      s.data = at('2026-11-05T21:00');
      s.recheckDaytime();
      expect(s.isDaytime, isFalse);
      expect(s.themeMode, ThemeMode.dark);

      s.data = at('2026-11-06T06:30'); // before 07:03 sunrise
      s.recheckDaytime();
      expect(s.themeMode, ThemeMode.dark);
    });

    test('the place clock advances with time since the fetch', () {
      final d = at('2026-11-05T17:00');
      final fetched = DateTime(2030, 1, 1, 9);
      // Fetched at 5:00 PM place time; 20 min later is still day,
      // 1 h later is past the 5:35 PM sunset.
      expect(
        d.isDaylightNow(
          fetchedAt: fetched,
          now: fetched.add(const Duration(minutes: 20)),
        ),
        isTrue,
      );
      expect(
        d.isDaylightNow(
          fetchedAt: fetched,
          now: fetched.add(const Duration(hours: 1)),
        ),
        isFalse,
      );
    });
  });

  group('big-screen layouts', () {
    Future<AppState> withData() async {
      final s = await makeState();
      s.selected = knox;
      s.data = WeatherService.parse(forecastBody(), airBody);
      return s;
    }

    Future<void> pumpAt(WidgetTester t, Size logical, Widget w) async {
      t.view.physicalSize = logical * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(w);
      await t.pump(const Duration(seconds: 2));
    }

    testWidgets('phone keeps the pull-up sheet', (t) async {
      await pumpAt(
        t,
        const Size(390, 844),
        host(await withData(), const HomeScreen()),
      );
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(find.text('Next 14 Days'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('unfolded foldable gets hero + docked panel', (t) async {
      await pumpAt(
        t,
        const Size(840, 900),
        host(await withData(), const HomeScreen()),
      );
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(find.text('Weather Today'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget); // visible, not hidden
      expect(find.text('Next 14 Days'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('tablet landscape still lays out cleanly', (t) async {
      await pumpAt(
        t,
        const Size(1180, 820),
        host(await withData(), const HomeScreen()),
      );
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('desktop gets a third 14-day column', (t) async {
      await pumpAt(
        t,
        const Size(1440, 900),
        host(await withData(), const HomeScreen()),
      );
      expect(find.text('Next 14 Days'), findsOneWidget);
      expect(find.text('Next 10 Days'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('secondary screens center on wide windows', (t) async {
      final s = await withData();
      await pumpAt(
        t,
        const Size(1440, 900),
        host(s, const AlertsScreen(refreshOnOpen: false)),
      );
      final card = t.getSize(find.byType(ClipRRect).first);
      expect(card.width, lessThanOrEqualTo(760));
      expect(t.takeException(), isNull);
      await t.pumpWidget(host(s, const ForecastScreen()));
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
    });
  });

  test('stepPlace cycles saved places and wraps', () async {
    final a = const Place(name: 'A', lat: 1, lon: 1);
    final b = const Place(name: 'B', lat: 2, lon: 2);
    final s = await makeState();
    s.saved = [a, b];
    s.selected = knox; // not saved: jumps into the list
    expect(s.stepPlace(1), isTrue);
    expect(s.selected?.name, 'A');
    s.stepPlace(1);
    expect(s.selected?.name, 'B');
    s.stepPlace(1);
    expect(s.selected?.name, 'A'); // wrapped
    s.stepPlace(-1);
    expect(s.selected?.name, 'B');
    s.saved = [];
    expect(s.stepPlace(1), isFalse);
  });
}

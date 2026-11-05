import 'package:flutter_test/flutter_test.dart';
import 'package:weatherapp/models/weather.dart';
import 'package:weatherapp/services/seen_alerts.dart';
import 'package:weatherapp/services/tropical_service.dart';
import 'package:weatherapp/services/weather_service.dart';
import 'package:weatherapp/utils/astro.dart';
import 'package:weatherapp/utils/summary.dart';
import 'package:weatherapp/utils/tips.dart';
import 'package:weatherapp/utils/weather_codes.dart';
import 'package:weatherapp/widgets/scene.dart';

import 'fixtures.dart';

String f(double c) => '${(c * 9 / 5 + 32).round()}°';

void main() {
  group('synthesizeCode', () {
    test('dry stays as reported', () {
      expect(synthesizeCode(0, 0), 0);
      expect(synthesizeCode(3, 0), 3);
    });
    test('measured rain upgrades a dry model code by intensity', () {
      expect(synthesizeCode(3, 0.3), 53); // drizzle
      expect(synthesizeCode(2, 1.5), 61); // light
      expect(synthesizeCode(3, 5), 63); // moderate
      expect(synthesizeCode(0, 9), 65); // heavy
    });
    test('existing rain only escalates when very heavy', () {
      expect(synthesizeCode(61, 2), 61);
      expect(synthesizeCode(61, 8), 65);
      expect(synthesizeCode(95, 20), 95); // storms untouched
    });
  });

  group('WeatherData.fromJson', () {
    final d = WeatherData.fromJson(forecastJson());

    test('hourly starts at the current hour and keeps 24 points', () {
      expect(d.hourly.length, 24);
      expect(d.hourly.first.time, DateTime(2026, 11, 5, 14));
      expect(d.hourly.last.time, DateTime(2026, 11, 6, 13));
    });

    test('daily, sun times and current values parse', () {
      expect(d.daily.length, 3);
      expect(d.daily.first.sunrise, DateTime(2026, 11, 5, 7, 3));
      expect(d.current.tempC, 20);
      expect(d.current.isDay, isTrue);
    });

    test('layer-mean steering wind of identical levels is that wind', () {
      expect(d.steeringWindKmh, closeTo(30, 0.01));
      expect(d.steeringWindDir, 270);
    });

    test('opposing winds cancel instead of averaging direction', () {
      final j = forecastJson();
      final h = j['hourly'] as Map<String, dynamic>;
      h['wind_direction_850hPa'] = List.filled(48, 0);
      h['wind_direction_700hPa'] = List.filled(48, 180);
      h['wind_speed_500hPa'] = List.filled(48, 0.0);
      final w = WeatherData.fromJson(j);
      // 850 (weight 850) vs 700 (weight 700) at equal speed: small residual
      // from the north, nowhere near 30 km/h.
      expect(w.steeringWindKmh, lessThan(5));
    });
  });

  group('nowcast', () {
    test('rainStartsIn finds the first wet quarter-hour', () {
      final d = WeatherData.fromJson(
        forecastJson(minutelyPrecip: (q) => q >= 3 ? 0.5 : 0),
      );
      // q=3 → 14:45, precip 0.5 mm/15min → 2 mm/h (> 0.2 threshold).
      expect(d.rainStartsIn, const Duration(minutes: 45));
    });
    test('no rain → null; already raining → null', () {
      expect(WeatherData.fromJson(forecastJson()).rainStartsIn, isNull);
      expect(
        WeatherData.fromJson(forecastJson(currentCode: 61)).rainStartsIn,
        isNull,
      );
    });
  });

  group('daylight', () {
    final d = WeatherData.fromJson(forecastJson());
    test('uses the real sunrise / sunset', () {
      expect(d.isDaylight(DateTime(2026, 11, 5, 7, 0)), isFalse);
      expect(d.isDaylight(DateTime(2026, 11, 5, 7, 10)), isTrue);
      expect(d.isDaylight(DateTime(2026, 11, 5, 17, 30)), isTrue);
      expect(d.isDaylight(DateTime(2026, 11, 5, 18, 0)), isFalse);
    });
    test('falls back to 6 AM – 8 PM outside the forecast', () {
      expect(d.isDaylight(DateTime(2027, 1, 1, 12)), isTrue);
      expect(d.isDaylight(DateTime(2027, 1, 1, 22)), isFalse);
    });
  });

  group('weatherSummary', () {
    test('dry day', () {
      final d = WeatherData.fromJson(forecastJson(dailyMax: [22, 23, 18]));
      expect(weatherSummary(d, f), 'Dry for the rest of the day.');
    });
    test('rain later today, and a cooler tomorrow', () {
      final d = WeatherData.fromJson(
        forecastJson(
          hourlyProb: (h) => h == 19 ? 70 : 0,
          hourlyCode: (h) => h == 19 ? 61 : 1,
          dailyMax: [24, 18, 18],
        ),
      );
      expect(
        weatherSummary(d, f),
        'Rain likely around 7 PM. Cooler tomorrow, high of 64°.',
      );
    });
    test('raining now and easing', () {
      final d = WeatherData.fromJson(
        forecastJson(
          currentCode: 63,
          hourlyProb: (h) => h < 17 ? 90 : 0,
          hourlyPrecip: (h) => h < 17 ? 2.0 : 0,
        ),
      );
      expect(weatherSummary(d, f), startsWith('Rain easing around 5 PM.'));
    });
    test('wind trumps the tomorrow note', () {
      final d = WeatherData.fromJson(
        forecastJson(windKmh: 50, dailyMax: [24, 10, 10]),
      );
      expect(weatherSummary(d, f), endsWith('Windy out there.'));
    });
  });

  group('dayTips', () {
    test('rain, cold and UV produce matching tips', () {
      final d = WeatherData.fromJson(
        forecastJson(currentFeels: 6, hourlyProb: (h) => 80, uv: [7, 1, 1]),
      );
      final t = dayTips(d).map((t) => t.text).toList();
      expect(t, contains('Bring an umbrella'));
      expect(t, contains('Grab a warm jacket'));
      expect(t, contains('High UV — wear sunscreen'));
    });
    test('pleasant dry day gets the feel-good tip, capped at 3', () {
      final d = WeatherData.fromJson(
        forecastJson(currentFeels: 22, uv: [3, 1, 1]),
      );
      expect(dayTips(d).single.text, 'Great day to be outside');
      final busy = WeatherData.fromJson(
        forecastJson(
          currentFeels: -3,
          windKmh: 60,
          hourlyProb: (h) => 90,
          uv: [9, 1, 1],
        ),
      );
      expect(dayTips(busy).length, 3);
    });
  });

  test('dew point (Magnus) is in the right place', () {
    expect(dewPointC(20, 50), closeTo(9.3, 0.2));
    expect(dewPointC(25, 100), closeTo(25, 0.01));
  });

  group('moon phase', () {
    test('known new and full moons', () {
      // Total solar eclipse = new moon: 2024-04-08 18:21 UTC.
      final newMoon = moonPhaseAt(DateTime.utc(2024, 4, 8, 18, 21));
      expect(newMoon.illumination, lessThan(0.02));
      expect(newMoon.name, 'New Moon');
      // Full moon: 2024-04-23 23:49 UTC.
      final full = moonPhaseAt(DateTime.utc(2024, 4, 23, 23, 49));
      expect(full.illumination, greaterThan(0.98));
      expect(full.name, 'Full Moon');
      expect(full.daysToFull, anyOf(0, 29, 30));
    });
    test('short names fit a small card', () {
      expect(moonPhaseAt(DateTime.utc(2024, 4, 11)).shortName, 'Crescent moon');
      expect(moonPhaseAt(DateTime.utc(2024, 4, 23, 23)).shortName, 'Full moon');
    });
    test('waxing before full, waning after', () {
      expect(moonPhaseAt(DateTime.utc(2024, 4, 15)).waxing, isTrue);
      expect(moonPhaseAt(DateTime.utc(2024, 4, 28)).waxing, isFalse);
    });
  });

  group('seen alerts', () {
    test('merges instead of replacing', () {
      expect(mergeSeenAlerts(['a', 'b'], ['c']), ['a', 'b', 'c']);
    });
    test('re-seen ids move to the newest end and the list is capped', () {
      expect(mergeSeenAlerts(['a', 'b', 'c'], ['a'], cap: 2), ['c', 'a']);
    });
  });

  group('tropical b-deck', () {
    // Two fixes 6 h apart, each repeated for the 34/50/64-kt radii.
    String line(String dt, String lat, String lon, int kt, String rad) =>
        'AL, 09, $dt,   , BEST,   0, $lat, $lon, $kt,  980, HU, $rad, NEQ';
    final body = [
      line('2026090100', '250N', '800W', 90, ' 34'),
      line('2026090100', '250N', '800W', 90, ' 50'),
      line('2026090100', '250N', '800W', 90, ' 64'),
      line('2026090106', '256N', '800W', 95, ' 34'),
      line('2026090106', '256N', '800W', 95, ' 50'),
      line('2026090106', '256N', '800W', 95, ' 64'),
    ].join('\n');

    test('duplicate radius lines collapse to one fix per time', () {
      final s = TropicalService.stormFromBdeck(
        'AL092026',
        'Test',
        'Hurricane',
        body,
      )!;
      expect(s.trail.length, 2);
      expect(s.windKt, 95);
      // 0.6° of latitude in 6 h = 36 nm / 6 h = 6 kt, heading north.
      expect(s.moveKt, closeTo(6, 0.1));
      expect(s.moveCompass, 'N');
      expect(s.category, 2);
    });
  });

  group('cached weather round-trip', () {
    test('raw bodies re-parse to the same forecast, with air quality', () {
      final d = WeatherService.parse(forecastBody(), airBody);
      expect(d.hourly.length, 24);
      expect(d.air?.usAqi, 42);
    });
    test('missing or broken air body is tolerated', () {
      expect(WeatherService.parse(forecastBody(), null).air, isNull);
      expect(WeatherService.parse(forecastBody(), 'not json').air, isNull);
    });
  });

  group('scene', () {
    test('picks the matching illustration', () {
      expect(sceneAsset(null), endsWith('bg_day.webp'));
      expect(
        sceneAsset(WeatherData.fromJson(forecastJson(isDay: 0))),
        endsWith('bg_night.webp'),
      );
      expect(
        sceneAsset(WeatherData.fromJson(forecastJson(currentCode: 63))),
        endsWith('bg_rain.webp'),
      );
      expect(
        sceneAsset(WeatherData.fromJson(forecastJson(currentCode: 95))),
        endsWith('bg_rain.webp'),
      );
    });
    test('condition phrases', () {
      expect(conditionPhrase(0, true), "It's Sunny");
      expect(conditionPhrase(0, false), "It's Clear");
      expect(conditionPhrase(63, true), "It's Raining");
      expect(conditionPhrase(53, true), "It's Drizzling");
      expect(conditionPhrase(73, true), "It's Snowing");
    });
  });
}

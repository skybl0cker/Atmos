import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert.dart';
import '../models/weather.dart';
import '../services/alerts_service.dart';
import '../services/climate_service.dart';
import '../services/location_service.dart';
import '../utils/forecast_changes.dart';
import '../services/nearby_threats.dart';
import '../services/notification_service.dart';
import '../services/seen_alerts.dart';
import '../services/weather_service.dart';
import '../services/widget_service.dart';
import '../utils/haptics.dart';

class AppState extends ChangeNotifier {
  /// [sunClock] re-checks day/night every minute; tests turn it off so no
  /// periodic timer outlives them.
  AppState({this.sunClock = true});
  final bool sunClock;

  final _weather = WeatherService();
  final _location = LocationService();
  final _alertsService = AlertsService();
  final _notifications = NotificationService();
  late final SharedPreferences _prefs;
  final Map<String, WeatherData> _cache = {};
  int _req = 0;

  List<Place> saved = [];
  Place? selected;
  WeatherData? data;
  List<WeatherAlert> alerts = [];
  bool loading = false;
  String? error;
  bool imperial = true;
  bool hapticsEnabled = true;
  bool notificationsEnabled = true;

  Set<String> _seenAlertIds = {};

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    imperial = _prefs.getBool('imperial') ?? true;
    hapticsEnabled = _prefs.getBool('haptics') ?? true;
    notificationsEnabled = _prefs.getBool('notifications') ?? true;
    morningSummary = _prefs.getBool('morningSummary') ?? false;
    _seenAlertIds = (_prefs.getStringList('seenAlerts') ?? []).toSet();

    if (notificationsEnabled) {
      // Plugin init only — the notification permission dialog is requested
      // from ensureLocation(), after the location prompt is answered.
      // Android shows a single system permission dialog at a time; asking
      // for both at startup raced and silently dropped the location one.
      unawaited(_notifications.init());
    }

    final s = _prefs.getString('saved');
    if (s != null) {
      saved = (jsonDecode(s) as List)
          .map((e) => Place.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    final last = _prefs.getString('last');
    if (last != null) {
      selected = Place.fromJson(jsonDecode(last) as Map<String, dynamic>);
    } else if (saved.isNotEmpty) {
      selected = saved.first;
    }

    if (selected != null) {
      // Paint last session's forecast instantly, then refresh it.
      _restoreWeather(selected!);
      unawaited(refresh());
    }
    // Upgrade path: places stored before reverse-geocoding existed are still
    // named "My location", and early builds could store junk like
    // "District 6". Resolve the real name once, in the background, so the
    // header, notifications, and widget read e.g. "Hardin Valley, TN".
    if (selected != null &&
        selected!.isCurrent &&
        LocationService.isPlaceholderName(selected!.name)) {
      unawaited(_refreshCurrentPlaceName());
    }
    // NOTE: do NOT call useMyLocation() here — init() runs before runApp(),
    // so there is no Activity yet for the permission dialog. The home screen
    // triggers it after the first frame via ensureLocation().

    // First frame already uses the right theme for the cached place.
    _syncDaytime();
    if (sunClock) _startSunClock();
  }

  /// Called by the home screen after the first frame. If there is no place
  /// selected yet (fresh install), this requests location permission and
  /// loads weather for the current position — then asks for notification
  /// permission, so the two system dialogs never race (Android drops the
  /// second of two simultaneous permission requests).
  Future<void> ensureLocation() async {
    if (selected != null || _locationRequested) {
      // Not a fresh install (or already asked): still offer the
      // notification permission if the OS hasn't recorded a decision.
      if (notificationsEnabled) unawaited(_notifications.requestPermission());
      return;
    }
    _locationRequested = true;
    await useMyLocation();
    if (notificationsEnabled) unawaited(_notifications.requestPermission());
  }

  bool _locationRequested = false;

  /// One-time upgrade for current-location places saved under the old
  /// "My location" placeholder name (or junk like "District 6").
  /// Silent; never surfaces an error.
  Future<void> _refreshCurrentPlaceName() async {
    final p = selected;
    if (p == null ||
        !p.isCurrent ||
        !LocationService.isPlaceholderName(p.name)) {
      return;
    }
    final name = await _location.resolvePlaceName(p.lat, p.lon);
    if (LocationService.isPlaceholderName(name) || name == p.name) return;
    selected = p.copyWith(name: name);
    _prefs.setString('last', jsonEncode(selected!.toJson()));
    notifyListeners();
  }

  // ---- units & formatting -------------------------------------------------

  double tv(double c) => imperial ? c * 9 / 5 + 32 : c;
  String temp(double c) => '${tv(c).round()}°';
  String wind(double kmh) =>
      imperial ? '${(kmh * 0.621371).round()} mph' : '${kmh.round()} km/h';
  String precip(double mm) => imperial
      ? '${(mm / 25.4).toStringAsFixed(2)} in'
      : '${mm.toStringAsFixed(1)} mm';
  String snow(double cm) => imperial
      ? '${(cm / 2.54).toStringAsFixed(cm / 2.54 < 1 ? 1 : 0)} in'
      : '${cm.toStringAsFixed(cm < 10 ? 1 : 0)} cm';

  /// Visibility, capped at "10+ mi" / "16+ km" like most observations.
  String distance(double metres) {
    if (imperial) {
      final mi = metres / 1609.34;
      return mi >= 10 ? '10+ mi' : '${mi.toStringAsFixed(mi < 3 ? 1 : 0)} mi';
    }
    final km = metres / 1000;
    return km >= 16 ? '16+ km' : '${km.toStringAsFixed(km < 3 ? 1 : 0)} km';
  }

  /// A temperature *difference* in the user's unit (no offset applied).
  double tvDelta(double dc) => imperial ? dc * 9 / 5 : dc;

  // ---- place selection ----------------------------------------------------

  bool isSaved(Place p) => saved.any((s) => s.key == p.key);

  void selectPlace(Place p) {
    selected = p;
    data = _cache[p.key];
    error = null;
    alerts = [];
    nearby = NearbyThreats.none;
    normal = null;
    changes = const [];
    _prefs.setString('last', jsonEncode(p.toJson()));
    notifyListeners();
    unawaited(refresh());
  }

  Future<void> useMyLocation() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final p = await _location.current();
      selectPlace(p);
    } catch (e) {
      error = _msg(e);
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    final p = selected;
    if (p == null) return;
    final id = ++_req;
    _lastAttempt = DateTime.now();
    loading = true;
    error = null;
    notifyListeners();
    // Nearby hurricanes / quakes load alongside, but never hold up (or fail)
    // the weather.
    unawaited(refreshNearby());
    unawaited(refreshNormal());
    try {
      final results = await Future.wait([
        _weather.fetchRaw(p),
        _alertsService.active(p.lat, p.lon),
      ]);
      if (id != _req) return;
      final raw = results[0] as RawWeather;
      final d = raw.data;
      final a = results[1] as List<WeatherAlert>;
      // "Since you last looked": compare with the forecast we had, if it's
      // from a previous look (≥ 2 h old) rather than a quick re-refresh.
      final prev = _cache[p.key], prevAt = _updatedAt[p.key];
      if (prev != null &&
          prevAt != null &&
          DateTime.now().difference(prevAt) >= sinceLastLook) {
        final c = forecastChanges(prev, d);
        if (c.isNotEmpty) changes = c;
      }
      _cache[p.key] = d;
      data = d;
      alerts = a;
      final now = DateTime.now();
      _updatedAt[p.key] = now;
      _persistWeather(p, raw, now);

      if (hapticsEnabled) {
        unawaited(hapticsForCode(d.current.code));
      }
      if (notificationsEnabled) {
        unawaited(_notifyNewAlerts(a));
      }
      // Keep the home screen widget fresh whenever the app loads new data.
      unawaited(updateAtmosWidget(d, p.name, imperial));
    } catch (e) {
      if (id != _req) return;
      error = _msg(e);
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _notifyNewAlerts(List<WeatherAlert> current) async {
    // Re-read: the background worker may have recorded alerts since launch.
    final stored = _prefs.getStringList('seenAlerts') ?? const <String>[];
    final seen = {...stored, ..._seenAlertIds};
    final unseen = current.where((a) => !seen.contains(a.id)).toList();
    for (final a in unseen) {
      await _notifications.showAlert(a);
    }
    // Merge, never replace: replacing with just this place's ids used to
    // erase what the background worker had announced for other places, so
    // it would announce them again.
    final merged = mergeSeenAlerts(stored, current.map((a) => a.id));
    _seenAlertIds = merged.toSet();
    await _prefs.setStringList('seenAlerts', merged);
  }

  Future<List<Place>> search(String q) => _weather.search(q);

  void toggleSaved(Place p) {
    if (isSaved(p)) {
      saved.removeWhere((s) => s.key == p.key);
    } else {
      saved.add(p);
    }
    _persistSaved();
    notifyListeners();
  }

  void removePlace(Place p) {
    saved.removeWhere((s) => s.key == p.key);
    _persistSaved();
    notifyListeners();
  }

  void _persistSaved() {
    _prefs.setString(
      'saved',
      jsonEncode(saved.map((p) => p.toJson()).toList()),
    );
  }

  /// Drag-to-reorder in the Places list. The order is also the swipe order
  /// on the home screen. [newIndex] is where the item ends up (what
  /// ReorderableListView's `onReorderItem` reports).
  void reorderSaved(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= saved.length) return;
    newIndex = newIndex.clamp(0, saved.length - 1);
    if (newIndex == oldIndex) return;
    saved.insert(newIndex, saved.removeAt(oldIndex));
    _persistSaved();
    notifyListeners();
  }

  // ---- saved places at a glance ---------------------------------------------

  /// Current temperature / conditions for saved places (and the selected
  /// one), keyed by [Place.key]. Filled by [refreshBriefs].
  Map<String, PlaceBrief> briefs = {};
  DateTime? _briefsAt;

  /// Loads conditions for every saved place in a single request. Skips the
  /// network when the last answer is under 10 minutes old unless [force].
  Future<void> refreshBriefs({bool force = false}) async {
    if (saved.isEmpty) return;
    final at = _briefsAt;
    final fresh =
        at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 10) &&
        saved.every((p) => briefs.containsKey(p.key));
    if (fresh && !force) return;
    final b = await _weather.briefs(List.of(saved));
    if (b.isEmpty) return;
    briefs = {...briefs, ...b};
    _briefsAt = DateTime.now();
    notifyListeners();
  }

  // ---- settings -----------------------------------------------------------

  void toggleUnits() {
    imperial = !imperial;
    _prefs.setBool('imperial', imperial);
    // The home screen widget renders its own strings; redraw it in the new
    // units right away instead of waiting for the next background run.
    final d = data, p = selected;
    if (d != null && p != null) {
      unawaited(updateAtmosWidget(d, p.name, imperial));
    }
    notifyListeners();
  }

  // ---- forecast changes -----------------------------------------------------

  /// How old the previous forecast must be for differences to count as
  /// "since you last looked".
  static const sinceLastLook = Duration(hours: 2);

  /// Notable revisions since the forecast was last seen (e.g. tomorrow's
  /// high up 6°). Shown once; cleared by [dismissChanges].
  List<ForecastChange> changes = const [];

  void dismissChanges() {
    changes = const [];
    notifyListeners();
  }

  // ---- normal for the date --------------------------------------------------

  /// Typical high / low for today's date at the place on screen.
  DayNormal? normal;

  /// Loads the normal for the place's current date, from a per-place,
  /// per-day cache when possible (it only changes once a day).
  Future<void> refreshNormal() async {
    final p = selected, d = data;
    if (p == null) return;
    final date = d?.current.time ?? DateTime.now();
    final key = 'normal:${p.key}:${date.year}-${date.month}-${date.day}';
    try {
      final cached = _prefs.getString(key);
      if (cached != null) {
        normal = DayNormal.fromJson(jsonDecode(cached) as Map<String, dynamic>);
        notifyListeners();
        return;
      }
    } catch (_) {}
    final n = await ClimateService.normalFor(p, date);
    if (n == null || selected?.key != p.key) return;
    normal = n;
    try {
      // Keep only the latest normal per place.
      for (final k in _prefs.getKeys().where(
        (k) => k.startsWith('normal:${p.key}:'),
      )) {
        await _prefs.remove(k);
      }
      await _prefs.setString(key, jsonEncode(n.toJson()));
    } catch (_) {}
    notifyListeners();
  }

  // ---- nearby threats -------------------------------------------------------

  /// Tropical cyclones within 500 mi and M5+ quakes within 300 mi of the
  /// place on screen. Empty most of the time — that's the point.
  NearbyThreats nearby = NearbyThreats.none;
  bool loadingNearby = false;

  /// Something worth a badge on the Alerts button: an NWS alert for this
  /// place, or a nearby storm / quake.
  bool get hasAlerts => alerts.isNotEmpty || !nearby.isEmpty;

  Future<void> refreshNearby() async {
    final p = selected;
    if (p == null) return;
    loadingNearby = true;
    try {
      final n = await NearbyThreats.forPlace(p.lat, p.lon);
      // Ignore results for a place the user has already left.
      if (selected?.key == p.key) nearby = n;
    } catch (_) {
      // Keep whatever we had.
    }
    loadingNearby = false;
    notifyListeners();
  }

  // ---- offline cache --------------------------------------------------------

  final Map<String, DateTime> _updatedAt = {};

  /// When the data on screen was fetched (null before the first load).
  DateTime? get updatedAt => _updatedAt[selected?.key];

  /// True when the last refresh failed but older data is still on screen.
  bool get showingStale => error != null && data != null;

  /// Saves the raw API responses for the place on screen, so the next
  /// launch paints immediately (and works offline) instead of a spinner.
  void _persistWeather(Place p, RawWeather raw, DateTime at) {
    try {
      _prefs.setString(
        'wxLast',
        jsonEncode({
          'place': p.key,
          'forecast': raw.forecastJson,
          'air': raw.airJson,
          'at': at.millisecondsSinceEpoch,
        }),
      );
    } catch (_) {
      // Storage full or unavailable: the cache is a nicety, never fatal.
    }
  }

  /// Loads the saved forecast for [p], if it is the place that was cached.
  void _restoreWeather(Place p) {
    try {
      final s = _prefs.getString('wxLast');
      if (s == null) return;
      final j = jsonDecode(s) as Map<String, dynamic>;
      if (j['place'] != p.key) return;
      final d = WeatherService.parse(
        j['forecast'] as String,
        j['air'] as String?,
      );
      _cache[p.key] = d;
      data = d;
      _updatedAt[p.key] = DateTime.fromMillisecondsSinceEpoch(
        (j['at'] as num).toInt(),
      );
    } catch (_) {
      // Corrupt or outdated format: ignore and fetch fresh.
    }
  }

  // ---- swiping between saved places -------------------------------------

  /// Moves to the next (+1) or previous (-1) saved place, wrapping around.
  /// From a place that isn't saved, jumps to the first / last saved one.
  /// Returns false when there is nowhere to go.
  bool stepPlace(int dir) {
    if (saved.isEmpty) return false;
    final i = saved.indexWhere((p) => p.key == selected?.key);
    if (i == -1) {
      selectPlace(dir > 0 ? saved.first : saved.last);
      return true;
    }
    if (saved.length < 2) return false;
    selectPlace(saved[(i + dir) % saved.length]);
    return true;
  }

  void toggleHaptics() {
    hapticsEnabled = !hapticsEnabled;
    _prefs.setBool('haptics', hapticsEnabled);
    notifyListeners();
  }

  /// Daily 7 AM forecast notification (Android background worker). Off by
  /// default; needs notifications on.
  bool morningSummary = false;

  void toggleMorningSummary() {
    morningSummary = !morningSummary;
    _prefs.setBool('morningSummary', morningSummary);
    if (morningSummary) unawaited(_notifications.requestPermission());
    notifyListeners();
  }

  void toggleNotifications() {
    notificationsEnabled = !notificationsEnabled;
    _prefs.setBool('notifications', notificationsEnabled);
    if (notificationsEnabled) unawaited(_notifications.init());
    notifyListeners();
  }

  // ---- day / night theme ---------------------------------------------------

  bool _daytime = _deviceDaytime();
  Timer? _sunClock;

  /// Light theme between sunrise and sunset at the place on screen, dark at
  /// night. Before any forecast is loaded, falls back to the device clock.
  bool get isDaytime => _daytime;

  ThemeMode get themeMode => _daytime ? ThemeMode.light : ThemeMode.dark;

  static bool _deviceDaytime() {
    final h = DateTime.now().hour;
    return h >= 6 && h < 20;
  }

  bool _computeDaytime() {
    final d = data;
    if (d == null) return _deviceDaytime();
    return d.isDaylightNow(fetchedAt: updatedAt);
  }

  /// Updates [isDaytime] without notifying (callers notify right after).
  void _syncDaytime() => _daytime = _computeDaytime();

  /// Re-checks the sun every minute so the theme flips at sunrise/sunset
  /// while the app stays open.
  void _startSunClock() {
    _sunClock?.cancel();
    _sunClock = Timer.periodic(const Duration(minutes: 1), (_) {
      recheckDaytime();
      refreshIfStale();
    });
  }

  /// How old the forecast may get while the app sits open (a tablet on a
  /// stand, a browser tab) before it refreshes itself.
  static const autoRefreshAfter = Duration(minutes: 15);
  DateTime? _lastAttempt;

  /// Refreshes when the forecast on screen is older than
  /// [autoRefreshAfter] — and it has been that long since the last try, so
  /// an offline device retries every 15 minutes, not every tick.
  /// Returns whether a refresh was started.
  bool refreshIfStale({DateTime? now}) {
    if (selected == null || loading) return false;
    final t = now ?? DateTime.now();
    bool old(DateTime? at) =>
        at == null || t.difference(at) >= autoRefreshAfter;
    if (!old(updatedAt) || !old(_lastAttempt)) return false;
    unawaited(refresh());
    return true;
  }

  /// Re-evaluates day/night now; notifies only if it flipped.
  void recheckDaytime() {
    if (_computeDaytime() != _daytime) notifyListeners();
  }

  @override
  void notifyListeners() {
    _syncDaytime();
    super.notifyListeners();
  }

  @override
  void dispose() {
    _sunClock?.cancel();
    super.dispose();
  }

  String _msg(Object e) {
    final s = e.toString();
    if (e is TimeoutException) return 'The request timed out. Try again.';
    if (s.contains('SocketException') || s.contains('ClientException')) {
      return 'No internet connection.';
    }
    return s.replaceFirst('Exception: ', '');
  }
}

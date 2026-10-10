import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alert.dart';
import '../models/weather.dart';
import '../services/alerts_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/weather_service.dart';
import '../services/widget_service.dart';
import '../utils/haptics.dart';

class AppState extends ChangeNotifier {
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
  ThemeMode themeMode = ThemeMode.system;

  Set<String> _seenAlertIds = {};

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    imperial = _prefs.getBool('imperial') ?? true;
    hapticsEnabled = _prefs.getBool('haptics') ?? true;
    notificationsEnabled = _prefs.getBool('notifications') ?? true;
    themeMode = ThemeMode.values[_prefs.getInt('theme') ?? 0];
    _seenAlertIds = (_prefs.getStringList('seenAlerts') ?? []).toSet();

    if (notificationsEnabled) {
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
      unawaited(refresh());
    } else {
      unawaited(useMyLocation());
    }
  }

  // ---- units & formatting -------------------------------------------------

  double tv(double c) => imperial ? c * 9 / 5 + 32 : c;
  String temp(double c) => '${tv(c).round()}°';
  String wind(double kmh) =>
      imperial ? '${(kmh * 0.621371).round()} mph' : '${kmh.round()} km/h';
  String precip(double mm) =>
      imperial ? '${(mm / 25.4).toStringAsFixed(2)} in' : '${mm.toStringAsFixed(1)} mm';

  // ---- place selection ----------------------------------------------------

  bool isSaved(Place p) => saved.any((s) => s.key == p.key);

  void selectPlace(Place p) {
    selected = p;
    data = _cache[p.key];
    error = null;
    alerts = [];
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
    loading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _weather.fetch(p),
        _alertsService.active(p.lat, p.lon),
      ]);
      if (id != _req) return;
      final d = results[0] as WeatherData;
      final a = results[1] as List<WeatherAlert>;
      _cache[p.key] = d;
      data = d;
      alerts = a;

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
    final ids = current.map((a) => a.id).toSet();
    final unseen = current.where((a) => !_seenAlertIds.contains(a.id));
    for (final a in unseen) {
      await _notifications.showAlert(a);
    }
    // Keep only ids still active, plus anything new, so the set can't grow
    // forever and old alerts get re-notified if they somehow recur.
    _seenAlertIds = ids;
    await _prefs.setStringList('seenAlerts', _seenAlertIds.toList());
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
    _prefs.setString('saved', jsonEncode(saved.map((p) => p.toJson()).toList()));
  }

  // ---- settings -----------------------------------------------------------

  void toggleUnits() {
    imperial = !imperial;
    _prefs.setBool('imperial', imperial);
    notifyListeners();
  }

  void toggleHaptics() {
    hapticsEnabled = !hapticsEnabled;
    _prefs.setBool('haptics', hapticsEnabled);
    notifyListeners();
  }

  void toggleNotifications() {
    notificationsEnabled = !notificationsEnabled;
    _prefs.setBool('notifications', notificationsEnabled);
    if (notificationsEnabled) unawaited(_notifications.init());
    notifyListeners();
  }

  void cycleTheme() {
    themeMode = ThemeMode.values[(themeMode.index + 1) % ThemeMode.values.length];
    _prefs.setInt('theme', themeMode.index);
    notifyListeners();
  }

  String get themeLabel => switch (themeMode) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };

  String _msg(Object e) {
    final s = e.toString();
    if (e is TimeoutException) return 'The request timed out. Try again.';
    if (s.contains('SocketException') || s.contains('ClientException')) {
      return 'No internet connection.';
    }
    return s.replaceFirst('Exception: ', '');
  }
}

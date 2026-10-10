import 'package:home_widget/home_widget.dart';

import '../models/weather.dart';
import '../utils/weather_codes.dart';

/// Pushes the current conditions to the Android home screen widget.
/// No-op on other platforms.
Future<void> updateAtmosWidget(
    WeatherData data, String placeName, bool imperial) async {
  try {
    final c = data.current;
    final today = data.daily.isNotEmpty ? data.daily.first : null;
    final t = imperial
        ? '${(c.tempC * 9 / 5 + 32).round()}°'
        : '${c.tempC.round()}°';
    final hi = today == null
        ? ''
        : imperial
            ? 'H ${(today.maxC * 9 / 5 + 32).round()}°  L ${(today.minC * 9 / 5 + 32).round()}°'
            : 'H ${today.maxC.round()}°  L ${today.minC.round()}°';

    await HomeWidget.saveWidgetData<String>('place', placeName);
    await HomeWidget.saveWidgetData<String>('temp', t);
    await HomeWidget.saveWidgetData<String>('icon', _emoji(c.code, c.isDay));
    await HomeWidget.saveWidgetData<String>('condition', describe(c.code));
    await HomeWidget.saveWidgetData<String>('hilo', hi);
    await HomeWidget.updateWidget(
      name: 'AtmosWidgetProvider',
      androidName: 'AtmosWidgetProvider',
    );
  } catch (_) {
    // Widget may not be installed; never break the app over it.
  }
}

String _emoji(int code, bool day) {
  if (code == 0) return day ? '☀️' : '🌙';
  if (code == 1 || code == 2) return day ? '⛅' : '☁️';
  if (code == 3) return '☁️';
  if (code == 45 || code == 48) return '🌫️';
  if (code >= 51 && code <= 57) return '🌦️';
  if (code >= 61 && code <= 67) return '🌧️';
  if (code >= 71 && code <= 77) return '🌨️';
  if (code >= 80 && code <= 82) return '🌦️';
  if (code >= 85 && code <= 86) return '🌨️';
  if (code >= 95) return '⛈️';
  return '☁️';
}

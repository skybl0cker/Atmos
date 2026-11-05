import '../models/weather.dart';
import 'weather_codes.dart';

/// One short, practical suggestion for the day ("Bring an umbrella").
class DayTip {
  final String emoji;
  final String text;
  const DayTip(this.emoji, this.text);
}

/// Practical tips for the rest of today from the forecast, most useful
/// first, at most [max]. Temperatures are judged on "feels like" (°C).
List<DayTip> dayTips(WeatherData d, {int max = 3}) {
  final c = d.current;
  final today = d.daily.isNotEmpty ? d.daily.first : null;
  // Rest of the day = the next 12 hours of the hourly forecast.
  final next = d.hourly.take(12).toList();
  final tips = <DayTip>[];

  final stormy = c.code >= 95 || next.any((h) => h.code >= 95);
  final snowy = isSnowCode(c.code) || next.any((h) => isSnowCode(h.code));
  final wet =
      isRainCode(c.code) ||
      next.any((h) => h.precipProb >= 50 || h.precipMm >= 0.5) ||
      (today?.precipProb ?? 0) >= 60;

  if (stormy) {
    tips.add(const DayTip('⛈️', 'Storms possible — stay weather aware'));
  } else if (snowy) {
    tips.add(const DayTip('❄️', 'Snow around — allow extra travel time'));
  } else if (wet) {
    tips.add(const DayTip('☂️', 'Bring an umbrella'));
  }

  final feels = c.feelsC;
  if (feels <= 0) {
    tips.add(const DayTip('🧣', 'Bundle up — it’s freezing'));
  } else if (feels <= 10) {
    tips.add(const DayTip('🧥', 'Grab a warm jacket'));
  } else if (feels <= 16) {
    tips.add(const DayTip('🧶', 'Light layer weather'));
  } else if (feels >= 32) {
    tips.add(const DayTip('💧', 'Very hot — stay hydrated'));
  }

  if ((today?.uv ?? 0) >= 6 && c.isDay) {
    tips.add(const DayTip('🧴', 'High UV — wear sunscreen'));
  }
  if (c.windKmh >= 40) {
    tips.add(const DayTip('💨', 'Windy — secure loose items'));
  }
  final aqi = d.air?.usAqi;
  if (aqi != null && aqi > 100) {
    tips.add(const DayTip('😷', 'Poor air — limit time outdoors'));
  }

  if (tips.isEmpty && !wet && feels > 16 && feels < 29) {
    tips.add(
      DayTip(
        c.isDay ? '😎' : '🌙',
        c.isDay ? 'Great day to be outside' : 'Pleasant night out',
      ),
    );
  }
  return tips.take(max).toList();
}

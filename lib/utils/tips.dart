import 'package:intl/intl.dart' show DateFormat;

import '../models/weather.dart';
import 'insights.dart';
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

  // Storms: a thunderstorm code, or unstable air with rain around.
  final storm = c.code >= 95 ? StormRisk(c.time, strong: false) : stormRisk(d);
  final snowy = isSnowCode(c.code) || next.any((h) => isSnowCode(h.code));
  final wet =
      isRainCode(c.code) ||
      next.any((h) => h.precipProb >= 50 || h.precipMm >= 0.5) ||
      (today?.precipProb ?? 0) >= 60;

  if (storm != null) {
    final soon = storm.time.difference(c.time) < const Duration(hours: 1);
    final what = storm.strong ? 'Strong storms' : 'Thunderstorms';
    tips.add(
      DayTip(
        '⛈️',
        soon
            ? '$what nearby — stay weather aware'
            : '$what possible around ${DateFormat('h a').format(storm.time)}',
      ),
    );
  } else if (snowy) {
    tips.add(const DayTip('❄️', 'Snow around — allow extra travel time'));
  } else if (wet) {
    tips.add(const DayTip('☂️', 'Bring an umbrella'));
  }

  // Overnight cold over the next ~18 hours (air temperature, not feels).
  final coldest = d.hourly
      .take(18)
      .map((h) => h.tempC)
      .fold<double>(c.tempC, (a, b) => b < a ? b : a);
  // Rain or snow onto freezing ground: the most dangerous combination.
  if ((wet || snowy) && coldest <= 0) {
    tips.add(const DayTip('🧊', 'Icy roads possible — take it slow'));
  } else if (coldest <= 1 && c.tempC > 1) {
    // Only worth saying when it isn't already freezing.
    tips.add(const DayTip('🌱', 'Frost likely — cover tender plants'));
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

  // Sunscreen, with *when* it matters if the hourly UV says so.
  final uvw = uvWindow(d);
  if (uvw != null) {
    String h(DateTime t) => DateFormat('h a').format(t);
    tips.add(
      DayTip('🧴', 'UV high ${h(uvw.start)} – ${h(uvw.end)} — wear sunscreen'),
    );
  } else if ((today?.uv ?? 0) >= 6 && c.isDay) {
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

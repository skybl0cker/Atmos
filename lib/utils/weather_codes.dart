import 'package:flutter/material.dart';

String describe(int code) {
  switch (code) {
    case 0:
      return 'Clear sky';
    case 1:
      return 'Mainly clear';
    case 2:
      return 'Partly cloudy';
    case 3:
      return 'Overcast';
    case 45:
    case 48:
      return 'Fog';
    case 51:
    case 53:
    case 55:
      return 'Drizzle';
    case 56:
    case 57:
      return 'Freezing drizzle';
    case 61:
      return 'Light rain';
    case 63:
      return 'Rain';
    case 65:
      return 'Heavy rain';
    case 66:
    case 67:
      return 'Freezing rain';
    case 71:
      return 'Light snow';
    case 73:
      return 'Snow';
    case 75:
      return 'Heavy snow';
    case 77:
      return 'Snow grains';
    case 80:
    case 81:
    case 82:
      return 'Rain showers';
    case 85:
    case 86:
      return 'Snow showers';
    case 95:
      return 'Thunderstorm';
    case 96:
    case 99:
      return 'Thunderstorm with hail';
    default:
      return 'Unknown';
  }
}

IconData iconFor(int code, {bool day = true}) {
  if (code == 0 || code == 1) return day ? Icons.wb_sunny : Icons.nightlight_round;
  if (code == 2) return day ? Icons.wb_cloudy : Icons.cloud;
  if (code == 3) return Icons.cloud;
  if (code == 45 || code == 48) return Icons.blur_on;
  if (code >= 51 && code <= 67) return Icons.water_drop;
  if (code >= 71 && code <= 77) return Icons.ac_unit;
  if (code >= 80 && code <= 82) return Icons.water_drop;
  if (code == 85 || code == 86) return Icons.ac_unit;
  if (code >= 95) return Icons.thunderstorm;
  return Icons.cloud;
}

bool isDayHour(DateTime t) => t.hour >= 6 && t.hour < 20;

/// True when the (possibly synthesized) code is any kind of rain or drizzle.
bool isRainCode(int code) =>
    (code >= 51 && code <= 67) || (code >= 80 && code <= 82);

/// True when the code is any kind of snow.
bool isSnowCode(int code) =>
    (code >= 71 && code <= 77) || code == 85 || code == 86;

/// Open-Meteo's weather_code is model-synthesized and often lags reality —
/// it happily reports "overcast" (3) while precipitation is actively falling.
/// This blends the model code with measured precipitation (mm/hr) so the
/// displayed condition reflects what is actually happening. Everything
/// downstream — labels, icons, gradients, haptics — keys off this.
int synthesizeCode(int code, double precipMmPerHour) {
  if (precipMmPerHour <= 0) return code;
  final dry = code >= 0 && code <= 3;
  final drizzle = code >= 51 && code <= 57;
  if (!dry && !drizzle) {
    // Model already reports precipitation; only upgrade severity.
    if (precipMmPerHour > 7.5 &&
        (code == 61 || code == 63 || code == 80 || code == 81)) {
      return 65;
    }
    return code;
  }
  // Measured rain but the model thinks it is dry (or just drizzle):
  // grade by standard meteorological intensity bands.
  if (precipMmPerHour <= 0.5) return 53; // drizzle
  if (precipMmPerHour <= 2.5) return 61; // light rain
  if (precipMmPerHour <= 7.5) return 63; // moderate rain
  return 65; // heavy rain
}

List<Color> gradientFor(int code, bool day) {
  if (code >= 95) return const [Color(0xFF232526), Color(0xFF414345)];
  if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) {
    return day
        ? const [Color(0xFF4B6CB7), Color(0xFF182848)]
        : const [Color(0xFF141E30), Color(0xFF243B55)];
  }
  if ((code >= 71 && code <= 77) || code == 85 || code == 86) {
    return const [Color(0xFF8DA5C4), Color(0xFF5B7590)];
  }
  if (code == 45 || code == 48 || code == 3) {
    return day
        ? const [Color(0xFF757F9A), Color(0xFFA9B4C8)]
        : const [Color(0xFF2C3E50), Color(0xFF4B5B6B)];
  }
  return day
      ? const [Color(0xFF2E8BFF), Color(0xFF87CEFA)]
      : const [Color(0xFF0F2027), Color(0xFF2C5364)];
}

String compass(int deg) {
  const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  return dirs[((deg + 22.5) / 45).floor() % 8];
}

String uvLabel(double uv) {
  if (uv < 3) return 'Low';
  if (uv < 6) return 'Moderate';
  if (uv < 8) return 'High';
  if (uv < 11) return 'Very high';
  return 'Extreme';
}

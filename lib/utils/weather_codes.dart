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

/// Rough daytime test (6 AM – 8 PM) for when real sun times are unknown.
/// Prefer [isDaylightAt], which uses the forecast's sunrise and sunset.
bool isDayHour(DateTime t) => t.hour >= 6 && t.hour < 20;

/// Whether [t] falls between sunrise and sunset, using the daily forecast's
/// sun times for that calendar day. Falls back to [isDayHour] when the day
/// isn't in the forecast.
bool isDaylightAt(
  DateTime t,
  Iterable<({DateTime sunrise, DateTime sunset})> days,
) {
  for (final d in days) {
    if (d.sunrise.year == t.year &&
        d.sunrise.month == t.month &&
        d.sunrise.day == t.day) {
      return !t.isBefore(d.sunrise) && t.isBefore(d.sunset);
    }
  }
  return isDayHour(t);
}

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

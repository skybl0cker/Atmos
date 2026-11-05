import 'dart:convert';

/// Builds a synthetic Open-Meteo /v1/forecast response.
///
/// Times are local (timezone=auto style, no offset). "Now" is
/// 2026-11-05 14:00; hourly data starts at midnight so parsing has to skip
/// the past hours. Override per-hour values with the callbacks.
Map<String, dynamic> forecastJson({
  int currentCode = 0,
  double currentTemp = 20,
  double currentFeels = 20,
  double currentPrecip = 0,
  double windKmh = 10,
  int isDay = 1,
  int Function(int hour)? hourlyProb,
  double Function(int hour)? hourlyPrecip,
  int Function(int hour)? hourlyCode,
  double Function(int quarter)? minutelyPrecip,
  List<double> dailyMax = const [22, 24, 18],
  List<double> dailyMin = const [12, 13, 9],
  List<double> uv = const [4, 5, 2],
  List<int> dailyProb = const [10, 20, 60],
  double steerSpeed = 30,
  int steerDir = 270,
}) {
  String two(int v) => v.toString().padLeft(2, '0');
  final start = DateTime(2026, 11, 5);
  final hTimes = <String>[];
  for (var i = 0; i < 48; i++) {
    final t = start.add(Duration(hours: i));
    hTimes.add('${t.year}-${two(t.month)}-${two(t.day)}T${two(t.hour)}:00');
  }
  final mTimes = <String>[];
  for (var q = 0; q < 16; q++) {
    final t = DateTime(2026, 11, 5, 14).add(Duration(minutes: 15 * q));
    mTimes.add(
      '${t.year}-${two(t.month)}-${two(t.day)}T${two(t.hour)}:${two(t.minute)}',
    );
  }
  final days = ['2026-11-05', '2026-11-06', '2026-11-07'];
  return {
    'current': {
      'time': '2026-11-05T14:00',
      'interval': 900,
      'temperature_2m': currentTemp,
      'relative_humidity_2m': 60,
      'apparent_temperature': currentFeels,
      'is_day': isDay,
      'precipitation': currentPrecip,
      'weather_code': currentCode,
      'pressure_msl': 1013.2,
      'wind_speed_10m': windKmh,
      'wind_direction_10m': 225,
    },
    'hourly': {
      'time': hTimes,
      'temperature_2m': [for (var i = 0; i < 48; i++) 10 + (i % 24) * 0.5],
      'precipitation_probability': [
        for (var i = 0; i < 48; i++) hourlyProb?.call(i) ?? 0,
      ],
      'precipitation': [
        for (var i = 0; i < 48; i++) hourlyPrecip?.call(i) ?? 0.0,
      ],
      'weather_code': [for (var i = 0; i < 48; i++) hourlyCode?.call(i) ?? 1],
      for (final lvl in ['850hPa', '700hPa', '500hPa']) ...{
        'wind_speed_$lvl': [for (var i = 0; i < 48; i++) steerSpeed],
        'wind_direction_$lvl': [for (var i = 0; i < 48; i++) steerDir],
      },
    },
    'minutely_15': {
      'time': mTimes,
      'precipitation_probability': [for (var q = 0; q < 16; q++) 0],
      'precipitation': [
        for (var q = 0; q < 16; q++) minutelyPrecip?.call(q) ?? 0.0,
      ],
      'weather_code': [for (var q = 0; q < 16; q++) 3],
    },
    'daily': {
      'time': days,
      'weather_code': [1, 2, 61],
      'temperature_2m_max': dailyMax,
      'temperature_2m_min': dailyMin,
      'sunrise': [for (final d in days) '${d}T07:03'],
      'sunset': [for (final d in days) '${d}T17:35'],
      'uv_index_max': uv,
      'precipitation_probability_max': dailyProb,
    },
  };
}

String forecastBody({int currentCode = 0}) =>
    jsonEncode(forecastJson(currentCode: currentCode));

const airBody =
    '{"current":{"us_aqi":42,"pm2_5":8.1,"pm10":12.3,"ozone":60.0,"nitrogen_dioxide":5.5}}';

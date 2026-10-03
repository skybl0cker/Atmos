import '../utils/weather_codes.dart';

class Place {
  final String name;
  final String? region;
  final String? country;
  final double lat;
  final double lon;
  final bool isCurrent;

  const Place({
    required this.name,
    this.region,
    this.country,
    required this.lat,
    required this.lon,
    this.isCurrent = false,
  });

  String get key => '${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';

  String get subtitle => [region, country]
      .where((s) => s != null && s.isNotEmpty)
      .join(', ');

  factory Place.fromGeocoding(Map<String, dynamic> j) => Place(
        name: j['name'] as String,
        region: j['admin1'] as String?,
        country: j['country'] as String?,
        lat: (j['latitude'] as num).toDouble(),
        lon: (j['longitude'] as num).toDouble(),
      );

  factory Place.fromJson(Map<String, dynamic> j) => Place(
        name: j['name'] as String,
        region: j['region'] as String?,
        country: j['country'] as String?,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        isCurrent: j['isCurrent'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'region': region,
        'country': country,
        'lat': lat,
        'lon': lon,
        'isCurrent': isCurrent,
      };
}

class CurrentWeather {
  final DateTime time;
  final double tempC;
  final double feelsC;
  final double humidity;
  final double windKmh;
  final int windDir;
  final double pressure;
  final double precipMm;
  final int code;
  final bool isDay;

  const CurrentWeather({
    required this.time,
    required this.tempC,
    required this.feelsC,
    required this.humidity,
    required this.windKmh,
    required this.windDir,
    required this.pressure,
    required this.precipMm,
    required this.code,
    required this.isDay,
  });
}

class HourlyPoint {
  final DateTime time;
  final double tempC;
  final int precipProb;
  final double precipMm;
  final int code;

  const HourlyPoint({
    required this.time,
    required this.tempC,
    required this.precipProb,
    required this.precipMm,
    required this.code,
  });
}

/// 15-minute nowcast point for the next 4 hours.
class MinutelyPoint {
  final DateTime time;
  final int precipProb;
  final double precipMm;
  final int code;

  const MinutelyPoint({
    required this.time,
    required this.precipProb,
    required this.precipMm,
    required this.code,
  });
}

class DailyPoint {
  final DateTime date;
  final int code;
  final double maxC;
  final double minC;
  final DateTime sunrise;
  final DateTime sunset;
  final double uv;
  final int precipProb;

  const DailyPoint({
    required this.date,
    required this.code,
    required this.maxC,
    required this.minC,
    required this.sunrise,
    required this.sunset,
    required this.uv,
    required this.precipProb,
  });
}

class AirQuality {
  final int usAqi;
  final double pm25;
  final double pm10;
  final double ozone;
  final double no2;

  const AirQuality({
    required this.usAqi,
    required this.pm25,
    required this.pm10,
    required this.ozone,
    required this.no2,
  });

  static AirQuality? tryParse(Map<String, dynamic> j) {
    final c = j['current'] as Map<String, dynamic>?;
    final aqi = c?['us_aqi'] as num?;
    if (c == null || aqi == null) return null;
    double n(dynamic v) => (v as num?)?.toDouble() ?? 0;
    return AirQuality(
      usAqi: aqi.round(),
      pm25: n(c['pm2_5']),
      pm10: n(c['pm10']),
      ozone: n(c['ozone']),
      no2: n(c['nitrogen_dioxide']),
    );
  }
}

class WeatherData {
  final CurrentWeather current;
  final List<HourlyPoint> hourly;
  final List<MinutelyPoint> minutely;
  final List<DailyPoint> daily;
  final AirQuality? air;

  const WeatherData({
    required this.current,
    required this.hourly,
    required this.minutely,
    required this.daily,
    this.air,
  });

  WeatherData withAir(AirQuality? a) => WeatherData(
        current: current,
        hourly: hourly,
        minutely: minutely,
        daily: daily,
        air: a,
      );

  /// Time until rain starts at the current location, or null when nothing is
  /// expected in the next two hours. Based on the 15-minute nowcast rather
  /// than the (often wrong) model weather code.
  Duration? get rainStartsIn {
    if (isRainCode(current.code) || current.precipMm > 0) return null;
    final now = current.time;
    for (final m in minutely) {
      final dt = m.time.difference(now);
      if (dt.isNegative || dt > const Duration(hours: 2)) continue;
      if (m.precipMm > 0.2 || m.precipProb >= 60) return dt;
    }
    return null;
  }

  /// Expected peak precipitation rate (mm/hr) over the next two hours.
  double get nowcastPeakMm {
    double peak = 0;
    final end = current.time.add(const Duration(hours: 2));
    for (final m in minutely) {
      if (m.time.isAfter(current.time) && !m.time.isAfter(end)) {
        if (m.precipMm > peak) peak = m.precipMm;
      }
    }
    return peak;
  }

  factory WeatherData.fromJson(Map<String, dynamic> j) {
    double n(dynamic v) => (v as num?)?.toDouble() ?? 0;
    int i(dynamic v) => (v as num?)?.toInt() ?? 0;

    final c = j['current'] as Map<String, dynamic>;
    final h = j['hourly'] as Map<String, dynamic>;
    final d = j['daily'] as Map<String, dynamic>;

    // current.precipitation is accumulated over the current interval
    // (usually 15 minutes), so convert it to an hourly rate for grading.
    final intervalSec = (c['interval'] as num?)?.toDouble() ?? 3600.0;
    final currentPrecipMm = n(c['precipitation']);
    final currentRate = currentPrecipMm * 3600.0 / intervalSec;
    final currentCode = synthesizeCode(i(c['weather_code']), currentRate);

    final current = CurrentWeather(
      time: DateTime.parse(c['time'] as String),
      tempC: n(c['temperature_2m']),
      feelsC: n(c['apparent_temperature']),
      humidity: n(c['relative_humidity_2m']),
      windKmh: n(c['wind_speed_10m']),
      windDir: i(c['wind_direction_10m']),
      pressure: n(c['pressure_msl']),
      precipMm: currentPrecipMm,
      code: currentCode,
      isDay: i(c['is_day']) == 1,
    );

    final hTimes = (h['time'] as List).cast<String>();
    final hTemp = h['temperature_2m'] as List;
    final hProb = h['precipitation_probability'] as List;
    final hCode = h['weather_code'] as List;
    final hPrecip = (h['precipitation'] as List?) ?? [];
    final startOfHour = DateTime(current.time.year, current.time.month,
        current.time.day, current.time.hour);

    final hourly = <HourlyPoint>[];
    for (var k = 0; k < hTimes.length && hourly.length < 24; k++) {
      final t = DateTime.parse(hTimes[k]);
      if (t.isBefore(startOfHour)) continue;
      final mm = k < hPrecip.length ? n(hPrecip[k]) : 0.0; // per-hour = mm/hr
      hourly.add(HourlyPoint(
        time: t,
        tempC: n(hTemp[k]),
        precipProb: i(hProb[k]),
        precipMm: mm,
        code: synthesizeCode(i(hCode[k]), mm),
      ));
    }

    // 15-minute nowcast (next ~2 hours). Per-interval accumulations are
    // converted to mm/hr so thresholds match the hourly bands.
    final minutely = <MinutelyPoint>[];
    final m15 = j['minutely_15'] as Map<String, dynamic>?;
    if (m15 != null) {
      final mTimes = ((m15['time'] as List?) ?? const []).cast<String>();
      final mProb = ((m15['precipitation_probability'] as List?) ?? const []);
      final mPrecip = ((m15['precipitation'] as List?) ?? const []);
      final mCode = ((m15['weather_code'] as List?) ?? const []);
      for (var k = 0; k < mTimes.length; k++) {
        final t = DateTime.parse(mTimes[k]);
        if (t.isBefore(startOfHour)) continue;
        final rate = (k < mPrecip.length ? n(mPrecip[k]) : 0.0) * 4.0;
        minutely.add(MinutelyPoint(
          time: t,
          precipProb: k < mProb.length ? i(mProb[k]) : 0,
          precipMm: rate,
          code: synthesizeCode(k < mCode.length ? i(mCode[k]) : 3, rate),
        ));
      }
    }

    final dTimes = (d['time'] as List).cast<String>();
    final daily = <DailyPoint>[
      for (var k = 0; k < dTimes.length; k++)
        DailyPoint(
          date: DateTime.parse(dTimes[k]),
          code: i((d['weather_code'] as List)[k]),
          maxC: n((d['temperature_2m_max'] as List)[k]),
          minC: n((d['temperature_2m_min'] as List)[k]),
          sunrise: DateTime.parse((d['sunrise'] as List)[k] as String),
          sunset: DateTime.parse((d['sunset'] as List)[k] as String),
          uv: n((d['uv_index_max'] as List)[k]),
          precipProb: i((d['precipitation_probability_max'] as List)[k]),
        ),
    ];

    return WeatherData(
        current: current, hourly: hourly, minutely: minutely, daily: daily);
  }
}

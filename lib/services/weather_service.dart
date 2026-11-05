import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/weather.dart';

/// A parsed forecast plus the raw response bodies it came from, so the app
/// can cache them for offline / instant start.
class RawWeather {
  final WeatherData data;
  final String forecastJson;
  final String? airJson;
  const RawWeather(this.data, this.forecastJson, this.airJson);
}

class WeatherService {
  static const _timeout = Duration(seconds: 15);

  Future<String> _forecast(Place p) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': p.lat.toString(),
      'longitude': p.lon.toString(),
      'current': 'temperature_2m,relative_humidity_2m,apparent_temperature,'
          'is_day,precipitation,weather_code,pressure_msl,'
          'wind_speed_10m,wind_direction_10m',
      'hourly': 'temperature_2m,precipitation_probability,precipitation,weather_code,'
          'wind_speed_850hPa,wind_direction_850hPa,'
          'wind_speed_700hPa,wind_direction_700hPa,'
          'wind_speed_500hPa,wind_direction_500hPa',
      'minutely_15': 'precipitation_probability,precipitation,weather_code',
      'forecast_minutely_15': '16',
      'daily': 'weather_code,temperature_2m_max,temperature_2m_min,'
          'sunrise,sunset,uv_index_max,precipitation_probability_max',
      'timezone': 'auto',
      'forecast_days': '14',
    });
    final r = await http.get(uri).timeout(_timeout);
    if (r.statusCode != 200) {
      throw Exception('Weather service error (${r.statusCode})');
    }
    return r.body;
  }

  /// Builds [WeatherData] from raw forecast / air-quality bodies (fresh or
  /// cached). Throws if the forecast body is malformed.
  static WeatherData parse(String forecastJson, String? airJson) {
    final w = WeatherData.fromJson(
        jsonDecode(forecastJson) as Map<String, dynamic>);
    AirQuality? air;
    if (airJson != null) {
      try {
        air = AirQuality.tryParse(jsonDecode(airJson) as Map<String, dynamic>);
      } catch (_) {
        air = null;
      }
    }
    return w.withAir(air);
  }

  Future<RawWeather> fetchRaw(Place p) async {
    final airFuture = _air(p);
    final f = await _forecast(p);
    final a = await airFuture;
    return RawWeather(parse(f, a), f, a);
  }

  Future<WeatherData> fetch(Place p) async => (await fetchRaw(p)).data;

  /// Raw air-quality body, or null when unavailable (never throws).
  Future<String?> _air(Place p) async {
    try {
      final uri = Uri.https('air-quality-api.open-meteo.com', '/v1/air-quality', {
        'latitude': p.lat.toString(),
        'longitude': p.lon.toString(),
        'current': 'us_aqi,pm10,pm2_5,ozone,nitrogen_dioxide',
        'timezone': 'auto',
      });
      final r = await http.get(uri).timeout(_timeout);
      if (r.statusCode != 200) return null;
      return r.body;
    } catch (_) {
      return null;
    }
  }

  Future<List<Place>> search(String query) async {
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': query,
      'count': '8',
      'language': 'en',
      'format': 'json',
    });
    final r = await http.get(uri).timeout(_timeout);
    if (r.statusCode != 200) {
      throw Exception('Search error (${r.statusCode})');
    }
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final results = (body['results'] as List?) ?? [];
    return results
        .map((e) => Place.fromGeocoding(e as Map<String, dynamic>))
        .toList();
  }
}

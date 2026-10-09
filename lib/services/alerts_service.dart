import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/alert.dart';

/// US National Weather Service active alerts (watches/warnings/advisories).
/// Free, no key. US coverage only — returns an empty list elsewhere.
/// Docs: https://www.weather.gov/documentation/services-web-api
class AlertsService {
  Future<List<WeatherAlert>> active(double lat, double lon) async {
    final uri = Uri.https('api.weather.gov', '/alerts/active', {
      'point': '${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}',
    });
    try {
      final r = await http
          .get(uri, headers: {'User-Agent': 'Atmos weather app (contact: skybl0cker@gmail.com)'})
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return [];
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final features = (body['features'] as List?) ?? [];
      return features
          .map((e) => WeatherAlert.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

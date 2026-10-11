import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../models/weather.dart';

class LocationService {
  /// Placeholder used when a human-readable name can't be resolved.
  static const placeholderName = 'My location';

  Future<Place> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Location services are turned off.');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      throw Exception('Location permission was denied.');
    }
    if (perm == LocationPermission.deniedForever) {
      throw Exception(
          'Location permission is blocked. Enable it in system settings.');
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 15),
      ),
    );
    // Resolve a real place name ("Knoxville, TN") so the home header,
    // notifications, and the home widget never read "My location".
    final name = await resolvePlaceName(pos.latitude, pos.longitude);
    return Place(
      name: name,
      lat: pos.latitude,
      lon: pos.longitude,
      isCurrent: true,
    );
  }

  /// Reverse-geocodes coordinates into a short display name like
  /// "Knoxville, TN" (US) or "Paris, France". Never throws — returns
  /// [placeholderName] when the lookup fails or is inconclusive.
  ///
  /// Uses BigDataCloud's free client-side reverse-geocode API (no key,
  /// CORS-friendly, works on every platform including web).
  Future<String> resolvePlaceName(double lat, double lon) async {
    try {
      // api-bdc.io is BigDataCloud's current host (api.bigdatacloud.net
      // 307-redirects here); calling it directly skips the redirect hop.
      final uri =
          Uri.https('api-bdc.io', '/data/reverse-geocode-client', {
        'latitude': '$lat',
        'longitude': '$lon',
        'localityLanguage': 'en',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return placeholderName;
      final j = jsonDecode(res.body) as Map<String, dynamic>;

      String? city = (j['city'] as String?)?.trim();
      if (city == null || city.isEmpty) {
        city = (j['locality'] as String?)?.trim();
      }
      if (city == null || city.isEmpty) return placeholderName;

      if (j['countryCode'] == 'US') {
        // principalSubdivisionCode looks like "US-TN".
        final sub = j['principalSubdivisionCode'] as String?;
        final state =
            (sub != null && sub.contains('-')) ? sub.split('-').last : null;
        if (state != null && state.isNotEmpty) return '$city, $state';
        return city;
      }
      final country = (j['countryName'] as String?)?.trim();
      if (country != null && country.isNotEmpty) return '$city, $country';
      return city;
    } catch (_) {
      return placeholderName;
    }
  }
}

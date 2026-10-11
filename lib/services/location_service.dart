import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../models/weather.dart';

class LocationService {
  /// Placeholder used when a human-readable name can't be resolved.
  static const placeholderName = 'My location';

  /// Names that are technically correct but useless to a human — e.g.
  /// BigDataCloud reports unincorporated Knox County as "District 6".
  /// Places carrying one of these get re-resolved on next launch.
  static final _junkName =
      RegExp(r'^(district|precinct|ward|census tract|tract)\s+[\d.]+$',
          caseSensitive: false);

  static bool isPlaceholderName(String name) =>
      name == placeholderName || _junkName.hasMatch(name.trim());

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
    // Resolve a real place name ("Hardin Valley, TN") so the home header,
    // notifications, and the home widget never read "My location".
    final name = await resolvePlaceName(pos.latitude, pos.longitude);
    return Place(
      name: name,
      lat: pos.latitude,
      lon: pos.longitude,
      isCurrent: true,
    );
  }

  /// Reverse-geocodes coordinates into a short community-level display name
  /// like "Hardin Valley, TN". Never throws — returns [placeholderName]
  /// when every lookup fails or is inconclusive.
  Future<String> resolvePlaceName(double lat, double lon) async {
    // 1. OpenStreetMap Nominatim at zoom 13 — the best free source of
    //    community/suburb-level names ("Hardin Valley", not "District 6").
    final community = await _nominatimCommunity(lat, lon);
    if (community != null) return community;
    // 2. BigDataCloud fallback (city-level, no key needed).
    return _bigDataCloudName(lat, lon);
  }

  /// Most-specific community name from Nominatim, or null.
  Future<String?> _nominatimCommunity(double lat, double lon) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': '$lat',
        'lon': '$lon',
        'format': 'jsonv2',
        'zoom': '13', // community/suburb level
        'addressdetails': '1',
      });
      final res = await http.get(uri, headers: {
        // Nominatim usage policy requires an identifying User-Agent.
        'User-Agent':
            'AtmosWeatherApp/1.0 (https://github.com/skybl0cker/Atmos)',
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final addr = j['address'] as Map<String, dynamic>?;
      if (addr == null) return null;

      String? name;
      for (final key in const [
        'suburb',
        'neighbourhood',
        'quarter',
        'hamlet',
        'village',
        'town',
        'municipality',
        'city',
      ]) {
        final v = (addr[key] as String?)?.trim();
        if (v != null && v.isNotEmpty && !isPlaceholderName(v)) {
          name = v;
          break;
        }
      }
      if (name == null) return null;

      final countryCode =
          (addr['country_code'] as String?)?.trim().toUpperCase();
      if (countryCode == 'US') {
        // ISO3166-2-lvl4 looks like "US-TN".
        final iso = addr['ISO3166-2-lvl4'] as String?;
        final state =
            (iso != null && iso.contains('-')) ? iso.split('-').last : null;
        if (state != null && state.isNotEmpty) return '$name, $state';
        return name;
      }
      final country = (addr['country'] as String?)?.trim();
      if (country != null && country.isNotEmpty) return '$name, $country';
      return name;
    } catch (_) {
      return null;
    }
  }

  /// City-level fallback via BigDataCloud's free client-side API (no key,
  /// CORS-friendly, works on every platform including web).
  Future<String> _bigDataCloudName(double lat, double lon) async {
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
      if (city == null || city.isEmpty || isPlaceholderName(city)) {
        city = (j['locality'] as String?)?.trim();
      }
      if (city == null || city.isEmpty || isPlaceholderName(city)) {
        return placeholderName;
      }

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

import 'dart:math' as math;

import 'tropical_service.dart';
import 'usgs_service.dart';

/// Only threats close enough to matter for the place on screen.
const stormRadiusMi = 500.0;
const quakeRadiusMi = 300.0;
const quakeMinMag = 5.0;

/// Great-circle distance in miles.
double milesBetween(double lat1, double lon1, double lat2, double lon2) {
  const r = 3958.8; // Earth radius, miles
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(a)));
}

class NearbyStorm {
  final TropicalStorm storm;
  final double miles;
  const NearbyStorm(this.storm, this.miles);
}

class NearbyQuake {
  final Earthquake quake;
  final double miles;
  const NearbyQuake(this.quake, this.miles);
}

/// Tropical cyclones within [stormRadiusMi] and M[quakeMinMag]+ earthquakes
/// within [quakeRadiusMi] (past week) of a place, nearest first.
class NearbyThreats {
  final List<NearbyStorm> storms;
  final List<NearbyQuake> quakes;
  const NearbyThreats({this.storms = const [], this.quakes = const []});

  static const none = NearbyThreats();

  bool get isEmpty => storms.isEmpty && quakes.isEmpty;
  int get count => storms.length + quakes.length;

  /// Filters raw feeds down to what is near ([lat], [lon]). Pure, so the
  /// radius rules are testable without the network.
  factory NearbyThreats.filter(
    double lat,
    double lon, {
    required List<TropicalStorm> storms,
    required List<Earthquake> quakes,
  }) {
    final s =
        [
            for (final t in storms)
              NearbyStorm(t, milesBetween(lat, lon, t.lat, t.lon)),
          ].where((n) => n.miles <= stormRadiusMi).toList()
          ..sort((a, b) => a.miles.compareTo(b.miles));
    final q =
        [
            for (final e in quakes)
              if (e.mag >= quakeMinMag)
                NearbyQuake(
                  e,
                  milesBetween(
                    lat,
                    lon,
                    e.location.latitude,
                    e.location.longitude,
                  ),
                ),
          ].where((n) => n.miles <= quakeRadiusMi).toList()
          ..sort((a, b) => a.miles.compareTo(b.miles));
    return NearbyThreats(storms: s, quakes: q);
  }

  /// Fetches both feeds for a place. Never throws.
  static Future<NearbyThreats> forPlace(double lat, double lon) async {
    final results = await Future.wait([
      TropicalService.activeStorms(),
      UsgsService.nearby(
        lat,
        lon,
        radiusKm: quakeRadiusMi * 1.609,
        minMag: quakeMinMag,
      ),
    ]);
    return NearbyThreats.filter(
      lat,
      lon,
      storms: results[0] as List<TropicalStorm>,
      quakes: results[1] as List<Earthquake>,
    );
  }
}

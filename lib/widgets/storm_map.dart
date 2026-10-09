import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Situation-room map for a tropical cyclone: best-track trail, current
/// position, and NWS warning polygons.
class StormMap extends StatelessWidget {
  final String name;
  final LatLng position;
  final List<LatLng> trail;
  final List<List<LatLng>> warningPolygons;
  final double height;

  const StormMap({
    super.key,
    required this.name,
    required this.position,
    required this.trail,
    this.warningPolygons = const [],
    this.height = 260,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: position,
            initialZoom: 5,
            minZoom: 3,
            maxZoom: 10,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.skycast',
            ),
            if (warningPolygons.isNotEmpty)
              PolygonLayer(
                polygons: [
                  for (final ring in warningPolygons)
                    Polygon(
                      points: ring,
                      color: Colors.red.withAlpha(50),
                      borderColor: Colors.red.withAlpha(160),
                      borderStrokeWidth: 2,
                    ),
                ],
              ),
            if (trail.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: trail,
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                  Polyline(
                    points: trail,
                    color: Colors.lightBlueAccent,
                    strokeWidth: 1.5,
                  ),
                ],
              ),
            MarkerLayer(markers: [
              Marker(
                point: position,
                width: 44,
                height: 44,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black54, blurRadius: 6)
                    ],
                  ),
                  child: const Icon(Icons.cyclone,
                      color: Colors.white, size: 24),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Converts NWS alert GeoJSON geometry to flutter_map polygon rings.
List<List<LatLng>> warningRings(List<Map<String, dynamic>> features) {
  final rings = <List<LatLng>>[];
  for (final f in features) {
    final geom =
        (f['geometry'] as Map?)?.cast<String, dynamic>();
    if (geom == null) continue;
    final type = geom['type'] as String?;
    final coords = geom['coordinates'] as List?;
    if (coords == null) continue;
    try {
      if (type == 'Polygon') {
        for (final ring in coords) {
          rings.add(_ring(ring as List));
        }
      } else if (type == 'MultiPolygon') {
        for (final poly in coords) {
          for (final ring in (poly as List)) {
            rings.add(_ring(ring as List));
          }
        }
      }
    } catch (_) {
      continue;
    }
  }
  return rings;
}

List<LatLng> _ring(List coords) => [
      for (final p in coords)
        LatLng(p[1].toDouble(), p[0].toDouble()),
    ];

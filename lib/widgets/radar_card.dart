import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/weather.dart';
import '../screens/radar_screen.dart';
import '../services/radar_service.dart';
import '../state/app_state.dart';
import 'glass_card.dart';

// Matches the darkened basemap on the full radar screen.
const _darkTiles = ColorFilter.matrix(<double>[
  -0.15, -0.295, -0.055, 0, 149.5,
  -0.15, -0.295, -0.055, 0, 154.5,
  -0.15, -0.295, -0.055, 0, 165.5,
  0, 0, 0, 1, 0,
]);
const _userAgent = 'com.example.skycast';

class RadarCard extends StatelessWidget {
  const RadarCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final place = s.selected;
    if (place == null) return const SizedBox.shrink();
    final minutely = s.data?.minutely ?? const [];
    final windKmh = s.data?.steeringWindKmh ?? 0;
    final windDir = s.data?.steeringWindDir ?? 0;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => RadarScreen(
                place: place,
                minutely: minutely,
                windKmh: windKmh,
                windDir: windDir)),
      ),
      child: GlassCard(
        title: 'Radar',
        icon: Icons.radar,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RadarPreview(key: ValueKey(place.key), place: place),
            const SizedBox(height: 10),
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'Live radar with +30/+60 min forecast frames and a 4-hour rain outlook',
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A small, non-interactive snapshot of the current radar frame — the "now"
/// picture. Tapping anywhere on the card opens the full radar screen.
class _RadarPreview extends StatefulWidget {
  final Place place;
  const _RadarPreview({super.key, required this.place});

  @override
  State<_RadarPreview> createState() => _RadarPreviewState();
}

class _RadarPreviewState extends State<_RadarPreview> {
  RadarFrame? _frame;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final frames = await RadarService.fetchFrames();
      if (!mounted) return;
      final i = frames.lastIndexWhere((f) => !f.isForecast);
      setState(() => _frame = i >= 0 ? frames[i] : frames.last);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = LatLng(widget.place.lat, widget.place.lon);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 150,
        child: _frame == null
            ? Container(
                color: Colors.black26,
                child: Center(
                  child: Icon(
                    _failed ? Icons.cloud_off_outlined : Icons.radar,
                    color: Colors.white54,
                    size: 32,
                  ),
                ),
              )
            : Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 8,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      ColorFiltered(
                        colorFilter: _darkTiles,
                        child: TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: _userAgent,
                        ),
                      ),
                      Opacity(
                        opacity: 0.85,
                        child: TileLayer(
                          urlTemplate: _frame!.tileUrl,
                          userAgentPackageName: _userAgent,
                        ),
                      ),
                      MarkerLayer(markers: [
                        Marker(
                          point: center,
                          width: 14,
                          height: 14,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.orangeAccent,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ]),
                    ],
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(150),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _frame!.label,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

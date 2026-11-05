import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/weather.dart';
import '../state/app_state.dart';
import '../services/hrrr_service.dart';
import '../services/radar_service.dart';
import '../utils/layout.dart';
import '../utils/radar_legend.dart';
import '../widgets/nowcast_strip.dart';
import '../widgets/scene.dart';
import '../widgets/scene_page.dart';

const _accent = Color(0xFF6C63FF);

// Change this to match your applicationId when you rename the app.
const _userAgent = 'com.skybl0cker.atmos';
const _startZoom = 7.0;
const _speeds = [0.5, 1.0, 2.0, 4.0];
const _baseFrameMs = 600;

/// Darkens the light OpenStreetMap basemap so radar colors stand out.
const _darkTiles = ColorFilter.matrix(<double>[
  -0.15, -0.295, -0.055, 0, 149.5,
  -0.15, -0.295, -0.055, 0, 154.5,
  -0.15, -0.295, -0.055, 0, 165.5,
  0, 0, 0, 1, 0,
]);
const _noFilter = ColorFilter.mode(Colors.transparent, BlendMode.dst);

class RadarScreen extends StatefulWidget {
  final Place place;
  final List<MinutelyPoint> minutely;
  final double windKmh;
  final int windDir;
  const RadarScreen({
    super.key,
    required this.place,
    this.minutely = const [],
    this.windKmh = 0,
    this.windDir = 0,
  });

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  final _map = MapController();
  List<RadarFrame> _frames = [];
  bool _failed = false;

  late int _index = 0;
  bool _playing = false;
  /// Map style follows day/night at the place (light by day, dark at
  /// night); tapping the toggle overrides it for this visit.
  bool? _darkOverride;
  bool get _dark =>
      _darkOverride ?? !context.read<AppState>().isDaytime;
  double _opacity = 0.8;
  double _zoom = _startZoom;
  double _speed = 1.0;
  int _hold = 0;
  Timer? _timer;
  StreamSubscription? _mapSub;
  final Set<int> _visited = {};

  @override
  void initState() {
    super.initState();
    _mapSub = _map.mapEventStream.listen((_) {
      final z = _map.camera.zoom;
      if (z != _zoom) setState(() => _zoom = z);
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      var frames = await RadarService.fetchFrames();
      // HRRR simulated reflectivity: the single unified "future radar"
      // model, from the earliest available frame out to +6 h.
      frames = RadarService.addHrrrForecast(
          frames, await HrrrService.forecastFrames());
      if (!mounted) return;
      setState(() {
        _frames = frames;
        // Start playback at "Now" — the newest past (non-forecast) frame.
        _index = _frames.lastIndexWhere((f) => !f.isForecast);
        if (_index < 0) _index = _frames.length - 1;
        _visited.add(_index);
        _mountRest();
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  // Mount the remaining frames one at a time so the free tile server isn't
  // hit with a burst of concurrent requests.
  void _mountRest() {
    Timer.periodic(const Duration(milliseconds: 300), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      int? next;
      for (var i = _frames.length - 1; i >= 0; i--) {
        if (!_visited.contains(i)) {
          next = i;
          break;
        }
      }
      if (next == null) {
        t.cancel();
        return;
      }
      setState(() => _visited.add(next!));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _mapSub?.cancel();
    _map.dispose();
    super.dispose();
  }

  void _show(int i) => setState(() {
        _index = i;
        _visited.add(i);
      });

  void _step(int d) => _show((_index + d) % _frames.length);

  void _tick() {
    if (_index == _frames.length - 1 && _hold < 2) {
      _hold++;
      return;
    }
    _hold = 0;
    _step(1);
  }

  void _togglePlay() {
    if (_playing) {
      _timer?.cancel();
      setState(() => _playing = false);
      return;
    }
    setState(() => _playing = true);
    _timer = Timer.periodic(
        Duration(milliseconds: (_baseFrameMs / _speed).round()), (_) => _tick());
  }

  void _setSpeed(double v) {
    setState(() => _speed = v);
    if (_playing) {
      _timer?.cancel();
      _timer = Timer.periodic(
          Duration(milliseconds: (_baseFrameMs / _speed).round()),
          (_) => _tick());
    }
  }

  String _speedLabel(double v) => v % 1 == 0 ? '${v.toInt()}×' : '$v×';

  /// Badge for the current frame: observed past has no badge, and HRRR
  /// simulated reflectivity is MODEL.
  String _frameBadge(RadarFrame f) {
    if (f.isModel) return 'MODEL';
    return 'FORECAST';
  }

  bool get _ready => _frames.isNotEmpty && _visited.length == _frames.length;

  @override
  Widget build(BuildContext context) {
    final p = widget.place;
    final center = LatLng(p.lat, p.lon);
    final pal = SheetPalette.of(context);
    // Rebuild (and re-pick the map style) when day turns to night.
    context.select<AppState, bool>((s) => s.isDaytime);

    final gutter = centeredGutter(context, min: 14);
    final header = SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 0),
        child: Row(
          children: [
            RoundIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back',
              solid: true,
              onTap: () => Navigator.maybePop(context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: pal.bg,
                  borderRadius: BorderRadius.circular(21),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 12,
                        offset: Offset(0, 4)),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.radar, color: _accent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Radar · ${p.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: pal.ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            RoundIconButton(
              icon: _dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              tooltip: _dark ? 'Light map' : 'Dark map',
              solid: true,
              onTap: () => setState(() => _darkOverride = !_dark),
            ),
            const SizedBox(width: 8),
            RoundIconButton(
              icon: Icons.refresh_rounded,
              tooltip: 'Refresh',
              solid: true,
              onTap: _failed
                  ? () {
                      setState(() => _failed = false);
                      unawaited(_load());
                    }
                  : null,
            ),
          ],
        ),
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: pal.bg,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _body(context, center, pal),
            Positioned(top: 0, left: 0, right: 0, child: header),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, LatLng center, SheetPalette pal) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final wide = isWide(context);
    final gutter = centeredGutter(context, min: 14);
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 44, color: pal.faint),
              const SizedBox(height: 12),
              Text(
                'Could not load radar frames. Check your connection and tap refresh.',
                textAlign: TextAlign.center,
                style: TextStyle(color: pal.soft),
              ),
            ],
          ),
        ),
      );
    }
    if (_frames.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: _accent));
    }

    final sliders = SliderTheme.of(context).copyWith(
      activeTrackColor: _accent,
      inactiveTrackColor: pal.track,
      thumbColor: _accent,
      overlayColor: _accent.withAlpha(30),
      trackHeight: 4,
      activeTickMarkColor: Colors.transparent,
      inactiveTickMarkColor: Colors.transparent,
    );
    final f = _frames[_index];

    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: center,
            initialZoom: _startZoom,
            minZoom: 3,
            maxZoom: 12,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            ColorFiltered(
              colorFilter: _dark ? _darkTiles : _noFilter,
              child: TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: _userAgent,
              ),
            ),
            for (final i in _visited)
              AnimatedOpacity(
                opacity: i == _index ? _opacity : 0,
                duration: const Duration(milliseconds: 200),
                child: _frames[i].isModel
                    ? TileLayer(
                        // HRRR simulated reflectivity — a model
                        // forecast, rendered as-is (no advection).
                        key: ValueKey(_frames[i].key),
                        urlTemplate: _frames[i].tileUrl,
                        userAgentPackageName: _userAgent,
                      )
                    : TileLayer(
                        // RainViewer tiles top out at native zoom 7;
                        // scale up beyond that instead of requesting
                        // unsupported zooms.
                        key: ValueKey(_frames[i].key),
                        urlTemplate: _frames[i].tileUrl,
                        userAgentPackageName: _userAgent,
                        maxNativeZoom: 7,
                      ),
              ),
            MarkerLayer(markers: [
              Marker(
                point: center,
                width: 24,
                height: 24,
                child: Container(
                  decoration: BoxDecoration(
                    color: _accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3.5),
                    boxShadow: const [
                      BoxShadow(color: Colors.black38, blurRadius: 8)
                    ],
                  ),
                ),
              ),
            ]),
          ],
        ),
        Positioned(
          left: gutter,
          top: top + 62,
          child: const _Legend(),
        ),
        if (!_ready)
          Positioned(
            top: top + 56,
            left: 70,
            right: 70,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                minHeight: 3,
                color: _accent,
                backgroundColor: pal.track,
                value: _visited.length / _frames.length,
              ),
            ),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Padding(
                padding: EdgeInsets.only(right: gutter, bottom: 12),
                child: RoundIconButton(
                  icon: Icons.my_location_rounded,
                  tooltip: 'Back to my place',
                  solid: true,
                  onTap: () => _map.move(center, _startZoom),
                ),
              ),
              Container(
                width: double.infinity,
                // Big screens: a centered, width-capped floating panel so
                // the controls don't stretch across the whole map.
                margin: wide
                    ? EdgeInsets.fromLTRB(gutter, 0, gutter, 16)
                    : EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: pal.bg,
                  borderRadius: wide
                      ? BorderRadius.circular(32)
                      : const BorderRadius.vertical(top: Radius.circular(32)),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0x33000000),
                        blurRadius: 24,
                        offset: Offset(0, wide ? 8 : -6)),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(16, 16, 16, 6 + bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.minutely.isNotEmpty) ...[
                      NowcastStrip(minutely: widget.minutely, hours: 4),
                      const SizedBox(height: 14),
                    ],
                    Row(
                      children: [
                        Text(f.label,
                            style: TextStyle(
                                color: pal.ink,
                                fontSize: 17,
                                fontWeight: FontWeight.w600)),
                        if (f.isForecast) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: (f.isModel
                                      ? const Color(0xFFB36BD1)
                                      : const Color(0xFF3F8CFF))
                                  .withAlpha(34),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(_frameBadge(f),
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                    color: f.isModel
                                        ? const Color(0xFFB36BD1)
                                        : const Color(0xFF3F8CFF))),
                          ),
                        ],
                        const Spacer(),
                        Icon(Icons.opacity_rounded, size: 16, color: pal.soft),
                        SizedBox(
                          width: 96,
                          child: SliderTheme(
                            data: sliders,
                            child: Slider(
                              value: _opacity,
                              min: 0.2,
                              max: 1,
                              onChanged: (v) => setState(() => _opacity = v),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous frame',
                          icon: Icon(Icons.skip_previous_rounded,
                              color: pal.ink),
                          onPressed: () => _step(-1),
                        ),
                        IconButton.filled(
                          tooltip: _playing ? 'Pause' : 'Play',
                          style: IconButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: pal.track,
                          ),
                          icon: Icon(_playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded),
                          onPressed: _ready ? _togglePlay : null,
                        ),
                        IconButton(
                          tooltip: 'Next frame',
                          icon:
                              Icon(Icons.skip_next_rounded, color: pal.ink),
                          onPressed: () => _step(1),
                        ),
                        PopupMenuButton<double>(
                          tooltip: 'Playback speed',
                          initialValue: _speed,
                          onSelected: _setSpeed,
                          itemBuilder: (_) => [
                            for (final sp in _speeds)
                              PopupMenuItem(
                                value: sp,
                                child: Text(
                                  '${_speedLabel(sp)} speed',
                                  style: TextStyle(
                                    fontWeight: sp == _speed
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                          ],
                          child: Container(
                            margin: const EdgeInsets.only(left: 2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: pal.card,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _speedLabel(_speed),
                              style: TextStyle(
                                color: pal.ink,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: sliders,
                            child: Slider(
                              min: 0,
                              max: (_frames.length - 1).toDouble(),
                              divisions: _frames.length > 1
                                  ? _frames.length - 1
                                  : null,
                              value: _index.toDouble(),
                              onChanged: (v) => _show(v.round()),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Center(
                      child: Text('© OpenStreetMap · Radar: RainViewer',
                          style: TextStyle(color: pal.soft, fontSize: 10)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final pal = SheetPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: pal.bg.withAlpha(235),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Intensity',
              style: TextStyle(
                  color: pal.ink, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          for (final s in radarLegendStops)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: s.color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(s.label,
                      style: TextStyle(color: pal.soft, fontSize: 10)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

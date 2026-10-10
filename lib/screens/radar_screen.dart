import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/weather.dart';
import '../services/echo_motion.dart';
import '../services/hrrr_service.dart';
import '../services/radar_service.dart';
import '../state/app_state.dart';
import '../utils/radar_legend.dart';

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
  bool _dark = true;
  double _opacity = 0.8;
  double _zoom = _startZoom;
  double _speed = 1.0;
  int _hold = 0;
  Timer? _timer;
  StreamSubscription? _mapSub;
  final Set<int> _visited = {};

  /// Measured echo motion (null until the background estimate finishes, or
  /// when the scene has too little echo to track). Estimated frames advect
  /// along this when present, else the model steering wind.
  EchoMotion? _echoMotion;

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
      // RainViewer's own nowcast is often unavailable — fall back to
      // wind-advected estimated frames so the future is still visible.
      frames = RadarService.addEstimatedForecast(
          frames, widget.windKmh, widget.windDir);
      // Then HRRR simulated reflectivity: the model "future radar" from
      // +90 min out to +6 h.
      frames = RadarService.addHrrrForecast(
          frames, await HrrrService.forecastFrames());
      if (!mounted) return;
      setState(() {
        _frames = frames;
        _echoMotion = null; // re-measured below; never steer new frames stale
        // Start playback at "Now" — the newest past (non-forecast) frame.
        _index = _frames.lastIndexWhere((f) => !f.isForecast);
        if (_index < 0) _index = _frames.length - 1;
        _visited.add(_index);
        _mountRest();
      });
      // Measure what the echoes actually did between the last two frames;
      // runs in the background and upgrades the estimated frames when done.
      unawaited(_estimateMotion());
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// Cross-correlates the last two observed radar tiles to measure real
  /// echo motion. On success the estimated frames advect along the measured
  /// vector (added even if the model wind was too calm to trigger them);
  /// on failure the model steering wind remains in effect.
  Future<void> _estimateMotion() async {
    final past = _frames.where((f) => !f.isForecast).toList();
    if (past.length < 2) return;
    final a = past[past.length - 2];
    final b = past[past.length - 1];
    final m = await EchoMotionService.estimate(
      tileUrlA: a.tileUrlAt(widget.place.lat, widget.place.lon, 7),
      tileUrlB: b.tileUrlAt(widget.place.lat, widget.place.lon, 7),
      dtSeconds: (b.timeUtc - a.timeUtc).toDouble(),
      lat: widget.place.lat,
    );
    if (!mounted || m == null) return;
    setState(() {
      _echoMotion = m;
      final before = _frames.length;
      _frames = RadarService.addEstimatedForecast(
          _frames, widget.windKmh, widget.windDir,
          force: true);
      for (var i = before; i < _frames.length; i++) {
        _visited.add(i);
      }
      _index = _index.clamp(0, _frames.length - 1).toInt();
    });
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

  String _speedLabel(double v) => v % 1 == 0 ? '${v.toInt()}×' : '${v}×';

  /// Honest caption for the estimated frames: measured echo motion when the
  /// cross-correlation succeeded, otherwise the model steering wind.
  String _motionSourceLabel() {
    final m = _echoMotion;
    if (m != null) {
      return 'measured echo motion · ${m.speedKmh.round()} km/h';
    }
    return 'model steering wind';
  }

  /// Badge for the current frame: observed past has no badge, RainViewer
  /// nowcast is FORECAST, advected frames are ESTIMATED, and HRRR
  /// simulated reflectivity is MODEL.
  String _frameBadge(RadarFrame f) {
    if (f.isModel) return 'MODEL';
    if (f.estimated) return 'ESTIMATED';
    return 'FORECAST';
  }

  bool get _ready => _frames.isNotEmpty && _visited.length == _frames.length;

  /// Screen-pixel shift for an estimated frame: advect the echo for the
  /// frame's lead time along the *measured* echo motion when available,
  /// else the layer-mean model steering wind. Open-Meteo's wind direction
  /// follows the meteorological convention (direction the wind comes FROM),
  /// so the motion vector points 180° away.
  Offset _advectionOffset(RadarFrame f) {
    if (!f.estimated || f.leadMinutes <= 0) return Offset.zero;
    final leadSec = f.leadMinutes * 60.0;
    double eastM, northM;
    final m = _echoMotion;
    if (m != null) {
      eastM = m.eastMs * leadSec;
      northM = m.northMs * leadSec;
    } else {
      final distM = (widget.windKmh / 3.6) * leadSec;
      final toRad = ((widget.windDir + 180) % 360) * math.pi / 180;
      eastM = distM * math.sin(toRad); // east positive
      northM = distM * math.cos(toRad); // north positive
    }
    final latRad = widget.place.lat * math.pi / 180;
    final mpp = 156543.03392 * math.cos(latRad) / math.pow(2, _zoom);
    return Offset(eastM / mpp, -northM / mpp);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.place;
    final center = LatLng(p.lat, p.lon);

    return Scaffold(
      appBar: AppBar(
        title: Text('Radar · ${p.name}'),
        actions: [
          IconButton(
            tooltip: _dark ? 'Light map' : 'Dark map',
            icon: Icon(_dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () => setState(() => _dark = !_dark),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _failed
                ? () {
                    setState(() => _failed = false);
                    unawaited(_load());
                  }
                : null,
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (_failed) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Could not load radar frames. Check your connection and tap refresh.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (_frames.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
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
                          : _frames[i].estimated
                              ? Opacity(
                                  opacity: 0.55,
                                  child: Transform.translate(
                                    offset: _advectionOffset(_frames[i]),
                                    child: TileLayer(
                                      key: ValueKey(_frames[i].key),
                                      urlTemplate: _frames[i].tileUrl,
                                      userAgentPackageName: _userAgent,
                                      maxNativeZoom: 7,
                                    ),
                                  ),
                                )
                              : TileLayer(
                                  // RainViewer tiles top out at native
                                  // zoom 7; scale up beyond that instead of
                                  // requesting unsupported zooms.
                                  key: ValueKey(_frames[i].key),
                                  urlTemplate: _frames[i].tileUrl,
                                  userAgentPackageName: _userAgent,
                                  maxNativeZoom: 7,
                                ),
                    ),
                  MarkerLayer(markers: [
                    Marker(
                      point: center,
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, blurRadius: 6)
                          ],
                        ),
                      ),
                    ),
                  ]),
                  const SimpleAttributionWidget(
                    source: Text('© OpenStreetMap · Radar: RainViewer'),
                  ),
                ],
              ),
              if (!_ready)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    value: _visited.length / _frames.length,
                  ),
                ),
              const Positioned(
                left: 12,
                top: 12,
                child: _Legend(),
              ),
              Positioned(
                right: 12,
                bottom: 260,
                child: FloatingActionButton.small(
                  heroTag: 'recenter',
                  tooltip: 'Back to my place',
                  onPressed: () => _map.move(center, _startZoom),
                  child: const Icon(Icons.my_location),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.minutely.isNotEmpty)
                          _NowcastStrip(minutely: widget.minutely),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                            child: Container(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(26),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                    color: Colors.white.withAlpha(45)),
                              ),
                              child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Text(_frames[_index].label,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                    fontWeight: FontWeight.w700)),
                                        if (_frames[_index].isForecast) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.withAlpha(40),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                  color: Colors.blueAccent),
                                            ),
                                            child: Text(
                                                _frameBadge(_frames[_index]),
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color: _frames[_index]
                                                            .isModel
                                                        ? Colors
                                                            .purpleAccent
                                                        : Colors
                                                            .lightBlueAccent)),
                                          ),
                                        ],
                                        if (_frames[_index].estimated) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            _motionSourceLabel(),
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.white54),
                                          ),
                                        ],
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        const Icon(Icons.opacity, size: 16),
                                        SizedBox(
                                          width: 90,
                                          child: Slider(
                                            value: _opacity,
                                            min: 0.2,
                                            max: 1,
                                            onChanged: (v) =>
                                                setState(() => _opacity = v),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.skip_previous),
                                      onPressed: () => _step(-1),
                                    ),
                                    IconButton.filled(
                                      icon: Icon(_playing
                                          ? Icons.pause
                                          : Icons.play_arrow),
                                      onPressed: _ready ? _togglePlay : null,
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.skip_next),
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
                                                    ? FontWeight.w700
                                                    : FontWeight.w400,
                                              ),
                                            ),
                                          ),
                                      ],
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 10),
                                        child: Text(
                                          _speedLabel(_speed),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Slider(
                                        min: 0,
                                        max: (_frames.length - 1).toDouble(),
                                        divisions: _frames.length - 1,
                                        value: _index.toDouble(),
                                        onChanged: (v) => _show(v.round()),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                              ),
                            ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Precipitation expected over the next 4 hours in 15-minute steps, from the
/// Open-Meteo nowcast — the "what's coming" view radar tiles can't show.
class _NowcastStrip extends StatelessWidget {
  final List<MinutelyPoint> minutely;
  const _NowcastStrip({required this.minutely});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final peak =
        minutely.fold<double>(0, (m, p) => p.precipMm > m ? p.precipMm : m);
    return Card(
      color: Theme.of(context).cardColor.withAlpha(235),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Next 4 hours',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SizedBox(
              height: 44,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < minutely.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Tooltip(
                          message:
                              '${DateFormat('h:mm a').format(minutely[i].time)} · ${minutely[i].precipProb}% · ${s.precip(minutely[i].precipMm)}/h',
                          child: Container(
                            height: peak <= 0
                                ? 2
                                : 2 +
                                    40 *
                                        (minutely[i].precipMm / peak).clamp(0, 1),
                            decoration: BoxDecoration(
                              color: minutely[i].precipMm > 0
                                  ? Colors.lightBlueAccent
                                  : Colors.white.withAlpha(40),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (minutely.isNotEmpty)
                  Text(DateFormat('h a').format(minutely.first.time),
                      style: const TextStyle(fontSize: 10, color: Colors.white70)),
                if (minutely.length > 8)
                  Text(DateFormat('h a').format(minutely[7].time),
                      style: const TextStyle(fontSize: 10, color: Colors.white70)),
                if (minutely.isNotEmpty)
                  Text(DateFormat('h a').format(minutely.last.time),
                      style: const TextStyle(fontSize: 10, color: Colors.white70)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).cardColor.withAlpha(230),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Intensity',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            for (final s in radarLegendStops)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 10, height: 10, color: s.color),
                    const SizedBox(width: 2),
                    Text(s.label, style: const TextStyle(fontSize: 10)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

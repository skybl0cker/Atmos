import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/radio_stations.dart';
import '../widgets/scene.dart';
import '../widgets/scene_page.dart';

const _accent = Color(0xFF6C63FF);

class RadioScreen extends StatefulWidget {
  const RadioScreen({super.key});

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  final _player = AudioPlayer();
  final _searchCtrl = TextEditingController();
  RadioStation? _current;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _player.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _play(RadioStation s) async {
    setState(() {
      _current = s;
      _loading = true;
      _error = null;
    });
    try {
      await _player.setUrl(s.url);
      await _player.play();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _current = null;
        _error =
            'Could not connect to ${s.label}. This is a volunteer-run stream — try another station.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _stop() async {
    await _player.stop();
    setState(() => _current = null);
  }

  @override
  Widget build(BuildContext context) {
    final pal = SheetPalette.of(context);
    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? radioStations
        : radioStations
              .where(
                (s) =>
                    s.city.toLowerCase().contains(q) ||
                    s.state.toLowerCase().contains(q) ||
                    s.callsign.toLowerCase().contains(q),
              )
              .toList();

    return ScenePage(
      title: 'Weather Radio',
      subtitle: '${radioStations.length} NOAA relay stations',
      sceneHeight: 0.3,
      header: SceneSearchField(
        controller: _searchCtrl,
        hint: 'Search state, city or callsign…',
        onChanged: (_) => setState(() {}),
      ),
      bottomBar: AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        child: _current == null
            ? const SizedBox(width: double.infinity)
            : _NowPlaying(station: _current!, loading: _loading, onStop: _stop),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _accent.withAlpha(pal.dark ? 40 : 18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: _accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Volunteer-relayed feeds, not official NOAA streams. Can lag up to 2 min '
                    '— not a substitute for a real weather alert radio.',
                    style: TextStyle(fontSize: 12, height: 1.4, color: pal.ink),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFFF4D5E), fontSize: 13),
              ),
            ),
          SheetLabel(q.isEmpty ? 'All stations' : '${filtered.length} matches'),
          for (final s in filtered)
            SheetRow(
              icon: _current?.callsign == s.callsign
                  ? Icons.graphic_eq_rounded
                  : Icons.radio_rounded,
              iconColor: _current?.callsign == s.callsign
                  ? _accent
                  : const Color(0xFF22B07D),
              title: s.label,
              subtitle: s.callsign,
              highlighted: _current?.callsign == s.callsign,
              trailing: _current?.callsign == s.callsign
                  ? (_loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _accent,
                            ),
                          )
                        : const Icon(
                            Icons.stop_circle_rounded,
                            color: _accent,
                            size: 28,
                          ))
                  : Icon(
                      Icons.play_circle_outline_rounded,
                      color: pal.faint,
                      size: 28,
                    ),
              onTap: () =>
                  _current?.callsign == s.callsign ? _stop() : _play(s),
            ),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No stations match "$q".',
                textAlign: TextAlign.center,
                style: TextStyle(color: pal.soft),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pinned "now playing" pill with live equalizer bars.
class _NowPlaying extends StatelessWidget {
  final RadioStation station;
  final bool loading;
  final VoidCallback onStop;
  const _NowPlaying({
    required this.station,
    required this.loading,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final pal = SheetPalette.of(context);
    return ColoredBox(
      color: pal.bg,
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(14, 6, 14, 12),
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              colors: [Color(0xFF7C6CFF), Color(0xFF4F8DFF)],
            ),
            boxShadow: [
              BoxShadow(
                color: _accent.withAlpha(80),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const _Equalizer(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loading ? 'Connecting…' : 'Now playing',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      station.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Stop',
                onPressed: onStop,
                icon: const Icon(Icons.stop_rounded, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withAlpha(50),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Equalizer extends StatefulWidget {
  const _Equalizer();

  @override
  State<_Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<_Equalizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 4; i++)
              Container(
                width: 3.5,
                height:
                    6 +
                    14 *
                        (0.5 +
                            0.5 * math.sin(_c.value * 2 * math.pi + i * 1.7)),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/weather.dart';
import '../services/severe_event_service.dart';
import '../state/app_state.dart';
import '../utils/aqi.dart';
import '../utils/haptics.dart';
import '../utils/weather_codes.dart';
import '../widgets/air_quality_card.dart';
import '../widgets/app_drawer.dart';
import '../widgets/aurora_background.dart';
import '../widgets/daily_list.dart';
import '../widgets/radar_card.dart';
import '../widgets/radio_card.dart';
import 'event_screen.dart';
import 'forecast_screen.dart';
import 'radar_screen.dart';
import 'search_screen.dart';

const _white70 = Colors.white70;
const _white = Colors.white;

/// Bento home: a grid of live tiles over the aurora. Tapping a tile dives
/// into its full screen. No tab bar — navigation is by tile.
class HomeScreen extends StatelessWidget {
  final SevereEvent? event;
  const HomeScreen({super.key, this.event});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        drawer: const AppDrawer(),
        appBar: _appBar(context, s),
        body: _body(context, s),
      ),
    );
  }

  AppBar _appBar(BuildContext context, AppState s) {
    final p = s.selected;
    return AppBar(
      backgroundColor: Colors.transparent,
      foregroundColor: _white,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      ),
      title: p == null
          ? const Text('Atmos',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                if (s.data != null)
                  Text(DateFormat.jm().format(s.data!.current.time),
                      style:
                          const TextStyle(fontSize: 12, color: _white70)),
              ],
            ),
      actions: [
        if (p != null && !p.isCurrent)
          IconButton(
            tooltip: s.isSaved(p) ? 'Remove from saved' : 'Save place',
            icon: Icon(s.isSaved(p) ? Icons.star : Icons.star_border),
            onPressed: () => s.toggleSaved(p),
          ),
        IconButton(
          tooltip: 'Add a place',
          icon: const Icon(Icons.add),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SearchScreen()),
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, AppState s) {
    final d = s.data;
    if (d == null) {
      if (s.loading) {
        return const Center(child: CircularProgressIndicator(color: _white));
      }
      return _Message(
        icon: Icons.cloud_off,
        text: s.error ?? 'Welcome to Atmos',
        actions: [
          FilledButton.icon(
            onPressed: s.selected == null ? s.useMyLocation : s.refresh,
            icon: const Icon(Icons.my_location),
            label: const Text('Use my location'),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: _white),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SearchScreen())),
            icon: const Icon(Icons.search),
            label: const Text('Search for a city'),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: s.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          if (s.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('${s.error} Showing last update.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.amberAccent)),
            ),
          if (s.loading)
            const LinearProgressIndicator(
                minHeight: 2,
                color: _white,
                backgroundColor: Colors.transparent),
          const _HeroTile(),
          const SizedBox(height: 12),
          _RadarTile(place: s.selected!),
          const SizedBox(height: 12),
          const _HourlyTile(),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _EventTile(event: event)),
              const SizedBox(width: 12),
              const Expanded(child: _AirTile()),
            ],
          ),
          const SizedBox(height: 12),
          const _ForecastTile(),
          const SizedBox(height: 12),
          const _DetailsBento(),
          const SizedBox(height: 12),
          const RadioCard(),
        ],
      ),
    );
  }
}

/// Frosted bento tile. Tapping dives into [destination].
class _BentoTile extends StatelessWidget {
  final Widget child;
  final Widget? destination;
  final String? semanticLabel;
  const _BentoTile({required this.child, this.destination, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final tile = FrostPanel(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      child: child,
    );
    if (destination == null) return tile;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => destination!),
      ),
      child: tile,
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final List<Widget> actions;
  const _Message(
      {required this.icon, required this.text, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: _white70),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _white, fontSize: 16)),
            const SizedBox(height: 20),
            Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center,
                children: actions),
          ],
        ),
      ),
    );
  }
}

/// Big hero tile: current temp, condition, high/low.
class _HeroTile extends StatelessWidget {
  const _HeroTile();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = s.data!.current;
    final today = s.data!.daily.first;
    final raining = isRainCode(c.code);
    final startIn = s.data!.rainStartsIn;

    return _BentoTile(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (raining && !hapticsSupported) ...[
                const _RainPulse(),
                const SizedBox(width: 8),
              ],
              Icon(iconFor(c.code, day: c.isDay), size: 22, color: _white),
              const SizedBox(width: 8),
              Text(describe(c.code),
                  style: const TextStyle(
                      fontSize: 20, color: _white, fontWeight: FontWeight.w600)),
            ],
          ),
          if (startIn != null) ...[
            const SizedBox(height: 8),
            _NowcastChip(startIn: startIn),
          ],
          const SizedBox(height: 4),
          Text(s.temp(c.tempC).replaceAll('°', ''),
              style: const TextStyle(
                  fontSize: 96, fontWeight: FontWeight.w200, color: _white, height: 1.0)),
          Text('Feels like ${s.temp(c.feelsC)}',
              style: const TextStyle(color: _white70, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.arrow_upward, size: 14, color: _white70),
              Text(' ${s.temp(today.maxC)}   ',
                  style: const TextStyle(
                      color: _white, fontWeight: FontWeight.w600)),
              const Icon(Icons.arrow_downward, size: 14, color: _white70),
              Text(' ${s.temp(today.minC)}',
                  style: const TextStyle(
                      color: _white, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Live radar tile — taps through to the full radar screen.
class _RadarTile extends StatelessWidget {
  final Place place;
  const _RadarTile({required this.place});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return _BentoTile(
      destination: RadarScreen(
        place: place,
        minutely: s.data?.minutely ?? const [],
        windKmh: s.data?.steeringWindKmh ?? 0,
        windDir: s.data?.steeringWindDir ?? 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.radar, size: 15, color: _white70),
            SizedBox(width: 6),
            Text('RADAR',
                style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.2,
                    color: _white70,
                    fontWeight: FontWeight.w600)),
            Spacer(),
            Icon(Icons.arrow_forward_ios, size: 14, color: _white70),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
                height: 150,
                child: RadarPreview(
                    key: ValueKey(place.key), place: place)),
          ),
        ],
      ),
    );
  }
}

class _HourlyTile extends StatelessWidget {
  const _HourlyTile();

  @override
  Widget build(BuildContext context) {
    return const _BentoTile(child: _HourlyStrip());
  }
}

class _HourlyStrip extends StatelessWidget {
  const _HourlyStrip();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final hours = s.data!.hourly.take(12).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(children: [
          Icon(Icons.schedule, size: 15, color: _white70),
          SizedBox(width: 6),
          Text('HOURLY',
              style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: _white70,
                  fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: hours.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final h = hours[i];
              return Container(
                width: 58,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(i == 0 ? 40 : 16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(i == 0 ? 'Now' : DateFormat('h a').format(h.time),
                        style:
                            const TextStyle(color: _white70, fontSize: 11)),
                    Icon(iconFor(h.code, day: isDayHour(h.time)),
                        color: _white, size: 22),
                    Text(s.temp(h.tempC),
                        style: const TextStyle(
                            color: _white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Severe-weather tile: live threat or all-clear. Taps to EventScreen.
class _EventTile extends StatelessWidget {
  final SevereEvent? event;
  const _EventTile({this.event});

  @override
  Widget build(BuildContext context) {
    final e = event;
    final active = e != null && e.kind != SevereKind.none;
    return _BentoTile(
      destination: const EventScreen(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
                active ? e.tabIcon : Icons.check_circle_outline,
                size: 15,
                color: active
                    ? (e.color ?? Colors.redAccent)
                    : Colors.greenAccent),
            const SizedBox(width: 6),
            const Text('SEVERE WX',
                style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.2,
                    color: _white70,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          Text(active ? e.tabLabel : 'All clear',
              style: const TextStyle(
                  color: _white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(active ? 'Tap for details' : 'No active threats',
              style: const TextStyle(color: _white70, fontSize: 12)),
          const SizedBox(height: 26),
        ],
      ),
    );
  }
}

class _AirTile extends StatelessWidget {
  const _AirTile();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final air = s.data?.air;
    final lvl = air == null ? null : aqiLevel(air.usAqi);
    return _BentoTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.eco_outlined, size: 15, color: _white70),
            SizedBox(width: 6),
            Text('AIR',
                style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.2,
                    color: _white70,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          Text(air == null ? '—' : '${air.usAqi.round()}',
              style: const TextStyle(
                  color: _white, fontSize: 32, fontWeight: FontWeight.w600)),
          Text(lvl?.label ?? 'No data',
              style: const TextStyle(color: _white70, fontSize: 12)),
          const SizedBox(height: 26),
        ],
      ),
    );
  }
}

/// 7-day tile — taps through to the full 14-day forecast.
class _ForecastTile extends StatelessWidget {
  const _ForecastTile();

  @override
  Widget build(BuildContext context) {
    return const _BentoTile(
      destination: ForecastScreen(),
      child: DailyList(title: '7-day forecast'),
    );
  }
}

/// Small detail tiles in a 2-column bento grid.
class _DetailsBento extends StatelessWidget {
  const _DetailsBento();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = s.data!.current;
    final today = s.data!.daily.first;
    final tiles = [
      _MiniTile(Icons.water_drop_outlined, 'HUMIDITY', '${c.humidity.round()}%'),
      _MiniTile(Icons.air, 'WIND', s.wind(c.windKmh)),
      _MiniTile(Icons.wb_sunny_outlined, 'UV', today.uv.round().toString()),
      _MiniTile(Icons.speed, 'PRESSURE', '${c.pressure.round()}'),
      _MiniTile(Icons.umbrella_outlined, 'PRECIP', s.precip(c.precipMm)),
      _MiniTile(Icons.thermostat, 'FEELS', s.temp(c.feelsC)),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.9,
      children: tiles,
    );
  }
}

class _MiniTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _MiniTile(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return FrostPanel(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: _white70),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.0,
                    color: _white70,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 6),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 22, color: _white, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _NowcastChip extends StatelessWidget {
  final Duration startIn;
  const _NowcastChip({required this.startIn});

  String get label {
    final m = startIn.inMinutes;
    if (m < 1) return 'Rain starting now';
    if (m < 60) return 'Rain in ~$m min';
    final h = startIn.inHours;
    final rem = m % 60;
    return rem == 0 ? 'Rain in ~$h hr' : 'Rain in ~${h}h ${rem}m';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.water_drop, size: 14, color: _white),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: _white, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _RainPulse extends StatefulWidget {
  const _RainPulse();

  @override
  State<_RainPulse> createState() => _RainPulseState();
}

class _RainPulseState extends State<_RainPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.85, end: 1.2).animate(
      CurvedAnimation(parent: _ctl, curve: Curves.easeInOut),
    );
    _opacity = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _ctl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctl,
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(
          scale: _scale.value,
          child: const Icon(Icons.water_drop, size: 20, color: _white),
        ),
      ),
    );
  }
}

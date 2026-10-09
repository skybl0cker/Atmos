import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../utils/haptics.dart';
import '../utils/weather_codes.dart';
import '../widgets/air_quality_card.dart';
import '../widgets/daily_list.dart';
import '../widgets/alert_banner.dart';
import '../widgets/app_drawer.dart';
import '../widgets/glass_card.dart';
import '../widgets/radar_card.dart';
import '../widgets/radio_card.dart';
import 'search_screen.dart';

const _white70 = Colors.white70;
const _white = Colors.white;

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF241A4D), // deep violet
            Color(0xFF120E24), // near-black purple
          ],
        ),
      ),
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
      centerTitle: true,
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      ),
      title: p == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(p.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                if (s.data != null)
                  Text(DateFormat.jm().format(s.data!.current.time),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
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
      if (s.error != null) {
        return _Message(
          icon: Icons.cloud_off,
          text: s.error!,
          actions: [
            FilledButton(
              onPressed: s.selected == null ? s.useMyLocation : s.refresh,
              child: const Text('Try again'),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: _white),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SearchScreen())),
              child: const Text('Search for a city'),
            ),
          ],
        );
      }
      return _Message(
        icon: Icons.wb_sunny_outlined,
        text: 'Welcome to Atmos',
        actions: [
          FilledButton.icon(
            onPressed: s.useMyLocation,
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

    return Column(
      children: [
        if (s.loading)
          const LinearProgressIndicator(
              minHeight: 2, color: _white, backgroundColor: Colors.transparent),
        Expanded(
          child: RefreshIndicator(
            onRefresh: s.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (s.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('${s.error} Showing last update.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.amberAccent)),
                  ),
                const AlertBanner(),
                const _Hero(),
                const _HourlyRow(),
                const SizedBox(height: 14),
                const _TrendCard(),
                const DailyList(title: '7-day forecast'),
                const AirQualityCard(),
                const RadarCard(),
                const RadioCard(),
                const _DetailsGrid(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final List<Widget> actions;
  const _Message({required this.icon, required this.text, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: _white),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _white, fontSize: 18)),
            const SizedBox(height: 24),
            for (final a in actions)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: a),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = s.data!.current;
    final today = s.data!.daily.first;
    final fmt = DateFormat.jm();

    final raining = isRainCode(c.code);
    final startIn = s.data!.rainStartsIn;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (raining && !hapticsSupported) ...[
                const _RainPulse(),
                const SizedBox(width: 8),
              ],
              Icon(iconFor(c.code, day: c.isDay), size: 20, color: _white),
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
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.arrow_upward, size: 14, color: _white70),
              Text(' ${s.temp(today.maxC)}   ',
                  style: const TextStyle(color: _white, fontWeight: FontWeight.w600)),
              const Icon(Icons.arrow_downward, size: 14, color: _white70),
              Text(' ${s.temp(today.minC)}',
                  style: const TextStyle(color: _white, fontWeight: FontWeight.w600)),
            ],
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              Text(s.temp(c.tempC).replaceAll('°', ''),
                  style: const TextStyle(
                      fontSize: 104,
                      fontWeight: FontWeight.w200,
                      color: _white,
                      height: 1.05)),
              const Positioned(
                right: 0,
                top: 18,
                child: Text('°',
                    style: TextStyle(fontSize: 44, color: _white, fontWeight: FontWeight.w200)),
              ),
            ],
          ),
          Text('Feels like ${s.temp(c.feelsC)}',
              style: const TextStyle(color: _white70, fontSize: 14)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wb_twilight, size: 16, color: _white70),
              const SizedBox(width: 4),
              Text(fmt.format(today.sunrise),
                  style: const TextStyle(color: _white70, fontSize: 13)),
              const SizedBox(width: 18),
              const Icon(Icons.nights_stay_outlined, size: 16, color: _white70),
              const SizedBox(width: 4),
              Text(fmt.format(today.sunset),
                  style: const TextStyle(color: _white70, fontSize: 13)),
            ],
          ),
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
    if (m <= 1) return 'Rain starting now';
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

/// Visual stand-in for haptics on platforms where the Vibration API is
/// unavailable (notably the iOS web install): a gently pulsing droplet while
/// it is actively raining.
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

class _HourlyRow extends StatelessWidget {
  const _HourlyRow();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final hours = s.data!.hourly;
    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: hours.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final h = hours[i];
          return Container(
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(i == 0 ? 130 : 80),
              borderRadius: BorderRadius.circular(18),
              border: i == 0
                  ? Border.all(color: Colors.white.withAlpha(90))
                  : Border.all(color: Colors.white.withAlpha(20)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(i == 0 ? 'Now' : DateFormat('h a').format(h.time),
                    style: const TextStyle(color: _white70, fontSize: 12)),
                Icon(iconFor(h.code, day: isDayHour(h.time)), color: _white, size: 24),
                Text(s.temp(h.tempC),
                    style: const TextStyle(
                        color: _white, fontSize: 16, fontWeight: FontWeight.w600)),
                Text(h.precipProb >= 20 ? '${h.precipProb}%' : ' ',
                    style: const TextStyle(color: Color(0xFF9BE7FF), fontSize: 11)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final vals = s.data!.hourly.map((h) => s.tv(h.tempC)).toList();
    if (vals.length < 2) return const SizedBox.shrink();
    final lo = vals.reduce(math.min);
    final hi = vals.reduce(math.max);

    return GlassCard(
      title: '24-hour temperature',
      icon: Icons.show_chart,
      child: Column(
        children: [
          SizedBox(
            height: 110,
            child: LineChart(
              LineChartData(
                minY: lo - 2,
                maxY: hi + 2,
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var k = 0; k < vals.length; k++) FlSpot(k.toDouble(), vals[k]),
                    ],
                    isCurved: true,
                    color: _white,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, color: Colors.white12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Low ${lo.round()}°', style: const TextStyle(color: _white70, fontSize: 12)),
              Text('High ${hi.round()}°', style: const TextStyle(color: _white70, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailsGrid extends StatelessWidget {
  const _DetailsGrid();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = s.data!.current;
    final today = s.data!.daily.first;

    final tiles = <_Tile>[
      _Tile(Icons.water_drop_outlined, 'Humidity', '${c.humidity.round()}%', null),
      _Tile(Icons.air, 'Wind', s.wind(c.windKmh), 'From ${compass(c.windDir)}'),
      _Tile(Icons.wb_sunny_outlined, 'UV index', today.uv.round().toString(),
          uvLabel(today.uv)),
      _Tile(Icons.speed, 'Pressure', '${c.pressure.round()} hPa', null),
      _Tile(Icons.umbrella_outlined, 'Precipitation', s.precip(c.precipMm),
          '${today.precipProb}% chance today'),
      _Tile(Icons.thermostat, 'Feels like', s.temp(c.feelsC), null),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: tiles,
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  const _Tile(this.icon, this.label, this.value, this.sub);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(80),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: _white70),
            const SizedBox(width: 6),
            Text(label.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.8,
                    color: _white70,
                    fontWeight: FontWeight.w600)),
          ]),
          const Spacer(),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 24, color: _white, fontWeight: FontWeight.w500)),
          if (sub != null)
            Text(sub!, style: const TextStyle(fontSize: 12, color: _white70)),
        ],
      ),
    );
  }
}

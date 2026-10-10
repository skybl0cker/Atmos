import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/weather.dart';
import '../services/severe_event_service.dart';
import '../state/app_state.dart';
import '../utils/weather_codes.dart';
import '../widgets/alert_banner.dart';
import '../widgets/app_drawer.dart';
import '../widgets/weather_icon.dart';
import 'event_screen.dart';
import 'forecast_screen.dart';
import 'radar_screen.dart';
import 'radio_screen.dart';
import 'search_screen.dart';

/// Gentle wave for the top edge of the bottom card, echoing the
/// rolling hills in the illustrated backgrounds.
class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 26);
    path.quadraticBezierTo(size.width * 0.25, 6, size.width * 0.5, 20);
    path.quadraticBezierTo(size.width * 0.75, 34, size.width, 16);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Illustrated home: a painterly landscape background that follows the
/// conditions, a big temperature readout, and a bottom card with the
/// hourly outlook plus dives into Radar / Forecast / Alerts.
class HomeScreen extends StatelessWidget {
  final SevereEvent? event;
  const HomeScreen({super.key, this.event});

  String _bgFor(int code, bool isDay) {
    if (!isDay) return 'assets/backgrounds/bg_night.webp';
    // Overcast skies read as gloom — show the rain illustration, since the
    // model often reports overcast while precipitation is starting.
    if (isRainCode(code) || code == 3) {
      return 'assets/backgrounds/bg_rain.webp';
    }
    return 'assets/backgrounds/bg_day.webp';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final d = s.data;
    final bg = d == null
        ? 'assets/backgrounds/bg_day.webp'
        : _bgFor(d.current.code, d.current.isDay);
    // Dark text on the light day illustration, white text otherwise.
    final onBg = bg.endsWith('bg_day.webp')
        ? const Color(0xFF3A2A5E)
        : Colors.white;
    final onBgSoft = bg.endsWith('bg_day.webp')
        ? const Color(0xFF6B5A8E)
        : Colors.white70;

    return Scaffold(
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(bg, fit: BoxFit.cover),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _topBar(context, s, onBg),
                if (d != null) _hero(s, onBg, onBgSoft),
                const Spacer(),
                _bottomCard(context, s, event),
              ],
            ),
          ),
          if (d == null)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context, AppState s, Color onBg) {
    final p = s.selected;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          Builder(
            builder: (ctx) => IconButton(
              icon: Icon(Icons.menu, color: onBg),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p?.name ?? 'Atmos',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: onBg)),
                if (s.data != null)
                  Text(
                      DateFormat('EEEE, MMM d · h:mm a')
                          .format(s.data!.current.time),
                      style: TextStyle(fontSize: 12, color: onBg)),
              ],
            ),
          ),
          if (p != null && !p.isCurrent)
            IconButton(
              tooltip: s.isSaved(p) ? 'Remove from saved' : 'Save place',
              icon: Icon(s.isSaved(p) ? Icons.star : Icons.star_border,
                  color: onBg),
              onPressed: () => s.toggleSaved(p),
            ),
          IconButton(
            tooltip: 'Weather radio',
            icon: Icon(Icons.radio, color: onBg),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RadioScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Add a place',
            icon: Icon(Icons.search, color: onBg),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero(AppState s, Color onBg, Color onBgSoft) {
    final c = s.data!.current;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ShaderMask(
            shaderCallback: (bounds) =>
                const LinearGradient(
                  colors: [Colors.white, Colors.white, Colors.transparent],
                  stops: [0.0, 0.65, 1.0],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ).createShader(bounds),
            blendMode: BlendMode.srcIn,
            child: Text(s.temp(c.tempC).replaceAll('°', ''),
                style: const TextStyle(
                    fontSize: 110,
                    fontWeight: FontWeight.w200,
                    color: Colors.white,
                    height: 1.0)),
          ),
          const SizedBox(width: 12),
          WeatherIcon(c.code, day: c.isDay, size: 46),
        ],
      ),
    );
  }

  Widget _bottomCard(
      BuildContext context, AppState s, SevereEvent? event) {
    final d = s.data;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = dark ? const Color(0xFF1B1440) : Colors.white;
    final ink = dark ? Colors.white : const Color(0xFF2A2140);
    final inkSoft = dark ? Colors.white70 : const Color(0xFF6B5A8E);
    final chipBg = dark ? Colors.white.withAlpha(24) : const Color(0xFFF4F1FD);
    return ClipPath(
      clipper: _WaveClipper(),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 24, offset: Offset(0, -6)),
          ],
        ),
        padding: EdgeInsets.fromLTRB(
            20, 34, 20, 20 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const AlertBanner(),
          if (d != null) ...[
            Text('Weather Today',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: ink)),
            const SizedBox(height: 12),
            _hourlyStrip(s, dark, ink, inkSoft, chipBg),
            const SizedBox(height: 16),
            Divider(
                height: 1,
                color: dark
                    ? Colors.white.withAlpha(30)
                    : const Color(0xFFE8E2F5)),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              _action(context, Icons.radar, 'Radar', const Color(0xFF7C4DFF),
                  () => _openRadar(context, s)),
              const SizedBox(width: 10),
              _action(context, Icons.calendar_month, '14-Day',
                  const Color(0xFF5C6BC0), () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ForecastScreen()));
              }),
              const SizedBox(width: 10),
              _action(
                  context,
                  event != null && event.kind != SevereKind.none
                      ? event.tabIcon
                      : Icons.notifications_outlined,
                  event != null && event.kind != SevereKind.none
                      ? event.tabLabel
                      : 'Alerts',
                  event != null && event.kind != SevereKind.none
                      ? (event.color ?? Colors.redAccent)
                      : const Color(0xFF9B8AC4), () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const EventScreen()));
              }),
            ],
          ),
        ],
      ),
      ),
    );
  }

  void _openRadar(BuildContext context, AppState s) {
    final place = s.selected;
    if (place == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RadarScreen(
          place: place,
          minutely: s.data?.minutely ?? const [],
          windKmh: s.data?.steeringWindKmh ?? 0,
          windDir: s.data?.steeringWindDir ?? 0,
        ),
      ),
    );
  }

  Widget _action(BuildContext context, IconData icon, String label,
      Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withAlpha(22),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withAlpha(60)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hourlyStrip(
      AppState s, bool dark, Color ink, Color inkSoft, Color chipBg) {
    final hours = s.data!.hourly.take(8).toList();
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: hours.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final h = hours[i];
          return Container(
            width: 62,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: i == 0
                  ? const Color(0xFF7C4DFF).withAlpha(dark ? 60 : 26)
                  : chipBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(i == 0 ? 'Now' : DateFormat('h a').format(h.time),
                    style: TextStyle(color: inkSoft, fontSize: 11)),
                WeatherIcon(h.code, day: isDayHour(h.time), size: 24),
                Text(s.temp(h.tempC),
                    style: TextStyle(
                        color: ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          );
        },
      ),
    );
  }
}

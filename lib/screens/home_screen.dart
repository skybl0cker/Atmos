import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../models/weather.dart';
import '../services/severe_event_service.dart';
import '../state/app_state.dart';
import '../utils/aqi.dart';
import '../utils/astro.dart';
import '../utils/layout.dart';
import '../utils/summary.dart';
import '../utils/tips.dart';
import '../utils/weather_codes.dart';
import '../widgets/alert_banner.dart';
import '../widgets/app_drawer.dart';
import '../widgets/art_icon.dart';
import '../widgets/light_daily_list.dart';
import '../widgets/moon_icon.dart';
import '../widgets/nowcast_strip.dart';
import '../widgets/pressable.dart';
import '../widgets/scene.dart';
import 'event_screen.dart';
import 'forecast_screen.dart';
import 'radar_screen.dart';
import 'radio_screen.dart';
import 'search_screen.dart';

const _accent = Color(0xFF6C63FF);

/// Fully open sheet stops below the place name and date.
const _maxSheet = 0.86;
const _shadow = [Shadow(color: Color(0x33000000), blurRadius: 16)];

/// Illustrated home: a watercolor landscape under a tinted sky, the
/// location and a huge fading temperature up top with the condition
/// running vertically down the side, and a white "Weather Today" sheet
/// that drags up to reveal details and the 10-day outlook.
class HomeScreen extends StatefulWidget {
  final SevereEvent? event;
  const HomeScreen({super.key, this.event});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// 0 = sheet resting, 1 = fully expanded. Drives the hero fade.
  final _expand = ValueNotifier<double>(0);
  final _sheetCtrl = DraggableScrollableController();
  final _panelScroll = ScrollController();

  @override
  void dispose() {
    _expand.dispose();
    _sheetCtrl.dispose();
    _panelScroll.dispose();
    super.dispose();
  }

  void _push(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  void _openRadar(AppState s) {
    final place = s.selected;
    if (place == null) return;
    _push(
      RadarScreen(
        place: place,
        minutely: s.data?.minutely ?? const [],
        windKmh: s.data?.steeringWindKmh ?? 0,
        windDir: s.data?.steeringWindDir ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final width = MediaQuery.sizeOf(context).width;
    // Phones keep the pull-up sheet; unfolded foldables, tablets and
    // desktop browsers get the side-by-side layout.
    if (width >= wideLayoutMinWidth) return _buildWide(context, s);
    return _buildPhone(context, s);
  }

  /// Big screens: the scene and hero fill the left, "Weather Today" sits in
  /// a floating panel on the right, and on very wide screens the 14-day
  /// outlook gets its own column.
  Widget _buildWide(BuildContext context, AppState s) {
    final d = s.data;
    final size = MediaQuery.sizeOf(context);
    final threeCol = size.width >= threeColumnMinWidth;
    final panelW = (size.width * (threeCol ? 0.3 : 0.44)).clamp(360.0, 480.0);
    final dailyW = threeCol ? (size.width * 0.24).clamp(320.0, 400.0) : 0.0;
    const gap = 20.0;
    final reserved = panelW + gap * 2 + (threeCol ? dailyW + gap : 0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        drawer: const AppDrawer(),
        body: Stack(
          children: [
            Positioned.fill(
              child: Scene(data: d, alignment: Scene.wideAlignment),
            ),
            SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          _Header(s: s),
                          if (d != null)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onHorizontalDragEnd: (e) {
                                final v = e.primaryVelocity ?? 0;
                                if (v.abs() < 250) return;
                                if (s.stepPlace(v < 0 ? 1 : -1)) {
                                  tapHaptic(context);
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Reveal(
                                  key: ValueKey(s.selected?.key),
                                  child: _Hero(s: s, d: d, maxScale: 1.3),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (threeCol)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, gap, gap, gap),
                      child: SizedBox(
                        width: dailyW,
                        child: _DailyPanel(s: s),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, gap, gap, gap),
                    child: SizedBox(
                      width: panelW,
                      child: _Sheet(
                        scroll: _panelScroll,
                        s: s,
                        event: widget.event,
                        docked: true,
                        showDaily: !threeCol,
                        onRadar: () => _openRadar(s),
                        onForecast: () => _push(const ForecastScreen()),
                        onAlerts: () => _push(const EventScreen()),
                        onRadio: () => _push(const RadioScreen()),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (d == null)
              _StatusOverlay(state: s, rightInset: reserved, bottomFraction: 0),
          ],
        ),
      ),
    );
  }

  Widget _buildPhone(BuildContext context, AppState s) {
    final d = s.data;
    final mq = MediaQuery.of(context);
    // Resting sheet: handle, title, the hourly row and the quick actions.
    final restPx = 300.0 + mq.padding.bottom;
    final restFrac = (restPx / mq.size.height).clamp(0.25, 0.62).toDouble();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        drawer: const AppDrawer(),
        body: Stack(
          children: [
            // The painting runs a little under the sheet so the hills meet
            // its rounded top, as in a landscape behind a card.
            Positioned.fill(
              child: Scene(data: d, bottomInset: restPx - 110),
            ),
            SafeArea(
              bottom: false,
              // Non-scrolling: on very short screens the lower hero simply
              // tucks under the sheet instead of throwing an overflow.
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Header(s: s),
                    if (d != null)
                      // Swipe left / right across the hero to flip between
                      // saved places.
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragEnd: (e) {
                          final v = e.primaryVelocity ?? 0;
                          if (v.abs() < 250) return;
                          if (s.stepPlace(v < 0 ? 1 : -1)) tapHaptic(context);
                        },
                        child: ValueListenableBuilder<double>(
                          valueListenable: _expand,
                          builder: (_, t, child) => Opacity(
                            opacity: (1 - t * 1.6).clamp(0.0, 1.0).toDouble(),
                            child: Transform.translate(
                              offset: Offset(0, -40 * t),
                              child: child,
                            ),
                          ),
                          child: Reveal(
                            key: ValueKey(s.selected?.key),
                            child: _Hero(s: s, d: d),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (d == null) _StatusOverlay(state: s),
            NotificationListener<DraggableScrollableNotification>(
              onNotification: (n) {
                final span = n.maxExtent - n.minExtent;
                _expand.value = span <= 0
                    ? 0
                    : ((n.extent - n.minExtent) / span)
                          .clamp(0.0, 1.0)
                          .toDouble();
                return false;
              },
              child: DraggableScrollableSheet(
                controller: _sheetCtrl,
                initialChildSize: restFrac,
                minChildSize: restFrac,
                maxChildSize: _maxSheet,
                snap: true,
                builder: (ctx, scroll) => _Sheet(
                  scroll: scroll,
                  s: s,
                  event: widget.event,
                  onRadar: () => _openRadar(s),
                  onForecast: () => _push(const ForecastScreen()),
                  onAlerts: () => _push(const EventScreen()),
                  onRadio: () => _push(const RadioScreen()),
                  onHandleTap: () {
                    final open = _expand.value > 0.5;
                    _sheetCtrl.animateTo(
                      open ? restFrac : _maxSheet,
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeOutCubic,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- header ---

class _Header extends StatelessWidget {
  final AppState s;
  const _Header({required this.s});

  @override
  Widget build(BuildContext context) {
    final p = s.selected;
    final d = s.data;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 10, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Pressable(
              pressedScale: 0.97,
              semanticLabel: 'Change place',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        p?.isCurrent ?? false
                            ? Icons.near_me_rounded
                            : Icons.location_on_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          p?.name ?? 'Atmos',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w400,
                            shadows: _shadow,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (d != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 2, top: 2),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: s.showingStale && !s.loading
                            ? _StaleNotice(s: s)
                            : Text(
                                s.loading
                                    ? 'Updating…'
                                    : 'Today, ${DateFormat('MMM d  h:mm a').format(d.current.time)}',
                                key: ValueKey(s.loading),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  shadows: _shadow,
                                ),
                              ),
                      ),
                    ),
                  _PlaceDots(s: s),
                ],
              ),
            ),
          ),
          if (p != null && !p.isCurrent)
            IconButton(
              tooltip: s.isSaved(p) ? 'Remove from saved' : 'Save place',
              onPressed: () {
                tapHaptic(context);
                s.toggleSaved(p);
              },
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (c, a) =>
                    ScaleTransition(scale: a, child: c),
                child: Icon(
                  s.isSaved(p)
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  key: ValueKey(s.isSaved(p)),
                  color: s.isSaved(p) ? const Color(0xFFFFD54F) : Colors.white,
                  size: 26,
                ),
              ),
            ),
          Builder(
            builder: (ctx) => Pressable(
              semanticLabel: 'Menu',
              onTap: () => Scaffold.of(ctx).openDrawer(),
              child: const Padding(
                padding: EdgeInsets.fromLTRB(12, 14, 12, 12),
                child: _MenuGlyph(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two rounded strokes, the lower one shorter — the reference's menu mark.
class _MenuGlyph extends StatelessWidget {
  const _MenuGlyph();

  @override
  Widget build(BuildContext context) {
    Widget bar(double w) => Container(
      width: w,
      height: 3,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(2),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [bar(30), const SizedBox(height: 6), bar(22)],
    );
  }
}

// --------------------------------------------------------------- hero ---

class _Hero extends StatelessWidget {
  final AppState s;
  final WeatherData d;

  /// How far the readout may grow past phone size (big screens only).
  final double maxScale;
  const _Hero({required this.s, required this.d, this.maxScale = 1.0});

  @override
  Widget build(BuildContext context) {
    final c = d.current;
    final today = d.daily.isNotEmpty ? d.daily.first : null;
    final target = s.tv(c.tempC);
    // Scale the big readout down on short phones (full size from ~780 dp),
    // and up to [maxScale] on large screens.
    final k = (MediaQuery.sizeOf(context).height / 780).clamp(0.68, maxScale);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 22, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: target - 10, end: target),
                      duration: const Duration(milliseconds: 1200),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, _) => ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (b) => LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white,
                            Colors.white.withAlpha(215),
                            Colors.white.withAlpha(70),
                          ],
                          stops: const [0, 0.5, 1],
                        ).createShader(b),
                        child: Padding(
                          padding: EdgeInsets.only(right: 34 * k),
                          child: Text(
                            '${v.round()}',
                            style: TextStyle(
                              fontSize: 148 * k,
                              fontWeight: FontWeight.w200,
                              letterSpacing: -6 * k,
                              height: 1.05,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 22 * k,
                      child: DegreeRing(
                        size: 26 * k,
                        stroke: 5 * k,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                if (today != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      'H ${s.temp(today.maxC)}   L ${s.temp(today.minC)}   ·   Feels ${s.temp(c.feelsC)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        shadows: _shadow,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 24),
                  child: Text(
                    weatherSummary(d, s.temp),
                    style: TextStyle(
                      color: Colors.white.withAlpha(230),
                      fontSize: 14,
                      height: 1.4,
                      shadows: _shadow,
                    ),
                  ),
                ),
                if (d.rainStartsIn != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 12),
                    child: _RainSoonChip(startsIn: d.rainStartsIn!),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 30),
            child: RotatedBox(
              quarterTurns: 3,
              child: Text(
                conditionPhrase(c.code, c.isDay),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 0.5,
                  shadows: _shadow,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- sheet ---

class _Sheet extends StatelessWidget {
  final ScrollController scroll;
  final AppState s;
  final SevereEvent? event;
  final VoidCallback onRadar, onForecast, onAlerts, onRadio;
  final VoidCallback? onHandleTap;

  /// Docked = a floating side panel on big screens (no drag handle, all
  /// corners rounded) instead of the phone's pull-up sheet.
  final bool docked;

  /// Whether the 10-day list lives in this panel (off when big screens
  /// give it its own column).
  final bool showDaily;
  const _Sheet({
    required this.scroll,
    required this.s,
    required this.event,
    required this.onRadar,
    required this.onForecast,
    required this.onAlerts,
    required this.onRadio,
    this.onHandleTap,
    this.docked = false,
    this.showDaily = true,
  });

  @override
  Widget build(BuildContext context) {
    final pal = SheetPalette.of(context);
    final d = s.data;
    final ev = (event != null && event!.kind != SevereKind.none) ? event : null;
    final bottom = docked ? 0.0 : MediaQuery.paddingOf(context).bottom;
    final radius = docked
        ? BorderRadius.circular(32)
        : const BorderRadius.vertical(top: Radius.circular(38));

    Widget title(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 10),
      child: Text(
        t,
        style: TextStyle(
          color: pal.ink,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: pal.bg,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: const Color(0x33000000),
            blurRadius: 30,
            offset: Offset(0, docked ? 10 : -6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: RefreshIndicator(
          color: _accent,
          onRefresh: () {
            tapHaptic(context);
            return s.refresh();
          },
          child: ListView(
            controller: scroll,
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.only(bottom: 28 + bottom),
            children: [
              if (docked)
                const SizedBox(height: 24)
              else
                GestureDetector(
                  onTap: onHandleTap,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 14),
                    child: Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: pal.faint,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              Center(
                child: Text(
                  'Weather Today',
                  style: TextStyle(
                    color: pal.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (d != null) _HourlyRow(s: s, d: d, pal: pal),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _Action(Icons.radar, 'Radar', _accent, pal, onRadar),
                    _Action(
                      Icons.calendar_month_rounded,
                      '14-Day',
                      const Color(0xFF3F8CFF),
                      pal,
                      onForecast,
                    ),
                    _Action(
                      ev != null
                          ? ev.tabIcon
                          : Icons.notifications_none_rounded,
                      ev != null ? ev.tabLabel : 'Alerts',
                      ev != null ? ev.color : const Color(0xFFFF7A59),
                      pal,
                      onAlerts,
                      badge: ev != null || s.alerts.isNotEmpty,
                    ),
                    _Action(
                      Icons.radio_rounded,
                      'Radio',
                      const Color(0xFF22B07D),
                      pal,
                      onRadio,
                    ),
                  ],
                ),
              ),
              if (d != null) ...[
                if (s.alerts.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 18, 16, 0),
                    child: AlertBanner(),
                  ),
                _Tips(d: d, pal: pal),
                // Rain on the way in the next two hours: show the nowcast.
                if (d.minutely.take(8).any((m) => m.precipMm > 0))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: NowcastStrip(
                      minutely: d.minutely,
                      hours: 2,
                      title: 'Rain, next 2 hours',
                    ),
                  ),
                title('Details'),
                _Details(s: s, d: d, pal: pal),
                if (showDaily) ...[
                  title('Next 10 Days'),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: LightDailyList(maxDays: 10),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Center(
                    child: Text(
                      'Updated ${DateFormat.jm().format(d.current.time)} · Pull down to refresh',
                      style: TextStyle(color: pal.soft, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HourlyRow extends StatelessWidget {
  final AppState s;
  final WeatherData d;
  final SheetPalette pal;
  const _HourlyRow({required this.s, required this.d, required this.pal});

  @override
  Widget build(BuildContext context) {
    final hours = d.hourly;
    // Four hours per view on phones; on wider panels the cards stop
    // growing past 104 dp and more hours show instead.
    return LayoutBuilder(
      builder: (context, box) {
        final w = math.min((box.maxWidth - 24) / 4, 104.0);
        return SizedBox(
          height: 122,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: hours.length,
            itemBuilder: (_, i) {
              final h = hours[i];
              final now = i == 0;
              return SizedBox(
                width: w,
                child: Column(
                  children: [
                    ArtIcon(
                      h.code,
                      day: now ? d.current.isDay : d.isDaylight(h.time),
                      size: 42,
                      onDark: pal.dark,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      now ? 'NOW' : DateFormat('hh:mm a').format(h.time),
                      style: TextStyle(
                        color: now ? _accent : pal.soft,
                        fontSize: 11,
                        fontWeight: now ? FontWeight.w600 : FontWeight.w400,
                        letterSpacing: now ? 1 : 0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    RingTemp(
                      '${s.tv(h.tempC).round()}',
                      fontSize: 30,
                      weight: FontWeight.w300,
                      color: pal.ink,
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final SheetPalette pal;
  final VoidCallback onTap;
  final bool badge;
  const _Action(
    this.icon,
    this.label,
    this.color,
    this.pal,
    this.onTap, {
    this.badge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Pressable(
          onTap: onTap,
          semanticLabel: label,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: pal.card,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, color: color, size: 22),
                    if (badge)
                      Positioned(
                        right: -3,
                        top: -2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF4D4D),
                            shape: BoxShape.circle,
                            border: Border.all(color: pal.card, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: pal.ink,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  final AppState s;
  final WeatherData d;
  final SheetPalette pal;
  const _Details({required this.s, required this.d, required this.pal});

  @override
  Widget build(BuildContext context) {
    final c = d.current;
    final today = d.daily.isNotEmpty ? d.daily.first : null;
    final tomorrow = d.daily.length > 1 ? d.daily[1] : null;

    var sunLabel = 'Sunset';
    var sunIcon = Icons.nights_stay_outlined;
    var sunValue = '—';
    if (today != null) {
      if (c.time.isBefore(today.sunrise)) {
        sunLabel = 'Sunrise';
        sunIcon = Icons.wb_twilight_rounded;
        sunValue = DateFormat.jm().format(today.sunrise);
      } else if (c.time.isBefore(today.sunset)) {
        sunValue = DateFormat.jm().format(today.sunset);
      } else if (tomorrow != null) {
        sunLabel = 'Sunrise';
        sunIcon = Icons.wb_twilight_rounded;
        sunValue = DateFormat.jm().format(tomorrow.sunrise);
      }
    }
    final pressure = s.imperial
        ? '${(c.pressure * 0.02953).toStringAsFixed(2)} in'
        : '${c.pressure.round()} hPa';

    final moon = moonPhaseAt(c.time);
    final air = d.air;
    Widget disc(IconData icon, Color color) => Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color.withAlpha(pal.dark ? 50 : 30),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 16, color: color),
    );

    // (icon, label, value)
    final items = <(Widget, String, String)>[
      (
        disc(Icons.thermostat_rounded, const Color(0xFFFF8A5B)),
        'Feels like',
        s.temp(c.feelsC),
      ),
      (
        disc(Icons.water_drop_outlined, const Color(0xFF3D9BFF)),
        'Humidity',
        '${c.humidity.round()}%',
      ),
      (
        disc(Icons.air_rounded, const Color(0xFF22B07D)),
        'Wind',
        '${s.wind(c.windKmh)} ${compass(c.windDir)}',
      ),
      (
        disc(Icons.wb_sunny_outlined, const Color(0xFFFFB524)),
        today == null ? 'UV index' : 'UV · ${uvLabel(today.uv)}',
        today == null ? '—' : '${today.uv.round()}',
      ),
      (disc(sunIcon, const Color(0xFFB36BD1)), sunLabel, sunValue),
      (disc(Icons.speed_rounded, _accent), 'Pressure', pressure),
      if (today != null)
        (
          disc(Icons.umbrella_outlined, const Color(0xFF3D9BFF)),
          'Rain today',
          '${today.precipProb}%',
        ),
      if (air != null)
        (
          disc(Icons.masks_outlined, aqiLevel(air.usAqi).color),
          'Air · ${aqiLevel(air.usAqi).label}',
          '${air.usAqi} AQI',
        ),
      (
        MoonIcon(
          phase: moon.phase,
          size: 28,
          shadow: pal.dark ? const Color(0xFF0E0B22) : const Color(0xFF3A3360),
        ),
        // The icon shows waxing vs waning; the label stays short.
        moon.shortName,
        '${(moon.illumination * 100).round()}% lit',
      ),
    ];
    final dew = dewPointC(c.tempC, c.humidity);

    Widget card((Widget, String, String) it) => Expanded(
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        decoration: BoxDecoration(
          color: pal.card,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            it.$1,
            const SizedBox(height: 10),
            Text(
              it.$3,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: pal.ink,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            // Shrink a long label slightly rather than cutting it off.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                it.$2,
                maxLines: 1,
                style: TextStyle(color: pal.soft, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i += 3)
            Row(
              children: [
                for (final it in items.skip(i).take(3)) card(it),
                // Keep card widths even on a short last row.
                for (var k = items.skip(i).take(3).length; k < 3; k++)
                  const Expanded(child: SizedBox()),
              ],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Text(
              'Dew point ${s.temp(dew)} — ${dew >= 18
                  ? 'muggy'
                  : dew >= 13
                  ? 'comfortable'
                  : 'dry and crisp'}.',
              style: TextStyle(color: pal.soft, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Third column on very wide screens: the 14-day outlook in its own
/// floating panel.
class _DailyPanel extends StatelessWidget {
  final AppState s;
  const _DailyPanel({required this.s});

  @override
  Widget build(BuildContext context) {
    final pal = SheetPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: pal.bg,
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 30,
            offset: Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: s.data == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 24, 14, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                  child: Text(
                    'Next 14 Days',
                    style: TextStyle(
                      color: pal.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const LightDailyList(maxDays: 14),
              ],
            ),
    );
  }
}

// -------------------------------------------------------------- extras ---

/// "Offline · updated 2:15 PM" — shown instead of the date when the last
/// refresh failed but older (or cached) data is still on screen. Tap to retry.
class _StaleNotice extends StatelessWidget {
  final AppState s;
  const _StaleNotice({required this.s});

  @override
  Widget build(BuildContext context) {
    final at = s.updatedAt;
    return GestureDetector(
      onTap: () {
        tapHaptic(context);
        s.refresh();
      },
      child: Container(
        margin: const EdgeInsets.only(top: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(60),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                at == null
                    ? "Couldn't update · tap to retry"
                    : 'Offline · updated ${DateFormat.jm().format(at)} · retry',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page dots for saved places, so the swipe gesture is discoverable.
class _PlaceDots extends StatelessWidget {
  final AppState s;
  const _PlaceDots({required this.s});

  @override
  Widget build(BuildContext context) {
    final i = s.saved.indexWhere((p) => p.key == s.selected?.key);
    if (s.saved.length < 2 || i == -1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var k = 0; k < s.saved.length; k++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.only(right: 5),
              width: k == i ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(k == i ? 255 : 120),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Rain likely in ~20 min" heads-up from the 15-minute nowcast.
class _RainSoonChip extends StatelessWidget {
  final Duration startsIn;
  const _RainSoonChip({required this.startsIn});

  @override
  Widget build(BuildContext context) {
    final m = startsIn.inMinutes;
    final label = m < 5
        ? 'Rain starting any minute'
        : m < 60
        ? 'Rain likely in ~$m min'
        : 'Rain likely in ~${(m / 60).toStringAsFixed(m % 60 == 0 ? 0 : 1)} hr';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(235),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.umbrella_rounded,
            size: 16,
            color: Color(0xFF3D9BFF),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF1F1A33),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Today's practical tips as soft chips ("☂️ Bring an umbrella").
class _Tips extends StatelessWidget {
  final WeatherData d;
  final SheetPalette pal;
  const _Tips({required this.d, required this.pal});

  @override
  Widget build(BuildContext context) {
    final tips = dayTips(d);
    if (tips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final t in tips)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _accent.withAlpha(pal.dark ? 45 : 20),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${t.emoji}  ${t.text}',
                style: TextStyle(
                  color: pal.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- status ---

class _StatusOverlay extends StatelessWidget {
  final AppState state;

  /// Space to keep clear on the right (the docked panel on big screens)
  /// and at the bottom (the phone sheet).
  final double rightInset;
  final double bottomFraction;
  const _StatusOverlay({
    required this.state,
    this.rightInset = 0,
    this.bottomFraction = 0.3,
  });

  @override
  Widget build(BuildContext context) {
    final s = state;
    void search() => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SearchScreen()),
    );

    final Widget body;
    if (s.error != null) {
      body = _panel(
        context,
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load the weather",
        message: s.error!,
        actions: [
          FilledButton.icon(
            onPressed: s.selected == null ? search : () => s.refresh(),
            icon: Icon(
              s.selected == null ? Icons.search_rounded : Icons.refresh_rounded,
            ),
            label: Text(s.selected == null ? 'Find a place' : 'Try again'),
          ),
        ],
      );
    } else if (s.selected == null && !s.loading) {
      body = _panel(
        context,
        icon: Icons.travel_explore_rounded,
        title: 'Where are you?',
        message: 'Use your location or search for a place.',
        actions: [
          FilledButton.icon(
            onPressed: () => s.useMyLocation(),
            icon: const Icon(Icons.my_location_rounded),
            label: const Text('My location'),
          ),
          OutlinedButton.icon(
            onPressed: search,
            icon: const Icon(Icons.search_rounded),
            label: const Text('Search'),
          ),
        ],
      );
    } else {
      body = const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 14),
          Text(
            'Painting the sky…',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              shadows: _shadow,
            ),
          ),
        ],
      );
    }
    return Positioned(
      left: 0,
      right: rightInset,
      top: 0,
      bottom: MediaQuery.sizeOf(context).height * bottomFraction,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: KeyedSubtree(
              key: ValueKey('${s.error}|${s.selected?.key}|${s.loading}'),
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
    required List<Widget> actions,
  }) {
    final pal = SheetPalette.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
      decoration: BoxDecoration(
        color: pal.bg,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 30,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: _accent),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: pal.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: pal.soft),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: actions,
          ),
        ],
      ),
    );
  }
}

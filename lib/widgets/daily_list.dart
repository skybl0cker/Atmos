import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../utils/weather_codes.dart';
import 'glass_card.dart';

const _white70 = Colors.white70;
const _white = Colors.white;

/// Expandable daily forecast list with temperature range bars. Used on the
/// home screen (7 days) and the full 14-day forecast tab.
class DailyList extends StatelessWidget {
  final String title;
  final int maxDays;
  const DailyList({super.key, required this.title, this.maxDays = 7});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final all = s.data!.daily;
    final days = all.length > maxDays ? all.sublist(0, maxDays) : all;
    final minAll = days.map((d) => d.minC).reduce(math.min);
    final maxAll = days.map((d) => d.maxC).reduce(math.max);
    final range = math.max(maxAll - minAll, 1.0);

    return GlassCard(
      title: title,
      icon: Icons.calendar_month,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.white24,
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: _white),
        ),
        child: Column(
          children: [
            for (var i = 0; i < days.length; i++)
              ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 10),
                iconColor: _white70,
                collapsedIconColor: _white70,
                title: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(
                        i == 0 ? 'Today' : DateFormat.E().format(days[i].date),
                        style: const TextStyle(color: _white, fontSize: 15),
                      ),
                    ),
                    Icon(iconFor(days[i].code), color: _white, size: 20),
                    SizedBox(
                      width: 38,
                      child: Text(
                        days[i].precipProb >= 20 ? ' ${days[i].precipProb}%' : '',
                        style: const TextStyle(color: Color(0xFF9BE7FF), fontSize: 11),
                      ),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text(s.temp(days[i].minC),
                          textAlign: TextAlign.right,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _white70)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LayoutBuilder(builder: (_, box) {
                        final w = box.maxWidth;
                        final left = (days[i].minC - minAll) / range * w;
                        final width =
                            math.max((days[i].maxC - days[i].minC) / range * w, 6.0);
                        return SizedBox(
                          height: 5,
                          child: Stack(children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            Positioned(
                              left: left.clamp(0.0, w - 6).toDouble(),
                              width: width,
                              top: 0,
                              bottom: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                      colors: [Color(0xFF7EE8FA), Color(0xFFFFC371)]),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ]),
                        );
                      }),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 42,
                      child: Text(s.temp(days[i].maxC),
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: _white, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                    child: Wrap(
                      spacing: 18,
                      runSpacing: 8,
                      children: [
                        _dayFact(Icons.water_drop_outlined, 'Rain chance',
                            '${days[i].precipProb}%'),
                        _dayFact(Icons.wb_sunny_outlined, 'UV index', days[i].uv.round().toString()),
                        _dayFact(Icons.wb_twilight, 'Sunrise', DateFormat.jm().format(days[i].sunrise)),
                        _dayFact(Icons.nights_stay_outlined, 'Sunset', DateFormat.jm().format(days[i].sunset)),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _dayFact(IconData icon, String label, String value) {
    return SizedBox(
      width: 140,
      child: Row(
        children: [
          Icon(icon, size: 16, color: _white70),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: _white70, fontSize: 10)),
                Text(value,
                    style: const TextStyle(
                        color: _white, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

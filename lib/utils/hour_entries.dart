import '../models/weather.dart';

/// One slot in an hour-by-hour list: either a forecast hour or a sunrise /
/// sunset marker that falls between two hours.
sealed class HourEntry {
  const HourEntry();
}

class HourSlot extends HourEntry {
  final HourlyPoint hour;

  /// Position in the forecast (0 = the current hour, "Now").
  final int index;
  const HourSlot(this.hour, this.index);
}

class SunSlot extends HourEntry {
  final DateTime time;
  final bool isSunrise;
  const SunSlot(this.time, {required this.isSunrise});
}

/// The first [count] forecast hours with upcoming sunrise / sunset markers
/// slotted in after the hour they occur in. Sun events already past (earlier
/// than the forecast's "now") are left out.
List<HourEntry> hourEntries(WeatherData d, {int count = 24}) {
  final hours = d.hourly.take(count).toList();
  final now = d.current.time;
  final suns = <SunSlot>[
    for (final day in d.daily.take(4)) ...[
      SunSlot(day.sunrise, isSunrise: true),
      SunSlot(day.sunset, isSunrise: false),
    ],
  ].where((s) => s.time.isAfter(now)).toList();

  final out = <HourEntry>[];
  for (var i = 0; i < hours.length; i++) {
    out.add(HourSlot(hours[i], i));
    final start = hours[i].time;
    final end = start.add(const Duration(hours: 1));
    // Markers belong after the hour they fall in — but not after the very
    // last hour shown, where they'd dangle at the end of the list.
    if (i == hours.length - 1) break;
    for (final s in suns) {
      if (!s.time.isBefore(start) && s.time.isBefore(end)) out.add(s);
    }
  }
  return out;
}

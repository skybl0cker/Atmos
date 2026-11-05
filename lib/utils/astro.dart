import 'dart:math' as math;

/// Mean length of a lunar cycle (new moon to new moon), in days.
const synodicMonth = 29.530588853;

/// A new moon used as the epoch: 2000-01-06 18:14 UTC.
final _refNewMoon = DateTime.utc(2000, 1, 6, 18, 14);

class MoonPhase {
  /// 0 = new, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter.
  final double phase;
  const MoonPhase(this.phase);

  /// Fraction of the disc that is lit, 0–1.
  double get illumination => (1 - math.cos(2 * math.pi * phase)) / 2;

  bool get waxing => phase < 0.5;

  String get name {
    // Named phases get a ±1 day window; the rest are the spans between.
    const day = 1 / synodicMonth;
    if (phase < day || phase > 1 - day) return 'New Moon';
    if ((phase - 0.25).abs() < day) return 'First Quarter';
    if ((phase - 0.5).abs() < day) return 'Full Moon';
    if ((phase - 0.75).abs() < day) return 'Last Quarter';
    if (phase < 0.25) return 'Waxing Crescent';
    if (phase < 0.5) return 'Waxing Gibbous';
    if (phase < 0.75) return 'Waning Gibbous';
    return 'Waning Crescent';
  }

  /// Compact name that fits a small card ("Crescent moon").
  String get shortName => switch (name) {
        'Waxing Crescent' || 'Waning Crescent' => 'Crescent moon',
        'Waxing Gibbous' || 'Waning Gibbous' => 'Gibbous moon',
        'New Moon' => 'New moon',
        'Full Moon' => 'Full moon',
        'First Quarter' => 'First quarter',
        _ => 'Last quarter',
      };

  /// Days until the next full moon (0 when it is full now).
  int get daysToFull {
    // Dart's % on doubles is never negative for a positive divisor.
    return (((0.5 - phase) % 1) * synodicMonth).round();
  }
}

/// Moon phase at [t]. Uses the mean synodic month — accurate to within
/// about half a day, plenty for a phase name and an icon.
MoonPhase moonPhaseAt(DateTime t) {
  final days =
      t.toUtc().difference(_refNewMoon).inSeconds / Duration.secondsPerDay;
  final p = (days / synodicMonth) % 1;
  return MoonPhase(p < 0 ? p + 1 : p);
}

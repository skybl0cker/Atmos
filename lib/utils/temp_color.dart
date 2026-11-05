import 'package:flutter/painting.dart';

/// Maps an absolute temperature (°C) onto a cold → hot color ramp, so range
/// bars read at a glance: blue for freezing, green for mild, orange and red
/// for hot days.
Color tempColor(double c) {
  const stops = <(double, Color)>[
    (-10, Color(0xFF7B8CFF)),
    (0, Color(0xFF5EC8FF)),
    (10, Color(0xFF6EE7C8)),
    (18, Color(0xFFB8E86B)),
    (25, Color(0xFFFFD166)),
    (31, Color(0xFFFF9F43)),
    (38, Color(0xFFFF5E5E)),
  ];
  if (c <= stops.first.$1) return stops.first.$2;
  for (var i = 1; i < stops.length; i++) {
    if (c <= stops[i].$1) {
      final a = stops[i - 1], b = stops[i];
      final t = (c - a.$1) / (b.$1 - a.$1);
      return Color.lerp(a.$2, b.$2, t)!;
    }
  }
  return stops.last.$2;
}

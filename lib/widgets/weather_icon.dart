import 'package:flutter/material.dart';
import '../utils/weather_codes.dart';

/// Condition icon in full color: amber sun, blue rain, purple storms,
/// icy snow. A drop-in replacement for bare `Icon(iconFor(...))`.
class WeatherIcon extends StatelessWidget {
  final int code;
  final bool day;
  final double size;
  const WeatherIcon(this.code, {required this.day, this.size = 24, super.key});

  @override
  Widget build(BuildContext context) {
    return Icon(iconFor(code, day: day), size: size, color: _colorFor(code, day));
  }
}

Color _colorFor(int code, bool day) {
  if (code == 0 || code == 1) {
    return day ? const Color(0xFFFFB300) : const Color(0xFFFFE082);
  }
  if (code == 2) return const Color(0xFFFFCA28);
  if (code == 3) return const Color(0xFF90A4AE);
  if (code == 45 || code == 48) return const Color(0xFFB0BEC5);
  if (code >= 51 && code <= 67) return const Color(0xFF29B6F6);
  if (code >= 71 && code <= 77 || code == 85 || code == 86) {
    return const Color(0xFF81D4FA);
  }
  if (code >= 80 && code <= 82) return const Color(0xFF039BE5);
  if (code >= 95) return const Color(0xFF7E57C2);
  return const Color(0xFF90A4AE);
}

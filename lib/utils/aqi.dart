import 'package:flutter/material.dart';

class AqiLevel {
  final String label;
  final Color color;
  final String advice;
  const AqiLevel(this.label, this.color, this.advice);
}

AqiLevel aqiLevel(int aqi) {
  if (aqi <= 50) {
    return const AqiLevel(
      'Good',
      Color(0xFF00E400),
      'Air quality is great for outdoor activity.',
    );
  }
  if (aqi <= 100) {
    return const AqiLevel(
      'Moderate',
      Color(0xFFFFFF00),
      'Acceptable. Unusually sensitive people may want to limit long outdoor exertion.',
    );
  }
  if (aqi <= 150) {
    return const AqiLevel(
      'Unhealthy for sensitive groups',
      Color(0xFFFF7E00),
      'Sensitive groups should reduce prolonged outdoor exertion.',
    );
  }
  if (aqi <= 200) {
    return const AqiLevel(
      'Unhealthy',
      Color(0xFFFF4D4D),
      'Everyone may start to feel effects. Limit prolonged outdoor exertion.',
    );
  }
  if (aqi <= 300) {
    return const AqiLevel(
      'Very unhealthy',
      Color(0xFFB36BD1),
      'Health alert: avoid outdoor exertion.',
    );
  }
  return const AqiLevel(
    'Hazardous',
    Color(0xFFB0223F),
    'Emergency conditions. Stay indoors if you can.',
  );
}

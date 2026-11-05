import 'package:flutter/material.dart';

import '../models/weather.dart';
import '../utils/weather_codes.dart';
import 'weather_background.dart';

/// Which watercolor landscape fits the conditions.
String sceneAsset(WeatherData? d) {
  if (d == null) return 'assets/backgrounds/bg_day.webp';
  final c = d.current;
  if (!c.isDay) return 'assets/backgrounds/bg_night.webp';
  // Overcast reads as gloom — show the rain scene, since the model often
  // reports overcast while precipitation is starting.
  if (isRainCode(c.code) || c.code == 3 || c.code >= 95) {
    return 'assets/backgrounds/bg_rain.webp';
  }
  return 'assets/backgrounds/bg_day.webp';
}

/// Sky tint washed over the top of the illustration so white type reads
/// cleanly: a fresh blue by day, violet at night, slate in the rain.
Color sceneTint(String asset) {
  if (asset.endsWith('bg_night.webp')) return const Color(0xFF4637C9);
  if (asset.endsWith('bg_rain.webp')) return const Color(0xFF55657E);
  return const Color(0xFF5C93F2);
}

/// "It's Sunny" style phrase for the vertical label.
String conditionPhrase(int code, bool day) {
  if (code == 0 || code == 1) return day ? "It's Sunny" : "It's Clear";
  if (code == 2) return 'Partly Cloudy';
  if (code == 3) return "It's Cloudy";
  if (code == 45 || code == 48) return "It's Foggy";
  if (code >= 95) return "It's Stormy";
  if (isSnowCode(code)) return "It's Snowing";
  if (code >= 51 && code <= 57) return "It's Drizzling";
  if (isRainCode(code)) return "It's Raining";
  return describe(code);
}

/// Full-bleed watercolor landscape with the sky tint and live particles
/// (rain, snow, twinkling stars, lightning) on top. [bottomInset] lifts the
/// hills so they sit just above a bottom sheet.
class Scene extends StatelessWidget {
  final WeatherData? data;
  final double bottomInset;

  /// Which part of the (portrait) painting to keep when cropping. Phones
  /// keep the hills at the bottom; wide windows frame the middle so the
  /// sun / moon and horizon stay in view.
  final Alignment alignment;
  const Scene({
    super.key,
    required this.data,
    this.bottomInset = 0,
    this.alignment = Alignment.bottomCenter,
  });

  /// Framing for landscape / big-screen layouts.
  static const wideAlignment = Alignment(0, 0.1);

  @override
  Widget build(BuildContext context) {
    final asset = sceneAsset(data);
    final tint = sceneTint(asset);
    final h = MediaQuery.sizeOf(context).height;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: tint),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: bottomInset,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 900),
            child: Image.asset(
              asset,
              key: ValueKey(asset),
              fit: BoxFit.cover,
              alignment: alignment,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
            ),
          ),
        ),
        // Sky wash: solid tint at the top fading into the painting.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: h * 0.4,
          child: IgnorePointer(
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: tint),
              duration: const Duration(milliseconds: 900),
              builder: (_, c, _) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      c!.withAlpha(235),
                      c.withAlpha(120),
                      c.withAlpha(0),
                    ],
                    stops: const [0, 0.4, 1],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (data != null)
          IgnorePointer(
            child: WeatherBackground(
              code: data!.current.code,
              isDay: data!.current.isDay,
              clouds: false,
              child: const SizedBox.expand(),
            ),
          ),
      ],
    );
  }
}

/// Colors for the white "Weather Today" surface (and its dark-mode twin).
class SheetPalette {
  final Color bg, ink, soft, faint, card, track;
  final bool dark;
  const SheetPalette._(
      this.bg, this.ink, this.soft, this.faint, this.card, this.track, this.dark);

  static SheetPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const SheetPalette._(
              Color(0xFF1C1838),
              Colors.white,
              Color(0xB3FFFFFF),
              Color(0x66FFFFFF),
              Color(0x14FFFFFF),
              Color(0x26FFFFFF),
              true)
          : const SheetPalette._(
              Colors.white,
              Color(0xFF1F1A33),
              Color(0xFF8A86A0),
              Color(0xFFC9C6D6),
              Color(0xFFF5F3FB),
              Color(0xFFEAE7F3),
              false);
}

/// Small outlined ring used as the degree mark, like the big readout's.
class DegreeRing extends StatelessWidget {
  final double size;
  final double stroke;
  final Color color;
  const DegreeRing(
      {super.key, required this.size, required this.stroke, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: stroke),
        ),
      );
}

/// A temperature number with a small ring degree hanging top-right.
class RingTemp extends StatelessWidget {
  final String value;
  final double fontSize;
  final FontWeight weight;
  final Color color;
  const RingTemp(this.value,
      {super.key,
      required this.fontSize,
      this.weight = FontWeight.w300,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: TextStyle(
                fontSize: fontSize,
                fontWeight: weight,
                color: color,
                height: 1.1)),
        Padding(
          padding: EdgeInsets.only(top: fontSize * 0.2, left: 1),
          child: DegreeRing(
              size: fontSize * 0.16,
              stroke: fontSize * 0.035 + 0.6,
              color: color),
        ),
      ],
    );
  }
}

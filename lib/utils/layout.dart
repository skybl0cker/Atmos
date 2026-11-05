import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Screen-size breakpoints (logical pixels).
///
/// Phones — including big ones in portrait — stay under [wideLayoutMinWidth]
/// and keep the phone layout exactly. Unfolded foldables (~700–900),
/// tablets and desktop browsers switch to the side-by-side layouts.
const wideLayoutMinWidth = 700.0;

/// Wide enough for a third column (desktop browsers, big tablets in
/// landscape).
const threeColumnMinWidth = 1280.0;

/// Readable width cap for list-style screens on big displays.
const contentMaxWidth = 760.0;

bool isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= wideLayoutMinWidth;

/// Horizontal padding that centers [contentMaxWidth] of content on wide
/// screens, never less than [min].
double centeredGutter(BuildContext context, {double min = 0}) {
  final w = MediaQuery.sizeOf(context).width;
  return math.max(min, (w - contentMaxWidth) / 2);
}

/// Centers [child] and caps its width at [maxWidth]; a no-op on phones.
class MaxWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const MaxWidth({
    super.key,
    required this.child,
    this.maxWidth = contentMaxWidth,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

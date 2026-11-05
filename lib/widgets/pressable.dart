import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../utils/haptics.dart';

/// Light tap feedback respecting the user's haptics setting (no-op on web).
void tapHaptic(BuildContext context) {
  if (!hapticsSupported) return;
  if (!context.read<AppState>().hapticsEnabled) return;
  HapticFeedback.selectionClick();
}

/// Shrinks slightly while pressed and fires a selection haptic on tap.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double pressedScale;
  final String? semanticLabel;
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.pressedScale = 0.93,
    this.semanticLabel,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: () {
          tapHaptic(context);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _down ? widget.pressedScale : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Fades and lifts its child in once, after [delay] — used to stagger the
/// home sections as they appear.
class Reveal extends StatelessWidget {
  final Widget child;
  final Duration delay;
  const Reveal({super.key, required this.child, this.delay = Duration.zero});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    const run = 650;
    final total = delay.inMilliseconds + run;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(
        delay.inMilliseconds / total,
        1,
        curve: Curves.easeOutCubic,
      ),
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 24 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether this device can actually produce haptic feedback.
///
/// Flutter web routes HapticFeedback through navigator.vibrate, which iOS
/// Safari does not support at all (and Flutter's web embedding never calls
/// it anyway), so on the web build — including the iOS home-screen install —
/// haptics are silently dropped. On native mobile they work.
bool get hapticsSupported => !kIsWeb;

/// Fires a haptic pattern matching the current condition. Callers should
/// check [hapticsSupported] first and fall back to a visual cue when it is
/// false.
Future<void> hapticsForCode(int code) async {
  if (!hapticsSupported) return;
  if (code >= 95) {
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 180));
    await HapticFeedback.heavyImpact();
  } else if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) {
    await HapticFeedback.lightImpact();
  }
}

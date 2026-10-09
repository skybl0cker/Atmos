import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// Observed precipitation-echo motion, measured by cross-correlating two
/// consecutive RainViewer radar tiles in a background isolate.
///
/// Unlike the model steering wind (a forecast of where air *should* go),
/// this measures where the echoes *actually* went between the last two
/// observed frames — discrete propagation, outflow boundaries and all.
/// Callers fall back to the layer-mean model wind when this returns null.
class EchoMotion {
  /// Motion vector in m/s. Positive east, positive north.
  final double eastMs;
  final double northMs;

  /// 0..1 — sharpness of the correlation peak. High means the echo field
  /// translated coherently; low means it mostly grew, decayed or morphed.
  final double confidence;

  const EchoMotion({
    required this.eastMs,
    required this.northMs,
    required this.confidence,
  });

  double get speedKmh =>
      math.sqrt(eastMs * eastMs + northMs * northMs) * 3.6;

  /// Compass direction the echo is moving TOWARD, in degrees.
  int get toDir =>
      ((math.atan2(eastMs, northMs) * 180 / math.pi) % 360).round() % 360;
}

class EchoMotionService {
  /// Measures echo motion between two radar tiles of the same {z}/{x}/{y}.
  /// [tileUrlA] is the older frame, [tileUrlB] the newer, [dtSeconds] the
  /// actual time between them. Returns null when the tiles can't be fetched,
  /// there's too little echo, the correlation is weak, or the implied speed
  /// is unphysical (> 45 m/s sustained echo motion doesn't happen).
  static Future<EchoMotion?> estimate({
    required String tileUrlA,
    required String tileUrlB,
    required double dtSeconds,
    required double lat,
    int zoom = 7,
  }) async {
    if (dtSeconds <= 0) return null;
    try {
      final rs = await Future.wait([
        http.get(Uri.parse(tileUrlA)).timeout(const Duration(seconds: 12)),
        http.get(Uri.parse(tileUrlB)).timeout(const Duration(seconds: 12)),
      ]);
      final a = rs[0], b = rs[1];
      if (a.statusCode != 200 || b.statusCode != 200) return null;
      if (a.bodyBytes.isEmpty || b.bodyBytes.isEmpty) return null;
      return await compute(
        _estimate,
        _MotionInput(a.bodyBytes, b.bodyBytes, dtSeconds, lat, zoom),
      );
    } catch (_) {
      return null;
    }
  }
}

class _MotionInput {
  final Uint8List a;
  final Uint8List b;
  final double dtSeconds;
  final double lat;
  final int zoom;
  const _MotionInput(this.a, this.b, this.dtSeconds, this.lat, this.zoom);
}

class _Shift {
  final int dx;
  final int dy;
  final double confidence;
  const _Shift(this.dx, this.dy, this.confidence);
}

EchoMotion? _estimate(_MotionInput q) {
  final ia = img.decodePng(q.a);
  final ib = img.decodePng(q.b);
  if (ia == null || ib == null) return null;
  if (ia.width != ib.width || ia.height != ib.height || ia.width < 64) {
    return null;
  }
  final n = ia.width;
  final fa = _field(ia);
  final fb = _field(ib);

  // Bail when there's barely any echo to track.
  var echo = 0;
  for (var i = 0; i < fa.length; i++) {
    if (fa[i] > 0.02 || fb[i] > 0.02) echo++;
  }
  if (echo < fa.length * 0.015) return null;

  // Coarse pass at 64x64, then refine at full resolution around the fix.
  // The coarse confidence gates acceptance: it measures how sharp the
  // correlation peak is over the whole search range. The fine pass only
  // refines the fix within ±4 px, so its peak is flat by construction and
  // must not be used as a confidence metric.
  final coarse = _bestShift(_downsample(fa, n, 64), _downsample(fb, n, 64),
      64, 16);
  if (coarse.confidence < 0.2) return null;
  final k = n ~/ 64;
  final fine = _bestShift(fa, fb, n, 4,
      centerX: coarse.dx * k, centerY: coarse.dy * k);

  final mpp =
      156543.03392 * math.cos(q.lat * math.pi / 180) / math.pow(2, q.zoom);
  final eastMs = fine.dx * mpp / q.dtSeconds;
  final northMs = -fine.dy * mpp / q.dtSeconds; // tile y grows downward
  final speed = math.sqrt(eastMs * eastMs + northMs * northMs);
  if (speed > 45) return null;
  return EchoMotion(
      eastMs: eastMs, northMs: northMs, confidence: coarse.confidence);
}

/// Echo intensity 0..1: alpha-weighted luminance. RainViewer's Universal
/// Blue tiles are transparent where there's no echo, so alpha alone is a
/// decent echo mask; weighting by luminance tracks echo strength.
Float64List _field(img.Image im) {
  final f = Float64List(im.width * im.height);
  var i = 0;
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      final p = im.getPixel(x, y);
      final a = p.a / 255.0;
      if (a < 0.15) {
        i++;
        continue;
      }
      final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) / 255.0;
      f[i++] = a * lum;
    }
  }
  return f;
}

Float64List _downsample(Float64List f, int n, int m) {
  final out = Float64List(m * m);
  final s = n ~/ m;
  for (var y = 0; y < m; y++) {
    for (var x = 0; x < m; x++) {
      var sum = 0.0;
      for (var dy = 0; dy < s; dy++) {
        var idx = (y * s + dy) * n + x * s;
        for (var dx = 0; dx < s; dx++) {
          sum += f[idx++];
        }
      }
      out[y * m + x] = sum / (s * s);
    }
  }
  return out;
}

/// Finds the integer pixel shift of B relative to A minimizing the
/// sum-of-squared-differences over their overlap. Confidence is
/// 1 - best/mean SSD: a sharp unique minimum scores near 1.
_Shift _bestShift(Float64List a, Float64List b, int n, int range,
    {int centerX = 0, int centerY = 0}) {
  var bestDx = centerX, bestDy = centerY;
  var best = double.infinity, sum = 0.0, cnt = 0;
  for (var dy = centerY - range; dy <= centerY + range; dy++) {
    for (var dx = centerX - range; dx <= centerX + range; dx++) {
      final x0 = dx < 0 ? -dx : 0;
      final x1 = dx < 0 ? n : n - dx;
      final y0 = dy < 0 ? -dy : 0;
      final y1 = dy < 0 ? n : n - dy;
      if (x0 >= x1 || y0 >= y1) continue;
      var ssd = 0.0;
      for (var y = y0; y < y1; y++) {
        var ai = y * n + x0;
        var bi = (y + dy) * n + x0 + dx;
        for (var x = x0; x < x1; x++) {
          final d = a[ai++] - b[bi++];
          ssd += d * d;
        }
      }
      sum += ssd;
      cnt++;
      if (ssd < best) {
        best = ssd;
        bestDx = dx;
        bestDy = dy;
      }
    }
  }
  if (cnt == 0) return const _Shift(0, 0, 0);
  final mean = sum / cnt;
  final confidence =
      mean <= 0 ? 0.0 : (1 - best / mean).clamp(0.0, 1.0);
  return _Shift(bestDx, bestDy, confidence);
}

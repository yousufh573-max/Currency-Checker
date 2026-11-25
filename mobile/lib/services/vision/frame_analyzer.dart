import 'dart:math' as math;
import 'dart:typed_data';

/// Luminance (Y) plane of a camera frame.
class LumaFrame {
  const LumaFrame({required this.bytes, required this.width, required this.height, required this.rowStride, this.rotation = 0});
  final Uint8List bytes;
  final int width;
  final int height;
  final int rowStride;

  /// Clockwise rotation (0/90/180/270) needed to make the frame upright (portrait).
  final int rotation;
}

/// Normalised rectangle (0..1) in upright image coordinates.
class NRect {
  const NRect(this.left, this.top, this.right, this.bottom);
  final double left, top, right, bottom;
  double get width => right - left;
  double get height => bottom - top;
  double get cx => (left + right) / 2;
  double get cy => (top + bottom) / 2;
  @override
  String toString() => 'NRect(${left.toStringAsFixed(2)}, ${top.toStringAsFixed(2)}, ${right.toStringAsFixed(2)}, ${bottom.toStringAsFixed(2)})';
}

class FrameAnalysis {
  const FrameAnalysis({
    required this.guidance,
    required this.notePresent,
    required this.ready,
    this.noteRect,
    this.brightness = 0,
    this.sharpness = 0,
    this.multiple = false,
  });

  /// Guidance key (see S.guidance), e.g. 'move_left', 'hold_steady'.
  final String guidance;
  final bool notePresent;

  /// Positioned, lit, sharp, single and stable: safe to capture.
  final bool ready;
  final NRect? noteRect;
  final double brightness;
  final double sharpness;
  final bool multiple;
}

/// Analyses low-resolution luminance to guide the user and decide when to
/// auto-capture. Runs in a few milliseconds per frame (96-px grid).
class FrameAnalyzer {
  FrameAnalyzer({this.gridW = 96, this.stableFramesNeeded = 4});

  final int gridW;
  final int stableFramesNeeded;
  NRect? _prevRect;
  Float32List? _prevGrid;
  int _stableCount = 0;

  void reset() {
    _prevRect = null;
    _prevGrid = null;
    _stableCount = 0;
  }

  /// Samples the Y plane into an upright grid. Returns (grid, w, h).
  (Float32List, int, int) _downsample(LumaFrame f) {
    final step = f.width / gridW;
    final sh = (f.height / step).floor();
    final sw = gridW;
    final rot = f.rotation % 360;
    final ow = (rot == 90 || rot == 270) ? sh : sw;
    final oh = (rot == 90 || rot == 270) ? sw : sh;
    final out = Float32List(ow * oh);
    for (var sy = 0; sy < sh; sy++) {
      final py = (sy * step + step / 2).floor().clamp(0, f.height - 1);
      for (var sx = 0; sx < sw; sx++) {
        final px = (sx * step + step / 2).floor().clamp(0, f.width - 1);
        final v = f.bytes[py * f.rowStride + px].toDouble();
        int ox, oy;
        switch (rot) {
          case 90:
            ox = sh - 1 - sy;
            oy = sx;
          case 180:
            ox = sw - 1 - sx;
            oy = sh - 1 - sy;
          case 270:
            ox = sy;
            oy = sw - 1 - sx;
          default:
            ox = sx;
            oy = sy;
        }
        out[oy * ow + ox] = v;
      }
    }
    return (out, ow, oh);
  }

  /// Variance of the Laplacian on a full-resolution central window.
  static double sharpness(LumaFrame f) {
    final cx = f.width ~/ 2, cy = f.height ~/ 2;
    final half = math.min(160, math.min(f.width, f.height) ~/ 3);
    double sum = 0, sum2 = 0;
    var n = 0;
    for (var y = cy - half; y < cy + half; y += 2) {
      final r = y * f.rowStride;
      for (var x = cx - half; x < cx + half; x += 2) {
        final c = f.bytes[r + x];
        final lap = 4 * c - f.bytes[r + x - 1] - f.bytes[r + x + 1] - f.bytes[r - f.rowStride + x] - f.bytes[r + f.rowStride + x];
        sum += lap;
        sum2 += lap * lap;
        n++;
      }
    }
    if (n == 0) return 0;
    final mean = sum / n;
    return sum2 / n - mean * mean;
  }

  FrameAnalysis analyze(LumaFrame f, {required NRect guide}) {
    final (g, w, h) = _downsample(f);
    var total = 0.0;
    for (final v in g) {
      total += v;
    }
    final brightness = total / g.length;
    final sharp = sharpness(f);

    // Background reference: median of the border ring.
    final border = <double>[];
    for (var x = 0; x < w; x++) {
      border
        ..add(g[x])
        ..add(g[(h - 1) * w + x]);
    }
    for (var y = 0; y < h; y++) {
      border
        ..add(g[y * w])
        ..add(g[y * w + w - 1]);
    }
    border.sort();
    final bgMed = border[border.length ~/ 2];

    // Foreground: textured (gradient) or different luminance from background.
    final fg = Uint8List(w * h);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final gx = (g[i + 1] - g[i - 1]).abs();
        final gy = (g[i + w] - g[i - w]).abs();
        if (gx + gy > 18 || (g[i] - bgMed).abs() > 28) fg[i] = 1;
      }
    }
    final comps = _components(_close(fg, w, h), w, h);
    final minArea = 0.04 * w * h;
    final big = comps.where((c) => c.area >= minArea).toList()..sort((a, b) => b.area.compareTo(a.area));

    String key;
    var ready = false;
    NRect? rect;
    final multiple = big.length > 1 && big[1].area > 0.35 * big[0].area;

    if (brightness < 45) {
      key = 'improve_lighting';
    } else if (brightness > 228) {
      key = 'reduce_glare';
    } else if (big.isEmpty) {
      key = 'place_note';
    } else if (multiple) {
      key = 'one_note';
      rect = big[0].rect(w, h);
    } else {
      rect = big[0].rect(w, h);
      final touches = rect.left <= 0.01 || rect.top <= 0.01 || rect.right >= 0.99 || rect.bottom >= 0.99;
      final coverage = rect.width / guide.width;
      final dx = (rect.cx - guide.cx) / guide.width;
      final dy = (rect.cy - guide.cy) / guide.height;
      if (coverage > 1.08 || touches) {
        key = 'move_farther';
      } else if (coverage < 0.55) {
        key = 'move_closer';
      } else if (dx > 0.12) {
        key = 'move_left';
      } else if (dx < -0.12) {
        key = 'move_right';
      } else if (dy > 0.2) {
        key = 'move_up';
      } else if (dy < -0.2) {
        key = 'move_down';
      } else if (sharp < 40) {
        key = 'hold_steady';
      } else {
        key = 'capturing';
        ready = true;
      }
    }

    // Stability: bounding box and image content barely change across frames.
    final stableNow = rect != null && _prevRect != null && _rectDelta(rect, _prevRect!) < 0.03 && _gridDiff(g) < 6.0;
    _stableCount = stableNow ? _stableCount + 1 : 0;
    _prevRect = rect;
    _prevGrid = g;
    if (ready && _stableCount < stableFramesNeeded) {
      ready = false;
      key = 'hold_steady';
    }
    return FrameAnalysis(
      guidance: key, notePresent: big.isNotEmpty, ready: ready, noteRect: rect, brightness: brightness, sharpness: sharp, multiple: multiple);
  }

  double _gridDiff(Float32List g) {
    final p = _prevGrid;
    if (p == null || p.length != g.length) return 255;
    var s = 0.0;
    for (var i = 0; i < g.length; i++) {
      s += (g[i] - p[i]).abs();
    }
    return s / g.length;
  }

  static double _rectDelta(NRect a, NRect b) => [
        (a.left - b.left).abs(),
        (a.top - b.top).abs(),
        (a.right - b.right).abs(),
        (a.bottom - b.bottom).abs()
      ].reduce(math.max);

  static Uint8List _close(Uint8List m, int w, int h) {
    Uint8List morph(Uint8List src, bool dilate) {
      final out = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          var v = dilate ? 0 : 1;
          for (var dy = -1; dy <= 1; dy++) {
            final yy = y + dy;
            if (yy < 0 || yy >= h) continue;
            for (var dx = -1; dx <= 1; dx++) {
              final xx = x + dx;
              if (xx < 0 || xx >= w) continue;
              final s = src[yy * w + xx];
              if (dilate && s == 1) v = 1;
              if (!dilate && s == 0) v = 0;
            }
          }
          out[y * w + x] = v;
        }
      }
      return out;
    }

    return morph(morph(m, true), false);
  }

  static List<_Comp> _components(Uint8List m, int w, int h) {
    final labels = Int32List(w * h);
    final comps = <_Comp>[];
    final stack = <int>[];
    var next = 0;
    for (var i = 0; i < m.length; i++) {
      if (m[i] == 0 || labels[i] != 0) continue;
      next++;
      final c = _Comp();
      stack.add(i);
      labels[i] = next;
      while (stack.isNotEmpty) {
        final p = stack.removeLast();
        final x = p % w, y = p ~/ w;
        c.add(x, y);
        for (final q in [if (x > 0) p - 1, if (x < w - 1) p + 1, if (y > 0) p - w, if (y < h - 1) p + w]) {
          if (m[q] == 1 && labels[q] == 0) {
            labels[q] = next;
            stack.add(q);
          }
        }
      }
      comps.add(c);
    }
    return comps;
  }
}

class _Comp {
  int area = 0, minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1;
  void add(int x, int y) {
    area++;
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }

  NRect rect(int w, int h) => NRect(minX / w, minY / h, (maxX + 1) / w, (maxY + 1) / h);
}

/// Prevents re-capturing the same note: after a capture, the note must leave
/// the frame (several empty frames) before the next automatic capture.
class CaptureGate {
  CaptureGate({this.emptyFramesToRearm = 5});
  final int emptyFramesToRearm;
  bool _armed = true;
  int _empty = 0;

  bool get armed => _armed;

  /// Returns true when an automatic capture should happen now.
  bool onFrame(FrameAnalysis a) {
    if (!_armed) {
      _empty = a.notePresent ? 0 : _empty + 1;
      if (_empty >= emptyFramesToRearm) {
        _armed = true;
        _empty = 0;
      }
      return false;
    }
    return a.ready;
  }

  void markCaptured() {
    _armed = false;
    _empty = 0;
  }

  /// Manual capture or a fresh scanner screen re-arms immediately only when
  /// the user explicitly asks (e.g. "Rescan" of a rejected note).
  void rearm() {
    _armed = true;
    _empty = 0;
  }
}

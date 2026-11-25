import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// On-device torn-area estimation (Dart port of backend/app/services/torn.py).
///
/// Background model from border colour → foreground mask (shadows and
/// border-connected skin/fingers excluded) → largest component → convex hull →
/// minimum-area rectangle (expected geometry, extrapolated by expected aspect
/// ratio when an end is missing) → torn % = (expected − remaining) / expected.
///
/// Fold detection is only implemented server-side; on-device results flag
/// notes touching the frame, multiple notes and finger occlusion as unreliable.
class TornEstimate {
  TornEstimate({required this.found, this.reliable = false, this.tornRatio, this.flags = const [], this.reason, this.crop, this.aspect});
  final bool found;
  final bool reliable;
  final double? tornRatio;
  final List<String> flags;
  final String? reason;

  /// Rotation-corrected crop of the note for the classifier.
  final img.Image? crop;
  final double? aspect;
}

const _genericAspect = (1.75, 2.45);

double _median(List<double> v) {
  v.sort();
  return v[v.length ~/ 2];
}

TornEstimate estimateTorn(img.Image source, {double? expectedAspect, int maxSide = 360}) {
  final scale = maxSide / math.max(source.width, source.height);
  final im = scale < 1 ? img.copyResize(source, width: (source.width * scale).round(), interpolation: img.Interpolation.average) : source;
  final w = im.width, h = im.height, n = w * h;
  final rgb = im.getBytes(order: img.ChannelOrder.rgb);

  final yy = Float32List(n), cb = Float32List(n), cr = Float32List(n);
  for (var i = 0; i < n; i++) {
    final r = rgb[i * 3].toDouble(), g = rgb[i * 3 + 1].toDouble(), b = rgb[i * 3 + 2].toDouble();
    yy[i] = 0.299 * r + 0.587 * g + 0.114 * b;
    cb[i] = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b;
    cr[i] = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b;
  }

  // Border statistics (robust).
  final bw = math.max(2, (math.min(w, h) * 0.04).round());
  final idx = <int>[];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (x < bw || y < bw || x >= w - bw || y >= h - bw) idx.add(y * w + x);
    }
  }
  (double, double) stat(Float32List c) {
    final vals = [for (final i in idx) c[i].toDouble()];
    final med = _median(List.of(vals));
    final mad = _median([for (final v in vals) (v - med).abs()]) * 1.4826 + 2.0;
    return (med, mad);
  }

  final (my, sy) = stat(yy);
  final (mcb, scb) = stat(cb);
  final (mcr, scr) = stat(cr);
  final bgSpread = (sy + scb + scr) / 3;

  // Skin (fingers) – keep only components touching the image border.
  var skin = Uint8List(n);
  var borderSkin = 0;
  for (var i = 0; i < n; i++) {
    if (yy[i] > 40 && cr[i] >= 138 && cr[i] <= 173 && cb[i] >= 77 && cb[i] <= 127) skin[i] = 1;
  }
  for (final i in idx) {
    borderSkin += skin[i];
  }
  if (borderSkin / idx.length > 0.3) {
    skin = Uint8List(n);
  } else {
    skin = _keepBorderComponents(skin, w, h);
  }

  var fg = Uint8List(n);
  for (var i = 0; i < n; i++) {
    final dl = (yy[i] - my) / sy;
    final dc = math.sqrt(math.pow((cb[i] - mcb) / scb, 2) + math.pow((cr[i] - mcr) / scr, 2));
    final shadow = dl < -1.0 && dc < 2.5;
    if (!shadow && math.sqrt(math.pow(0.5 * dl, 2) + dc * dc) > 3.0 && skin[i] == 0) fg[i] = 1;
  }
  fg = _morph(_morph(fg, w, h, false), w, h, true); // open
  fg = _morph(_morph(fg, w, h, true), w, h, false); // close

  final comps = _labels(fg, w, h);
  if (comps.sizes.isEmpty) return TornEstimate(found: false, reason: 'no_note_found');
  final order = List.generate(comps.sizes.length, (i) => i)..sort((a, b) => comps.sizes[b].compareTo(comps.sizes[a]));
  final mainLabel = order.first + 1;
  final mainArea = comps.sizes[order.first];
  if (mainArea < 0.05 * n) return TornEstimate(found: false, reason: 'note_too_small_or_absent', flags: ['move_closer']);

  final flags = <String>[];
  if (order.length > 1 && comps.sizes[order[1]] > 0.25 * mainArea) flags.add('multiple_notes');

  final mask = Uint8List(n);
  var minX = w, minY = h, maxX = 0, maxY = 0;
  for (var i = 0; i < n; i++) {
    if (comps.labels[i] == mainLabel) {
      mask[i] = 1;
      final x = i % w, y = i ~/ w;
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }
  }
  if (minX <= 1 || minY <= 1 || maxX >= w - 2 || maxY >= h - 2) flags.add('touches_frame_edge');

  // Internal holes (not reachable from the border without crossing the note).
  final outside = _floodOutside(mask, w, h);
  var holes = 0;
  for (var i = 0; i < n; i++) {
    if (mask[i] == 0 && outside[i] == 0) holes++;
  }
  if (holes < 0.002 * mainArea) holes = 0;

  // Hull points: note boundary + skin touching the note (occluders).
  final pts = <math.Point<double>>[];
  var skinOnNote = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final boundary = mask[i] == 1 && (x == 0 || y == 0 || x == w - 1 || y == h - 1 || mask[i - 1] == 0 || mask[i + 1] == 0 || mask[i - w] == 0 || mask[i + w] == 0);
      if (boundary) pts.add(math.Point(x.toDouble(), y.toDouble()));
      if (skin[i] == 1 && _near(mask, w, h, x, y, 4)) {
        skinOnNote++;
        pts.add(math.Point(x.toDouble(), y.toDouble()));
      }
    }
  }
  final hull = _convexHull(pts);
  final box = _minAreaRect(hull);
  if (box == null || box.short < 8) return TornEstimate(found: false, reason: 'note_geometry_invalid');
  final aspect = box.long / box.short;

  final target = expectedAspect ?? (_genericAspect.$1 + _genericAspect.$2) / 2;
  final lo = expectedAspect == null ? _genericAspect.$1 : expectedAspect * 0.93;
  final hi = expectedAspect == null ? _genericAspect.$2 : expectedAspect * 1.07;
  var expectedLong = box.long;
  if (aspect < lo) {
    expectedLong = box.short * target;
    flags.add('geometry_extrapolated');
  } else if (aspect > hi * 1.12) {
    flags.add('unexpected_shape');
  }
  if (skinOnNote > 0.01 * mainArea) flags.add('occlusion');
  if (bgSpread > 25) flags.add('busy_background');

  final expected = box.short * expectedLong;
  final remaining = (mainArea - holes).toDouble();
  final occluded = flags.contains('occlusion') ? skinOnNote.toDouble() : 0.0;
  var torn = ((expected - remaining - occluded) / expected * 100).clamp(0.0, 100.0);
  if (torn <= 1.0) torn = 0;

  const blockers = {'touches_frame_edge', 'multiple_notes', 'occlusion', 'unexpected_shape', 'busy_background'};
  final blocking = flags.where(blockers.contains).toList();

  // Rotation-corrected crop at source resolution for the classifier.
  final inv = 1 / (scale < 1 ? scale : 1);
  final rotated = img.copyRotate(source, angle: -box.angleDeg);
  final cx = rotated.width / 2 + ((box.cx * inv - source.width / 2) * math.cos(-box.angle) - (box.cy * inv - source.height / 2) * math.sin(-box.angle));
  final cy = rotated.height / 2 + ((box.cx * inv - source.width / 2) * math.sin(-box.angle) + (box.cy * inv - source.height / 2) * math.cos(-box.angle));
  final cw = (box.alongLong ? box.long : box.short) * inv, ch = (box.alongLong ? box.short : box.long) * inv;
  var crop = img.copyCrop(rotated,
      x: (cx - cw / 2).round().clamp(0, rotated.width - 1),
      y: (cy - ch / 2).round().clamp(0, rotated.height - 1),
      width: cw.round().clamp(1, rotated.width),
      height: ch.round().clamp(1, rotated.height));
  if (crop.height > crop.width) crop = img.copyRotate(crop, angle: 90);

  return TornEstimate(
    found: true,
    reliable: blocking.isEmpty,
    tornRatio: double.parse(torn.toStringAsFixed(1)),
    flags: flags,
    reason: blocking.isEmpty ? null : blocking.first,
    crop: crop,
    aspect: aspect,
  );
}

bool _near(Uint8List m, int w, int h, int x, int y, int r) {
  for (var dy = -r; dy <= r; dy += 2) {
    for (var dx = -r; dx <= r; dx += 2) {
      final xx = x + dx, yy = y + dy;
      if (xx >= 0 && yy >= 0 && xx < w && yy < h && m[yy * w + xx] == 1) return true;
    }
  }
  return false;
}

Uint8List _morph(Uint8List src, int w, int h, bool dilate) {
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var v = dilate ? 0 : 1;
      outer:
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final xx = (x + dx).clamp(0, w - 1), yy = (y + dy).clamp(0, h - 1);
          final s = src[yy * w + xx];
          if (dilate && s == 1) {
            v = 1;
            break outer;
          }
          if (!dilate && s == 0) {
            v = 0;
            break outer;
          }
        }
      }
      out[y * w + x] = v;
    }
  }
  return out;
}

class _Labels {
  _Labels(this.labels, this.sizes);
  final Int32List labels;
  final List<int> sizes;
}

_Labels _labels(Uint8List m, int w, int h) {
  final labels = Int32List(w * h);
  final sizes = <int>[];
  final stack = <int>[];
  for (var i = 0; i < m.length; i++) {
    if (m[i] == 0 || labels[i] != 0) continue;
    final lab = sizes.length + 1;
    var size = 0;
    labels[i] = lab;
    stack.add(i);
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      size++;
      final x = p % w, y = p ~/ w;
      if (x > 0 && m[p - 1] == 1 && labels[p - 1] == 0) { labels[p - 1] = lab; stack.add(p - 1); }
      if (x < w - 1 && m[p + 1] == 1 && labels[p + 1] == 0) { labels[p + 1] = lab; stack.add(p + 1); }
      if (y > 0 && m[p - w] == 1 && labels[p - w] == 0) { labels[p - w] = lab; stack.add(p - w); }
      if (y < h - 1 && m[p + w] == 1 && labels[p + w] == 0) { labels[p + w] = lab; stack.add(p + w); }
    }
    sizes.add(size);
  }
  return _Labels(labels, sizes);
}

Uint8List _keepBorderComponents(Uint8List m, int w, int h) {
  final l = _labels(m, w, h);
  final keep = <int>{};
  for (var x = 0; x < w; x++) {
    keep..add(l.labels[x])..add(l.labels[(h - 1) * w + x]);
  }
  for (var y = 0; y < h; y++) {
    keep..add(l.labels[y * w])..add(l.labels[y * w + w - 1]);
  }
  keep.remove(0);
  final out = Uint8List(w * h);
  for (var i = 0; i < out.length; i++) {
    if (keep.contains(l.labels[i])) out[i] = 1;
  }
  return out;
}

Uint8List _floodOutside(Uint8List mask, int w, int h) {
  final out = Uint8List(w * h);
  final stack = <int>[];
  void seed(int i) {
    if (mask[i] == 0 && out[i] == 0) {
      out[i] = 1;
      stack.add(i);
    }
  }

  for (var x = 0; x < w; x++) {
    seed(x);
    seed((h - 1) * w + x);
  }
  for (var y = 0; y < h; y++) {
    seed(y * w);
    seed(y * w + w - 1);
  }
  while (stack.isNotEmpty) {
    final p = stack.removeLast();
    final x = p % w, y = p ~/ w;
    if (x > 0) seed(p - 1);
    if (x < w - 1) seed(p + 1);
    if (y > 0) seed(p - w);
    if (y < h - 1) seed(p + w);
  }
  return out;
}

List<math.Point<double>> _convexHull(List<math.Point<double>> pts) {
  if (pts.length < 3) return pts;
  final p = List.of(pts)..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  double cross(math.Point<double> o, math.Point<double> a, math.Point<double> b) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  final lower = <math.Point<double>>[], upper = <math.Point<double>>[];
  for (final q in p) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, q) <= 0) {
      lower.removeLast();
    }
    lower.add(q);
  }
  for (final q in p.reversed) {
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, q) <= 0) {
      upper.removeLast();
    }
    upper.add(q);
  }
  return [...lower.sublist(0, lower.length - 1), ...upper.sublist(0, upper.length - 1)];
}

class _Box {
  _Box(this.cx, this.cy, this.a, this.b, this.angle);
  final double cx, cy, a, b, angle; // a along angle direction, b perpendicular
  double get long => math.max(a, b);
  double get short => math.min(a, b);
  bool get alongLong => a >= b;
  double get angleDeg => angle * 180 / math.pi;
}

/// Rotating-calipers minimum-area enclosing rectangle (+1 px for pixel extent).
_Box? _minAreaRect(List<math.Point<double>> hull) {
  if (hull.length < 3) return null;
  _Box? best;
  var bestArea = double.infinity;
  for (var i = 0; i < hull.length; i++) {
    final p1 = hull[i], p2 = hull[(i + 1) % hull.length];
    final th = math.atan2(p2.y - p1.y, p2.x - p1.x);
    final c = math.cos(th), s = math.sin(th);
    var minU = double.infinity, maxU = -double.infinity, minV = double.infinity, maxV = -double.infinity;
    for (final q in hull) {
      final u = q.x * c + q.y * s, v = -q.x * s + q.y * c;
      minU = math.min(minU, u);
      maxU = math.max(maxU, u);
      minV = math.min(minV, v);
      maxV = math.max(maxV, v);
    }
    final a = maxU - minU + 1, b = maxV - minV + 1;
    if (a * b < bestArea) {
      bestArea = a * b;
      final mu = (minU + maxU) / 2, mv = (minV + maxV) / 2;
      best = _Box(mu * c - mv * s, mu * s + mv * c, a, b, th);
    }
  }
  return best;
}

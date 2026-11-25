import 'dart:math' as math;
import 'dart:typed_data';

import 'package:banknote_assistant/services/vision/frame_analyzer.dart';
import 'package:banknote_assistant/services/vision/torn_estimator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Synthetic luma frame: plain background with a textured rectangle.
LumaFrame frame({double cx = 0.5, double cy = 0.48, double w = 0.75, double h = 0.3, int bg = 150, int seed = 0, bool note = true, int width = 480, int height = 640}) {
  final b = Uint8List(width * height)..fillRange(0, width * height, bg);
  if (note) {
    final rnd = math.Random(seed);
    final x0 = ((cx - w / 2) * width).round(), x1 = ((cx + w / 2) * width).round();
    final y0 = ((cy - h / 2) * height).round(), y1 = ((cy + h / 2) * height).round();
    for (var y = math.max(0, y0); y < math.min(height, y1); y++) {
      for (var x = math.max(0, x0); x < math.min(width, x1); x++) {
        b[y * width + x] = (90 + 60 * math.sin(x / 5.0) * math.cos(y / 7.0) + rnd.nextInt(10)).round().clamp(0, 255);
      }
    }
  }
  return LumaFrame(bytes: b, width: width, height: height, rowStride: width);
}

const guide = NRect(0.12, 0.3, 0.88, 0.66);

void main() {
  group('FrameAnalyzer guidance', () {
    test('empty frame asks to place a note', () {
      expect(FrameAnalyzer().analyze(frame(note: false), guide: guide).guidance, 'place_note');
    });
    test('dark frame asks for light', () {
      expect(FrameAnalyzer().analyze(frame(bg: 20, note: false), guide: guide).guidance, 'improve_lighting');
    });
    test('note to the right → move left', () {
      expect(FrameAnalyzer().analyze(frame(cx: 0.62, w: 0.6), guide: guide).guidance, 'move_left');
    });
    test('note to the left → move right', () {
      expect(FrameAnalyzer().analyze(frame(cx: 0.38, w: 0.6), guide: guide).guidance, 'move_right');
    });
    test('small note → move closer', () {
      expect(FrameAnalyzer().analyze(frame(w: 0.3, h: 0.12), guide: guide).guidance, 'move_closer');
    });
    test('note larger than the frame → move farther', () {
      expect(FrameAnalyzer().analyze(frame(w: 1.1, h: 0.45), guide: guide).guidance, 'move_farther');
    });
    test('two notes → one note at a time', () {
      final a = frame(cx: 0.5, cy: 0.3, w: 0.6, h: 0.18);
      final b2 = frame(cx: 0.5, cy: 0.72, w: 0.6, h: 0.18, seed: 3);
      final merged = Uint8List.fromList([for (var i = 0; i < a.bytes.length; i++) a.bytes[i] != 150 ? a.bytes[i] : b2.bytes[i]]);
      final r = FrameAnalyzer().analyze(LumaFrame(bytes: merged, width: 480, height: 640, rowStride: 480), guide: guide);
      expect(r.multiple, isTrue);
      expect(r.guidance, 'one_note');
    });
    test('well-placed note becomes ready only after it is stable', () {
      final fa = FrameAnalyzer(stableFramesNeeded: 3);
      final first = fa.analyze(frame(), guide: guide);
      expect(first.ready, isFalse);
      expect(first.guidance, 'hold_steady');
      FrameAnalysis last = first;
      for (var i = 0; i < 4; i++) {
        last = fa.analyze(frame(), guide: guide);
      }
      expect(last.ready, isTrue);
    });
    test('rotation 90 maps sensor frame to upright coordinates', () {
      // A landscape sensor frame whose note is at the top becomes "right" in portrait.
      final f = frame(width: 640, height: 480, cx: 0.5, cy: 0.3, w: 0.3, h: 0.6);
      final r = FrameAnalyzer().analyze(LumaFrame(bytes: f.bytes, width: 640, height: 480, rowStride: 640, rotation: 90), guide: guide);
      expect(r.noteRect!.cx, greaterThan(0.6));
    });
  });

  group('CaptureGate (no repeated capture of the same note)', () {
    const ready = FrameAnalysis(guidance: 'capturing', notePresent: true, ready: true);
    const present = FrameAnalysis(guidance: 'hold_steady', notePresent: true, ready: false);
    const empty = FrameAnalysis(guidance: 'place_note', notePresent: false, ready: false);

    test('captures once, then waits for the note to leave the frame', () {
      final g = CaptureGate(emptyFramesToRearm: 3);
      expect(g.onFrame(ready), isTrue);
      g.markCaptured();
      for (var i = 0; i < 10; i++) {
        expect(g.onFrame(ready), isFalse, reason: 'same note still in frame');
      }
      g.onFrame(empty);
      g.onFrame(present); // note came back before leaving long enough
      g.onFrame(empty);
      g.onFrame(empty);
      expect(g.armed, isFalse);
      g.onFrame(empty);
      expect(g.armed, isTrue);
      expect(g.onFrame(ready), isTrue, reason: 'next note can be captured');
    });
  });

  group('On-device torn estimator', () {
    img.Image scene({double tornFrac = 0, double angle = 0, int nw = 300, int nh = 140}) {
      final note = img.Image(width: nw, height: nh, numChannels: 4);
      for (var y = 0; y < nh; y++) {
        for (var x = 0; x < nw; x++) {
          note.setPixelRgba(x, y, (70 + 40 * math.cos(x / 11)).round(), (150 + 50 * math.sin((x + y) / 31)).round(), (120 + 60 * math.sin(x / 17) * math.cos(y / 23)).round(), 255);
        }
      }
      final canvas = img.Image(width: 520, height: 380)..clear(img.ColorRgb8(200, 190, 178));
      final n = angle == 0 ? note : img.copyRotate(note, angle: angle);
      img.compositeImage(canvas, n, dstX: (520 - n.width) ~/ 2, dstY: (380 - n.height) ~/ 2);
      if (tornFrac > 0) {
        // Jagged tear removing the right end of the note.
        final x0 = (520 - nw) ~/ 2, cut = x0 + nw * (1 - tornFrac);
        for (var y = 0; y < 380; y++) {
          final jag = cut + 6 * math.sin(y / 5);
          for (var x = jag.round(); x < 520; x++) {
            canvas.setPixelRgb(x, y, 200, 190, 178);
          }
        }
      }
      return canvas;
    }

    test('intact note is good and gives a landscape crop', () {
      final r = estimateTorn(scene());
      expect(r.found, isTrue);
      expect(r.reliable, isTrue, reason: '${r.flags}');
      expect(r.tornRatio!, lessThanOrEqualTo(5));
      expect(r.crop!.width, greaterThan(r.crop!.height));
    });

    test('rotated note still measured as intact', () {
      final r = estimateTorn(scene(angle: 20));
      expect(r.found, isTrue);
      expect(r.tornRatio!, lessThanOrEqualTo(6));
    });

    test('40% torn note is estimated within tolerance', () {
      final r = estimateTorn(scene(tornFrac: 0.4), expectedAspect: 300 / 140);
      expect(r.found, isTrue);
      expect(r.tornRatio!, closeTo(40, 7));
    });

    test('empty table → no note', () {
      final r = estimateTorn(img.Image(width: 400, height: 300)..clear(img.ColorRgb8(200, 190, 178)));
      expect(r.found, isFalse);
    });
  });
}

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../providers/providers.dart';
import '../services/recognition/recognition_engine.dart';
import '../services/vision/frame_analyzer.dart';
import '../services/voice/command_parser.dart';
import '../widgets/common.dart';
import '../widgets/glass_panel.dart';
import '../widgets/painters.dart';
import '../widgets/ui_kit.dart';
import '../widgets/waveform.dart';
import 'voice_screen.dart';

/// Shared across scanner visits so a note that was just captured must leave
/// the frame before another automatic capture (prevents double counting).
final captureGateProvider = Provider<CaptureGate>((_) => CaptureGate());

/// Screen 2 — Live banknote scanning (PDF page 2).
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});
  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> with VoiceScreen, WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _cam;
  final _analyzer = FrameAnalyzer();
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  final _guidance = ValueNotifier<String>('place_note');
  final _ready = ValueNotifier<bool>(false);
  final _stability = ValueNotifier<double>(0);
  final _noteScreen = ValueNotifier<Rect?>(null);
  bool _busy = false;
  bool _torch = false;
  bool _streaming = false;
  String? _cameraError;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSpoken = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastSpokenKey = '';
  Rect _guideScreen = Rect.zero;
  Size _screen = Size.zero;

  CaptureGate get _gate => ref.read(captureGateProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    WidgetsBinding.instance.addPostFrameCallback((_) => sayThenListen(s.scannerIntro));
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final ctrl = CameraController(back, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await ctrl.initialize();
      await ctrl.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await ctrl.setFocusMode(FocusMode.auto);
      await ctrl.setExposureMode(ExposureMode.auto);
      await ctrl.setFlashMode(FlashMode.off);
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() => _cam = ctrl);
      _torch = false;
      await _startStream();
    } catch (e) {
      if (!mounted) return;
      setState(() => _cameraError = e.toString());
      await say(s.cameraPermissionDenied);
    }
  }

  Future<void> _startStream() async {
    final c = _cam;
    if (c == null || _streaming || !c.value.isInitialized) return;
    _streaming = true;
    _analyzer.reset();
    await c.startImageStream(_onFrame);
  }

  Future<void> _stopStream() async {
    final c = _cam;
    if (c == null || !_streaming) return;
    _streaming = false;
    try {
      await c.stopImageStream();
    } catch (_) {}
  }

  /// Cover-fit transform between upright camera image and screen.
  (double, double, double, double, double) _fit() {
    final ps = _cam!.value.previewSize!;
    final iw = math.min(ps.width, ps.height), ih = math.max(ps.width, ps.height); // upright portrait
    final k = math.max(_screen.width / iw, _screen.height / ih);
    return (iw, ih, k, (_screen.width - iw * k) / 2, (_screen.height - ih * k) / 2);
  }

  /// Maps the on-screen bracket rectangle into normalised image coordinates.
  NRect _guideInImage() {
    final (iw, ih, k, ox, oy) = _fit();
    double nx(double x) => ((x - ox) / (iw * k)).clamp(0.0, 1.0);
    double ny(double y) => ((y - oy) / (ih * k)).clamp(0.0, 1.0);
    return NRect(nx(_guideScreen.left), ny(_guideScreen.top), nx(_guideScreen.right), ny(_guideScreen.bottom));
  }

  /// Normalised image rectangle → screen rectangle (for the note outline).
  Rect _imageToScreen(NRect r) {
    final (iw, ih, k, ox, oy) = _fit();
    return Rect.fromLTRB(ox + r.left * iw * k, oy + r.top * ih * k, ox + r.right * iw * k, oy + r.bottom * ih * k);
  }

  void _onFrame(CameraImage image) {
    final now = DateTime.now();
    if (_busy || now.difference(_lastFrame) < const Duration(milliseconds: 160) || _guideScreen == Rect.zero) return;
    _lastFrame = now;
    final plane = image.planes.first;
    final frame = LumaFrame(
      bytes: plane.bytes,
      width: image.width,
      height: image.height,
      rowStride: plane.bytesPerRow,
      rotation: _cam!.description.sensorOrientation,
    );
    final a = _analyzer.analyze(frame, guide: _guideInImage());
    final autoCapture = ref.read(settingsProvider).autoCapture;
    var key = a.guidance;
    if (!_gate.armed && a.notePresent) key = 'remove_note';
    final shouldCapture = _gate.onFrame(a) && autoCapture;
    _guidance.value = key;
    _ready.value = a.ready && _gate.armed;
    // The ring only fills once the note is positioned (waiting to be steady / capturing).
    final positioned = a.guidance == 'hold_steady' || a.guidance == 'capturing';
    _stability.value = _gate.armed && positioned ? (a.ready ? 1.0 : a.stability) : 0;
    _noteScreen.value = a.noteRect == null || !a.notePresent ? null : _imageToScreen(a.noteRect!);
    _maybeSpeakGuidance(key);
    if (shouldCapture) _capture();
  }

  void _maybeSpeakGuidance(String key) {
    final now = DateTime.now();
    final changed = key != _lastSpokenKey;
    final gap = now.difference(_lastSpoken);
    if (voice.speaking.value) return;
    if ((changed && gap > const Duration(milliseconds: 1800)) || gap > const Duration(seconds: 6)) {
      _lastSpoken = now;
      _lastSpokenKey = key;
      say(s.guidance(key));
    }
  }

  Future<void> _capture({bool manual = false}) async {
    final c = _cam;
    if (_busy || c == null || !c.value.isInitialized) return;
    _busy = true;
    haptic(HapticKind.capture);
    try {
      await _stopStream();
      await voice.stopAll();
      final shot = await c.takePicture();
      _gate.markCaptured();
      final store = ref.read(tempImagesProvider);
      final captureId = DateTime.now().microsecondsSinceEpoch.toString();
      final file = store != null ? await store.adopt(shot.path, captureId) : null;
      await ref.read(scanFlowProvider.notifier).setCapture(file ?? File(shot.path));
      if (_torch) await c.setFlashMode(FlashMode.off);
      if (mounted) context.go('/analyze');
    } catch (e) {
      _busy = false;
      await say(s.errorMessage('unknown'));
      await _startStream();
    }
  }

  Future<void> _toggleTorch() async {
    final c = _cam;
    if (c == null) return;
    _torch = !_torch;
    try {
      await c.setFlashMode(_torch ? FlashMode.torch : FlashMode.off);
    } catch (_) {
      _torch = false;
    }
    haptic(HapticKind.tap);
    setState(() {});
  }

  void _finish() {
    haptic(HapticKind.tap);
    context.go('/payment');
  }

  void _manualCapture() {
    _gate.rearm();
    _capture(manual: true);
  }

  @override
  void onVoice(String words) {
    switch (parseCommand(words)) {
      case VoiceCommand.finish || VoiceCommand.stop:
        _finish();
      case VoiceCommand.total:
        say(s.totalSpeech(ref.read(sessionProvider).total));
      case VoiceCommand.scan || VoiceCommand.confirm:
        _manualCapture();
      case VoiceCommand.undo:
        final removed = ref.read(sessionProvider.notifier).undo();
        say(s.undoSpeech(removed, ref.read(sessionProvider).total));
      case VoiceCommand.exit:
        context.go('/');
      default:
        break;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _cam;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      voice.setPaused(true);
      _streaming = false;
      _cam = null;
      c?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      voice.setPaused(false);
      if (c == null && mounted) _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final c = _cam;
    _cam = null;
    if (_streaming) {
      c?.stopImageStream().catchError((_) {}).whenComplete(() => c.dispose());
    } else {
      c?.dispose();
    }
    _pulse.dispose();
    _guidance.dispose();
    _ready.dispose();
    _stability.dispose();
    _noteScreen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final str = ref.watch(stringsProvider);
    final isDemo = ref.watch(settingsProvider.select((x) => x.mode == EngineMode.demo));
    final session = ref.watch(sessionProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(builder: (context, box) {
        _screen = box.biggest;
        final w = box.maxWidth, h = box.maxHeight;
        _guideScreen = Rect.fromLTWH(w * 0.1, h * 0.28, w * 0.8, math.min(h * 0.32, w * 0.8 * 0.9));
        final cam = _cam;
        return Stack(fit: StackFit.expand, children: [
          // Full-screen live preview (cover fit).
          if (cam != null && cam.value.isInitialized)
            Semantics(
              label: 'Camera view',
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: math.min(cam.value.previewSize!.width, cam.value.previewSize!.height),
                    height: math.max(cam.value.previewSize!.width, cam.value.previewSize!.height),
                    child: CameraPreview(cam),
                  ),
                ),
              ),
            )
          else
            Center(
                child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_cameraError == null ? '...' : str.cameraPermissionDenied, textAlign: TextAlign.center, style: t.bodyLarge),
            )),
          // Dim everything outside the scan frame so the target area stands out.
          IgnorePointer(child: ExcludeSemantics(child: CustomPaint(painter: _ScrimPainter(_guideScreen)))),
          // Outline of the note the analyser currently sees.
          ValueListenableBuilder<Rect?>(
            valueListenable: _noteScreen,
            builder: (_, r, _) => r == null
                ? const SizedBox.shrink()
                : IgnorePointer(child: ExcludeSemantics(child: CustomPaint(painter: _NoteOutlinePainter(r, _ready.value)))),
          ),
          // Yellow animated brackets (green when ready).
          ValueListenableBuilder<bool>(
            valueListenable: _ready,
            builder: (_, ready, _) => IgnorePointer(
              child: ExcludeSemantics(child: CustomPaint(painter: ScanBracketsPainter(rect: _guideScreen, pulse: _pulse, locked: ready))),
            ),
          ),
          SafeArea(
            child: Column(children: [
              if (isDemo) DemoBanner(text: str.demoBanner),
              const SizedBox(height: 10),
              // Running total, always visible while scanning.
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: TotalChip(total: session.total, count: session.accepted.length, label: str.totalLabel, notesLabel: str.notesLabel, shortNotesLabel: str.notesShort),
                ),
              ),
              const SizedBox(height: 10),
              // Voice guidance pill (live region).
              Padding(
                padding: EdgeInsets.symmetric(horizontal: w * 0.08),
                child: ValueListenableBuilder<String>(
                  valueListenable: _guidance,
                  builder: (_, key, _) => Semantics(
                    liveRegion: true,
                    label: str.guidance(key),
                    excludeSemantics: true,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Container(
                        key: ValueKey(key),
                        constraints: const BoxConstraints(minHeight: 72),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xA6071529),
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(color: const Color(0xFFB7C9D3), width: 4),
                        ),
                        child: Row(children: [
                          const Icon(Icons.volume_up_rounded, size: 42, color: AppColors.white),
                          const SizedBox(width: 12),
                          Expanded(child: Text(str.guidance(key), style: t.bodyLarge!.copyWith(fontWeight: FontWeight.w700))),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              // Compact glass status panel.
              Padding(
                padding: EdgeInsets.symmetric(horizontal: w * 0.08),
                child: ValueListenableBuilder<bool>(
                  valueListenable: _ready,
                  builder: (_, ready, _) => GlassPanel(
                    radius: 40,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Column(children: [
                      Waveform(level: voice.soundLevel, width: w * 0.5, height: 44),
                      Semantics(
                        liveRegion: true,
                        child: Text(ready ? str.capturing : str.searching, style: t.headlineMedium!.copyWith(fontSize: w * 0.07)),
                      ),
                      Text(str.holdSteady, style: t.bodyMedium),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Camera-style controls: torch · capture (steadiness ring) · finish.
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, crossAxisAlignment: CrossAxisAlignment.end, children: [
                RoundAction(
                  icon: _torch ? Icons.flashlight_off_rounded : Icons.flashlight_on_rounded,
                  label: str.torch,
                  semanticLabel: _torch ? str.flashOff : str.flashOn,
                  onPressed: _toggleTorch,
                  color: _torch ? AppColors.scanYellow : AppColors.glassBorder,
                ),
                RoundAction(
                  icon: Icons.camera_alt_rounded,
                  label: str.capture,
                  semanticLabel: str.captureNow,
                  size: 84,
                  filled: true,
                  color: AppColors.scanYellow,
                  progress: _stability,
                  onPressed: _manualCapture,
                ),
                RoundAction(
                  icon: Icons.check_rounded,
                  label: str.finish,
                  semanticLabel: str.finish,
                  onPressed: _finish,
                  color: AppColors.successGreen,
                ),
              ]),
              const SizedBox(height: 12),
            ]),
          ),
        ]);
      }),
    );
  }
}

/// Darkens the preview outside the scan frame.
class _ScrimPainter extends CustomPainter {
  _ScrimPainter(this.hole);
  final Rect hole;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(36)));
    canvas.drawPath(path, Paint()..color = const Color(0x66000000));
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.hole != hole;
}

/// Thin outline around the detected note (cyan; green when ready).
class _NoteOutlinePainter extends CustomPainter {
  _NoteOutlinePainter(this.rect, this.ready);
  final Rect rect;
  final bool ready;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = (ready ? AppColors.successGreen : AppColors.cyan).withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_NoteOutlinePainter old) => old.rect != rect || old.ready != ready;
}

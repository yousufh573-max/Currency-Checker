import 'dart:io';

import 'package:banknote_assistant/app.dart';
import 'package:banknote_assistant/providers/providers.dart';
import 'package:banknote_assistant/services/recognition/recognition_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:banknote_assistant/models/analysis_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fakes.dart';

/// Animations (waveform, pulses) repeat forever, so pump fixed durations.
Future<void> settle(WidgetTester t, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

const title = 'Banknote\nAssistant';
const _permChannel =MethodChannel('flutter.baseflow.com/permissions/methods');

/// Mocks the Android permission dialog: camera=1, microphone=7; 1=granted, 0=denied.
void mockPermissions({required bool camera, required bool mic}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_permChannel, (call) async {
    final status = {1: camera ? 1 : 0, 7: mic ? 1 : 0};
    if (call.method == 'requestPermissions') {
      return {for (final p in (call.arguments as List).cast<int>()) p: status[p] ?? 0};
    }
    if (call.method == 'checkPermissionStatus') return status[call.arguments as int] ?? 0;
    return null;
  });
}

void main() {
  late FakeVoice voice;
  late FakeEngine engine;
  late ProviderContainer container;

  Future<void> boot(WidgetTester t, String location) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.75;
    addTearDown(t.view.reset);
    voice = FakeVoice();
    engine = FakeEngine();
    container = ProviderContainer(overrides: [
      voiceProvider.overrideWithValue(voice),
      engineProvider.overrideWithValue(engine),
    ]);
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(container: container, child: BanknoteAssistantApp(initialLocation: location)));
    await settle(t, 3);
  }

  /// Simulates one capture, then runs the real analysis + result screens.
  Future<void> scanNote(WidgetTester t, AnalysisResult r) async {
    engine.queue.add(r);
    await container.read(scanFlowProvider.notifier).setCapture(File('missing_test_capture.jpg'));
    _go(t, '/analyze');
    await settle(t);
  }

  testWidgets('Acceptance: 20 + 100 + torn 500 → total 120; pay 70 → remaining 50; summary shown and spoken', (t) async {
    await boot(t, '/payment');

    // 1. Accepted 20 Taka.
    await scanNote(t, note(20, conf: 0.986, torn: 2));
    expect(find.text('20 Taka'), findsOneWidget);
    expect(find.text('Confidence: 98.6%'), findsOneWidget);
    expect(find.text('Condition: Good'), findsOneWidget);
    expect(find.text('Added to total'), findsOneWidget);
    expect(voice.spoken.any((s) => s.startsWith('20 Taka detected. Torn ratio is 2 percent. Added to your total. Current total: 20 Taka.')), isTrue);

    // 2. Accepted 100 Taka.
    await scanNote(t, note(100));
    expect(container.read(sessionProvider).total, 120);

    // 3. Heavily damaged 500 Taka → excluded; display and speech agree.
    await scanNote(t, note(500, conf: 0.916, torn: 40));
    expect(find.text('500 Taka'), findsOneWidget);
    expect(find.text('Condition: Too torn'), findsOneWidget);
    expect(find.text('(Torn ratio: 40%)'), findsOneWidget);
    expect(find.text('Not added to total'), findsOneWidget);
    expect(find.text('Added to total'), findsNothing);
    final speech = voice.spoken.lastWhere((s) => s.contains('500 Taka detected'));
    expect(speech, contains('Not added to your total'));
    expect(speech, contains('Current total: 120 Taka'));

    // 4. Total is 120.
    expect(container.read(sessionProvider).total, 120);
    expect(find.text('৳120'), findsOneWidget);

    // 5. Say "Finish" → payment screen; say "Seventy Taka".
    voice.hear('finish');
    await settle(t);
    expect(find.text('Total Scanned Amount'), findsOneWidget);
    expect(find.text('Required Payment Amount'), findsOneWidget, reason: 'PDF duplicate label corrected');
    voice.hear('Seventy Taka');
    await settle(t);

    // 6. Remaining 50.
    expect(container.read(sessionProvider).payment!.remaining, 50);
    expect(find.text('You have enough. Remaining 50 Taka.'), findsOneWidget);
    expect(voice.last, contains('You have enough. Remaining 50 Taka.'));

    // 7. Summary displayed and announced.
    voice.hear('finish');
    await settle(t);
    expect(find.text('Total scanned : 120 Taka'), findsOneWidget);
    expect(find.text('Needed amount : 70 Taka'), findsOneWidget);
    expect(find.text('Remaining : 50 Taka'), findsOneWidget);
    expect(find.text('Not counted : 1 note(s)'), findsOneWidget);
    expect(find.text('Cash calculation only. No payment was made or verified.'), findsOneWidget);
    expect(voice.last, startsWith('Calculation complete. You scanned 120 Taka. Needed 70 Taka. Remaining 50 Taka.'));
    expect(container.read(sessionProvider).completed, isTrue);

    // "Repeat Summary" repeats it.
    final before = voice.spoken.length;
    voice.hear('repeat summary');
    await settle(t, 2);
    expect(voice.spoken.length, before + 1);
    expect(voice.last, startsWith('Calculation complete.'));
  });

  testWidgets('Undo by voice on result screen updates total, banner and status', (t) async {
    await boot(t, '/payment');
    engine.queue.add(note(50));
    await container.read(scanFlowProvider.notifier).setCapture(File('x.jpg'));
    _go(t, '/analyze');
    await settle(t);
    expect(find.text('Added to total'), findsOneWidget);
    voice.hear('undo');
    await settle(t, 4);
    expect(container.read(sessionProvider).total, 0);
    expect(find.text('Not added to total'), findsOneWidget);
    expect(voice.last, contains('Removed the last 50 Taka note. Current total: 0 Taka.'));
  });

  testWidgets('Low-confidence note is not counted and asks to rescan', (t) async {
    await boot(t, '/payment');
    engine.queue.add(note(1000, conf: 0.42));
    await container.read(scanFlowProvider.notifier).setCapture(File('x.jpg'));
    _go(t, '/analyze');
    await settle(t);
    expect(find.text('Not added to total'), findsOneWidget);
    expect(find.text('Rescan'), findsOneWidget);
    expect(voice.spoken.last, contains('I am not sure which note this is. Please rescan.'));
    expect(container.read(sessionProvider).total, 0);
  });

  testWidgets('Engine timeout shows retry/rescan and speaks the error; retry succeeds', (t) async {
    await boot(t, '/payment');
    engine.throwNext = const EngineException('timeout');
    await container.read(scanFlowProvider.notifier).setCapture(File('x.jpg'));
    _go(t, '/analyze');
    await settle(t);
    expect(find.text('Retry'), findsOneWidget);
    expect(voice.spoken.last, contains('took too long'));
    expect(container.read(sessionProvider).scans, isEmpty);
    engine.queue.add(note(10));
    await t.ensureVisible(find.text('Retry'));
    await t.pump();
    await t.tap(find.text('Retry'));
    await settle(t);
    expect(find.text('10 Taka'), findsOneWidget);
    expect(container.read(sessionProvider).total, 10);
  });

  testWidgets('Model-not-installed is reported honestly, nothing counted', (t) async {
    await boot(t, '/payment');
    engine.queue.add(const AnalysisResult(success: false, error: 'model_not_installed', rejectionReason: 'model_not_installed'));
    await container.read(scanFlowProvider.notifier).setCapture(File('x.jpg'));
    _go(t, '/analyze');
    await settle(t);
    expect(find.text('Not recognized'), findsOneWidget);
    expect(voice.spoken.last, contains('recognition model is not installed'));
    expect(container.read(sessionProvider).total, 0);
  });

  testWidgets('Permissions: camera denied → spoken explanation, stays on welcome', (t) async {
    mockPermissions(camera: false, mic: true);
    addTearDown(() => mockPermissions(camera: true, mic: true));
    await boot(t, '/');
    expect(find.text(title), findsOneWidget);
    expect(find.text('Say “Start” to begin'), findsOneWidget);
    expect(voice.spoken.first, startsWith('Welcome to Banknote Assistant'));
    expect(voice.isListening, isTrue, reason: 'listens for "Start" after the welcome');
    voice.hear('start');
    await settle(t, 4);
    expect(voice.last, contains('Camera permission is required'));
    expect(find.text(title), findsOneWidget);
  });

  testWidgets('Permissions: microphone denied → manual alternative announced', (t) async {
    mockPermissions(camera: true, mic: false);
    addTearDown(() => mockPermissions(camera: true, mic: true));
    await boot(t, '/');
    expect(voice.spoken.first, contains('Microphone permission is off'));
    expect(voice.isListening, isFalse, reason: 'no microphone use without permission');
  });

  testWidgets('Permissions: granted + tap on "Say Start" pill navigates to scanner', (t) async {
    mockPermissions(camera: true, mic: true);
    await boot(t, '/');
    await t.ensureVisible(find.text('Say “Start” to begin'));
    await t.pump();
    await t.tap(find.text('Say “Start” to begin'));
    await settle(t, 6);
    expect(find.text(title), findsNothing);
    expect(find.text('Capture'), findsOneWidget);
    expect(find.bySemanticsLabel('Capture now'), findsOneWidget);
  });

  testWidgets('Payment: shortage announced and manual entry fallback works', (t) async {
    await boot(t, '/payment');
    container.read(sessionProvider.notifier).recordResult('a', note(20));
    await settle(t, 2);
    await t.tap(find.text('Required Payment Amount'));
    await settle(t, 4);
    await t.enterText(find.byType(TextField), '70');
    await t.tap(find.text('OK'));
    await settle(t, 4);
    expect(find.text('Not enough. You need 50 Taka more.'), findsOneWidget);
    expect(voice.last, contains('Say Scan More to add notes'));
  });

  group('Accessibility guidelines', () {
    for (final route in ['/', '/payment', '/summary']) {
      testWidgets('tap targets, labels and contrast on $route', (t) async {
        final handle = t.ensureSemantics();
        mockPermissions(camera: true, mic: true);
        await boot(t, route);
        if (route == '/summary') {
          container.read(sessionProvider.notifier)
            ..recordResult('a', note(20))
            ..setRequired(10);
        }
        await settle(t, 4);
        await expectLater(t, meetsGuideline(androidTapTargetGuideline));
        await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(t, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }

    testWidgets('result screen conveys status by text + icon, not colour alone', (t) async {
      final handle = t.ensureSemantics();
      await boot(t, '/payment');
      engine.queue.add(note(500, torn: 40));
      await container.read(scanFlowProvider.notifier).setCapture(File('x.jpg'));
      _go(t, '/analyze');
      await settle(t);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.byIcon(Icons.block), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Current Total: 0 Taka')), findsOneWidget);
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  });
}

void _go(WidgetTester t, String path) {
  GoRouter.of(t.element(find.byType(Scaffold).first)).go(path);
}

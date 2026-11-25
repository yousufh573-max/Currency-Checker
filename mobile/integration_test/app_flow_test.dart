// On-device integration test: real Android plugins (sqflite, path_provider,
// TTS/STT are replaced by a fake voice so the test is deterministic; the
// recognition engine is the labelled DEMO engine because no trained model is
// bundled). Run on a device/emulator:
//   flutter test integration_test/app_flow_test.dart
import 'dart:io';

import 'package:banknote_assistant/app.dart';
import 'package:banknote_assistant/providers/providers.dart';
import 'package:banknote_assistant/services/recognition/demo_engine.dart';
import 'package:banknote_assistant/services/storage/session_repository.dart';
import 'package:banknote_assistant/services/storage/temp_images.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../test/helpers/fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('demo flow on device: 20 + 100 + torn 500, pay 70, summary persisted', (t) async {
    final voice = FakeVoice();
    final repo = await SessionRepository.open(path: 'integration_test_${DateTime.now().millisecondsSinceEpoch}.db');
    final temp = await TempImageStore.create();
    final container = ProviderContainer(overrides: [
      voiceProvider.overrideWithValue(voice),
      engineProvider.overrideWithValue(DemoRecognitionEngine(stageDelay: const Duration(milliseconds: 50))),
      sessionRepoProvider.overrideWithValue(repo),
      tempImagesProvider.overrideWithValue(temp),
    ]);
    await t.pumpWidget(UncontrolledProviderScope(container: container, child: const BanknoteAssistantApp(initialLocation: '/payment')));
    await t.pump(const Duration(seconds: 1));

    Future<void> frames([int n = 20]) async {
      for (var i = 0; i < n; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> scan() async {
      final f = File('${temp.dir.path}/fake.jpg')..writeAsBytesSync([0xff, 0xd8, 0xff]);
      await container.read(scanFlowProvider.notifier).setCapture(f);
      GoRouter.of(t.element(find.byType(Scaffold).first)).go('/analyze');
      await frames(30);
    }

    await scan();
    await scan();
    await scan();
    expect(find.text('DEMO MODE — not real recognition'), findsWidgets);
    expect(container.read(sessionProvider).total, 120);

    voice.hear('finish');
    await frames();
    expect(find.text('Required Payment Amount'), findsOneWidget);
    voice.hear('seventy taka');
    await frames();
    expect(find.text('You have enough. Remaining 50 Taka.'), findsOneWidget);
    voice.hear('finish');
    await frames();
    expect(find.text('Remaining : 50 Taka'), findsOneWidget);
    expect((await repo.history()).first.payment!.remaining, 50);
    container.dispose();
  });
}

import 'package:banknote_assistant/core/app_config.dart';
import 'package:banknote_assistant/models/analysis_result.dart';
import 'package:banknote_assistant/models/session.dart';
import 'package:banknote_assistant/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AnalysisResult res(int? d, {double conf = 0.98, double torn = 2, bool reliable = true}) {
  const t = Thresholds();
  final cond = classifyCondition(torn, reliable, t);
  final (ok, reason) = decideEligibility(denomination: d, confidence: conf, condition: cond, qualityOk: true, flags: const [], t: t);
  return AnalysisResult(success: true, denomination: d, confidence: conf, tornRatio: torn, tornRatioReliable: reliable, condition: cond, eligible: ok, rejectionReason: reason);
}

void main() {
  group('condition thresholds (provisional)', () {
    const t = Thresholds();
    test('0–5% good, >5–20% damaged, >20% too torn, unreliable uncertain', () {
      expect(classifyCondition(0, true, t), NoteCondition.good);
      expect(classifyCondition(5, true, t), NoteCondition.good);
      expect(classifyCondition(5.1, true, t), NoteCondition.damaged);
      expect(classifyCondition(20, true, t), NoteCondition.damaged);
      expect(classifyCondition(20.1, true, t), NoteCondition.tooTorn);
      expect(classifyCondition(2, false, t), NoteCondition.uncertain);
      expect(classifyCondition(null, true, t), NoteCondition.uncertain);
    });
  });

  group('eligibility', () {
    test('low confidence is not counted', () => expect(res(100, conf: 0.6).eligible, isFalse));
    test('too torn is not counted', () => expect(res(500, torn: 40).rejectionReason, 'too_torn'));
    test('uncertain geometry is not counted', () => expect(res(50, reliable: false).rejectionReason, 'condition_uncertain'));
    test('unrecognised object is not counted', () => expect(res(null).rejectionReason, 'not_recognized'));
    test('multiple notes are not counted', () {
      final (ok, reason) = decideEligibility(
          denomination: 20, confidence: 0.99, condition: NoteCondition.good, qualityOk: true, flags: const ['multiple_notes'], t: const Thresholds());
      expect(ok, isFalse);
      expect(reason, 'multiple_notes');
    });
  });

  group('SessionController', () {
    late ProviderContainer c;
    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());
    SessionController ctrl() => c.read(sessionProvider.notifier);
    SessionState state() => c.read(sessionProvider);

    test('acceptance scenario: 20 + 100 + torn 500 → 120; pay 70 → 50 remaining', () {
      expect(ctrl().recordResult('cap-1', res(20)), isTrue);
      expect(ctrl().recordResult('cap-2', res(100)), isTrue);
      expect(ctrl().recordResult('cap-3', res(500, conf: 0.916, torn: 40)), isFalse);
      expect(state().total, 120);
      expect(state().rejected.single.denomination, 500);
      expect(state().denominationCounts, {20: 1, 100: 1});
      ctrl().setRequired(70);
      final p = state().payment!;
      expect(p.sufficient, isTrue);
      expect(p.remaining, 50);
      expect(p.shortage, 0);
    });

    test('same capture twice (camera repeat / retry) is counted once', () {
      ctrl().recordResult('cap-1', res(20));
      ctrl().recordResult('cap-1', res(20));
      expect(state().total, 20);
      expect(state().scans.length, 1);
    });

    test('two different notes of the same denomination are both counted', () {
      ctrl().recordResult('cap-1', res(20));
      ctrl().recordResult('cap-2', res(20));
      expect(state().total, 40);
      expect(state().denominationCounts[20], 2);
    });

    test('undo removes the last scan; undo on empty is a no-op', () {
      ctrl().recordResult('a', res(20));
      ctrl().recordResult('b', res(100));
      expect(ctrl().undo()!.denomination, 100);
      expect(state().total, 20);
      expect(ctrl().undo()!.denomination, 20);
      expect(ctrl().undo(), isNull);
      expect(state().total, 0);
    });

    test('shortage', () {
      ctrl().recordResult('a', res(20));
      ctrl().setRequired(70);
      expect(state().payment!.shortage, 50);
      expect(state().payment!.sufficient, isFalse);
    });

    test('completed session is frozen; newSession resets', () {
      ctrl().recordResult('a', res(20));
      ctrl().complete();
      ctrl().recordResult('b', res(100));
      expect(state().total, 20);
      final oldId = state().id;
      ctrl().newSession();
      expect(state().id, isNot(oldId));
      expect(state().total, 0);
    });
  });
}

import 'package:banknote_assistant/models/analysis_result.dart';
import 'package:banknote_assistant/models/session.dart';
import 'package:banknote_assistant/services/storage/session_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ScanRecord rec(String id, int d, {bool accepted = true}) => ScanRecord(
    captureId: id,
    denomination: d,
    confidence: 0.97,
    tornRatio: accepted ? 1 : 40,
    condition: accepted ? NoteCondition.good : NoteCondition.tooTorn,
    accepted: accepted,
    reason: accepted ? null : 'too_torn',
    isDemo: false,
    createdAt: DateTime(2026, 11, 25));

void main() {
  sqfliteFfiInit();

  test('offline session storage: save, reload active, complete, history, delete', () async {
    final repo = await SessionRepository.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    var s = const SessionState(id: 's1').addScan(rec('a', 20)).addScan(rec('b', 100)).addScan(rec('c', 500, accepted: false));
    await repo.save(s);

    final loaded = (await repo.loadActive())!;
    expect(loaded.total, 120);
    expect(loaded.rejected.single.condition, NoteCondition.tooTorn);

    // Undo is persisted (scans are rewritten).
    await repo.save(s.undoLast());
    expect((await repo.loadActive())!.scans.length, 2);

    s = s.withRequired(70).complete();
    await repo.save(s);
    expect(await repo.loadActive(), isNull);
    final hist = await repo.history();
    expect(hist.single.payment!.remaining, 50);

    await repo.delete('s1');
    expect(await repo.history(), isEmpty);
    await repo.close();
  });
}

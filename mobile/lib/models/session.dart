import 'analysis_result.dart';

/// One analysed capture recorded in a session (accepted or rejected).
class ScanRecord {
  const ScanRecord({
    required this.captureId,
    required this.denomination,
    required this.confidence,
    required this.tornRatio,
    required this.condition,
    required this.accepted,
    required this.reason,
    required this.isDemo,
    required this.createdAt,
  });

  /// Unique per physical capture; doubles as the idempotency key.
  final String captureId;
  final int? denomination;
  final double? confidence;
  final double? tornRatio;
  final NoteCondition condition;
  final bool accepted;
  final String? reason;
  final bool isDemo;
  final DateTime createdAt;
}

class PaymentResult {
  const PaymentResult({required this.total, required this.required, required this.remaining, required this.shortage});
  final int total;
  final int required;
  final int remaining;
  final int shortage;
  bool get sufficient => shortage == 0;
}

PaymentResult computePayment(int total, int required) {
  final diff = total - required;
  return PaymentResult(total: total, required: required, remaining: diff > 0 ? diff : 0, shortage: diff < 0 ? -diff : 0);
}

/// Immutable session state + pure calculation logic.
class SessionState {
  const SessionState({required this.id, this.scans = const [], this.requiredAmount, this.completed = false});

  final String id;
  final List<ScanRecord> scans;
  final int? requiredAmount;
  final bool completed;

  List<ScanRecord> get accepted => scans.where((s) => s.accepted).toList();
  List<ScanRecord> get rejected => scans.where((s) => !s.accepted).toList();
  int get total => accepted.fold(0, (sum, s) => sum + (s.denomination ?? 0));
  bool get hasDemoScans => scans.any((s) => s.isDemo);

  Map<int, int> get denominationCounts {
    final m = <int, int>{};
    for (final s in accepted) {
      m[s.denomination!] = (m[s.denomination!] ?? 0) + 1;
    }
    return m;
  }

  PaymentResult? get payment => requiredAmount == null ? null : computePayment(total, requiredAmount!);

  bool containsCapture(String captureId) => scans.any((s) => s.captureId == captureId);

  /// Idempotent: a capture already in the session is ignored, so camera
  /// frame repeats or retries can never double-count. Different captures of
  /// the same denomination are separate notes and are both kept.
  SessionState addScan(ScanRecord r) {
    if (completed || containsCapture(r.captureId)) return this;
    return copyWith(scans: [...scans, r]);
  }

  SessionState undoLast() => scans.isEmpty || completed ? this : copyWith(scans: scans.sublist(0, scans.length - 1));

  SessionState withRequired(int amount) => copyWith(requiredAmount: amount);

  SessionState complete() => copyWith(completed: true);

  SessionState copyWith({List<ScanRecord>? scans, int? requiredAmount, bool? completed}) => SessionState(
        id: id,
        scans: scans ?? this.scans,
        requiredAmount: requiredAmount ?? this.requiredAmount,
        completed: completed ?? this.completed,
      );
}

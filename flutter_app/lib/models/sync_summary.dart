// Aggregate result of a bulk sync operation.

class SyncSummary {
  final int succeeded;
  final int failed;
  final List<String> errors;

  const SyncSummary({
    this.succeeded = 0,
    this.failed = 0,
    this.errors = const [],
  });

  SyncSummary copyWith({int? succeeded, int? failed, List<String>? errors}) =>
      SyncSummary(
        succeeded: succeeded ?? this.succeeded,
        failed: failed ?? this.failed,
        errors: errors ?? this.errors,
      );
}

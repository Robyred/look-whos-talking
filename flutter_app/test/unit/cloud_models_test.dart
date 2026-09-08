import 'package:flutter_test/flutter_test.dart';
import 'package:look_whos_talking/models/cloud_models.dart';
import 'package:look_whos_talking/models/sync_summary.dart';

void main() {
  group('RemoteFileInfo', () {
    test('exposes the four spec fields as constructed', () {
      final info = RemoteFileInfo(
        remotePath: 'conversations/job_1/result.json',
        filename: 'result.json',
        sizeBytes: 4096,
        modifiedAt: DateTime.parse('2026-09-07T10:00:00Z'),
      );
      expect(info.remotePath, 'conversations/job_1/result.json');
      expect(info.filename, 'result.json');
      expect(info.sizeBytes, 4096);
      expect(info.modifiedAt, DateTime.parse('2026-09-07T10:00:00Z'));
    });

    test('allows zero-size and empty-path edge values without coercion', () {
      final info = RemoteFileInfo(
        remotePath: '',
        filename: '',
        sizeBytes: 0,
        modifiedAt: DateTime(2026),
      );
      expect(info.remotePath, isEmpty);
      expect(info.sizeBytes, 0);
    });
  });

  group('RemoteConversationMeta', () {
    test('exposes the four spec fields as constructed', () {
      final meta = RemoteConversationMeta(
        id: 'job_1',
        filename: 'Team call',
        createdAt: DateTime.parse('2026-09-07T10:00:00Z'),
        hasAudio: true,
      );
      expect(meta.id, 'job_1');
      expect(meta.filename, 'Team call');
      expect(meta.createdAt, DateTime.parse('2026-09-07T10:00:00Z'));
      expect(meta.hasAudio, isTrue);
    });

    test('distinguishes hasAudio false (audio deleted or never present)', () {
      final noAudio =
          RemoteConversationMeta(id: 'j', filename: 'f', createdAt: DateTime(2026), hasAudio: false);
      expect(noAudio.hasAudio, isFalse);
    });
  });

  group('SyncSummary', () {
    test('defaults to zero counts and empty errors (empty case)', () {
      const summary = SyncSummary();
      expect(summary.succeeded, 0);
      expect(summary.failed, 0);
      expect(summary.errors, isEmpty);
    });

    test('carries counts and error descriptions', () {
      const summary =
          SyncSummary(succeeded: 2, failed: 1, errors: ['job_3 failed']);
      expect(summary.succeeded, 2);
      expect(summary.failed, 1);
      expect(summary.errors, ['job_3 failed']);
    });

    test('copyWith replaces only the supplied fields', () {
      const summary =
          SyncSummary(succeeded: 2, failed: 1, errors: ['e1']);
      final updated = summary.copyWith(succeeded: 5);
      expect(updated.succeeded, 5);
      expect(updated.failed, 1);
      expect(updated.errors, ['e1']);
    });
  });
}

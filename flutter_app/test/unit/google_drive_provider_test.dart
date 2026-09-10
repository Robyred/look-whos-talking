import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:look_whos_talking/services/cloud_storage_provider.dart';
import 'package:look_whos_talking/services/google_drive_provider.dart';

class _Node {
  final String id;
  final String name;
  final String? parentId;
  final bool isFolder;
  final DateTime modifiedAt;

  _Node({
    required this.id,
    required this.name,
    required this.parentId,
    required this.isFolder,
    DateTime? modifiedAt,
  }) : modifiedAt = modifiedAt ?? DateTime(2026, 9, 7, 12);

  List<int> bytes = const [];

  int get sizeBytes => bytes.length;
}

/// In-memory Drive that behaves like the real one for the semantics the
/// provider relies on: sibling names are unique, folders nest, files store
/// content, deletes remove entries. Records every call for assertion.
class FakeDriveGateway implements DriveGateway {
  final Map<String, _Node> _nodes = {};
  final List<String> calls = [];
  int _nextId = 1;
  static const rootId = 'root';

  FakeDriveGateway() {
    _nodes[rootId] = _Node(
      id: rootId,
      name: '',
      parentId: null,
      isFolder: true,
    );
  }

  _Node? _findChild(String name, String? parentId, {required bool isFolder}) {
    final effectiveParent = parentId ?? rootId;
    for (final n in _nodes.values) {
      if (n.name == name &&
          n.parentId == effectiveParent &&
          n.isFolder == isFolder) {
        return n;
      }
    }
    return null;
  }

  _Node _new({required String name, String? parentId, required bool isFolder}) {
    final node = _Node(
      id: 'id${_nextId++}',
      name: name,
      parentId: parentId ?? rootId,
      isFolder: isFolder,
    );
    _nodes[node.id] = node;
    return node;
  }

  @override
  Future<String?> findFolder({required String name, String? parentId}) {
    calls.add('findFolder:$name');
    return Future.value(_findChild(name, parentId, isFolder: true)?.id);
  }

  @override
  Future<String> createFolder({required String name, String? parentId}) {
    calls.add('createFolder:$name');
    if (_findChild(name, parentId, isFolder: true) != null) {
      throw StorageException('folder already exists: $name');
    }
    return Future.value(_new(name: name, parentId: parentId, isFolder: true).id);
  }

  @override
  Future<String?> findFile({required String name, required String parentId}) {
    calls.add('findFile:$name');
    return Future.value(_findChild(name, parentId, isFolder: false)?.id);
  }

  @override
  Future<void> uploadNew({
    required String parentId,
    required String name,
    required String localPath,
  }) async {
    calls.add('uploadNew:$name');
    if (_findChild(name, parentId, isFolder: false) != null) {
      throw StorageException('file already exists: $name');
    }
    final node = _new(name: name, parentId: parentId, isFolder: false);
    node.bytes = await File(localPath).readAsBytes();
  }

  @override
  Future<void> overwrite({
    required String fileId,
    required String localPath,
  }) async {
    calls.add('overwrite:$fileId');
    final node = _nodes[fileId];
    if (node == null || node.isFolder) {
      throw StorageException('file not found: $fileId');
    }
    node.bytes = await File(localPath).readAsBytes();
  }

  @override
  Future<void> downloadToFile({
    required String fileId,
    required String localPath,
  }) async {
    calls.add('download:$fileId');
    final node = _nodes[fileId];
    if (node == null || node.isFolder) {
      throw StorageException('file not found: $fileId');
    }
    await File(localPath).writeAsBytes(node.bytes);
  }

  @override
  Future<List<DriveEntry>> listChildren({required String folderId}) {
    calls.add('listChildren:$folderId');
    final children = _nodes.values
        .where((n) => n.parentId == folderId)
        .map(
          (n) => DriveEntry(
            id: n.id,
            name: n.name,
            isFolder: n.isFolder,
            sizeBytes: n.isFolder ? null : n.sizeBytes,
            modifiedAt: n.modifiedAt,
          ),
        )
        .toList();
    return Future.value(children);
  }

  @override
  Future<void> deleteById({required String fileId}) {
    calls.add('delete:$fileId');
    if (!_nodes.containsKey(fileId)) {
      throw StorageException('entry not found: $fileId');
    }
    _nodes.remove(fileId);
    return Future.value();
  }
}

class FakeAuthGateway implements AuthGateway {
  bool authenticated = false;
  int authenticateCount = 0;
  int signOutCount = 0;

  @override
  Future<void> authenticate() async {
    authenticateCount++;
    authenticated = true;
  }

  @override
  Future<bool> isAuthenticated() async => authenticated;

  @override
  Future<void> signOut() async {
    signOutCount++;
    authenticated = false;
  }
}

GoogleDriveProvider _provider(FakeDriveGateway gateway, FakeAuthGateway auth) =>
    GoogleDriveProvider(gateway: gateway, auth: auth);

void main() {
  late FakeDriveGateway gateway;
  late FakeAuthGateway auth;
  late GoogleDriveProvider provider;
  late Directory tempDir;

  setUp(() async {
    gateway = FakeDriveGateway();
    auth = FakeAuthGateway();
    provider = _provider(gateway, auth);
    tempDir = await Directory.systemTemp.createTemp('lwt_drive_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<String> localFile(String name,
      [List<int> bytes = const [1, 2, 3]]) {
    return File('${tempDir.path}/$name').writeAsBytes(bytes).then((f) => f.path);
  }

  group('upload', () {
    test('creates the app folder on first upload', () async {
      final path = await localFile('a.aac');
      await provider.upload(path, 'conversations/job_1/audio.aac');

      final appFolder = gateway._findChild(
        "Look Whos Talking",
        FakeDriveGateway.rootId,
        isFolder: true,
      );
      expect(appFolder, isNotNull, reason: 'app folder should exist at root');
    });

    test('creates intermediate folders conversations/{id}', () async {
      final path = await localFile('a.json');
      await provider.upload(path, 'conversations/job_1/result.json');

      final app = gateway._findChild(
        "Look Whos Talking",
        FakeDriveGateway.rootId,
        isFolder: true,
      )!;
      final conv = gateway._findChild('conversations', app.id, isFolder: true);
      expect(conv, isNotNull);
      final job = gateway._findChild('job_1', conv!.id, isFolder: true);
      expect(job, isNotNull);
      final file =
          gateway._findChild('result.json', job!.id, isFolder: false);
      expect(file, isNotNull);
    });

    test('reuses existing folders instead of duplicating them', () async {
      final path = await localFile('a.json');
      await provider.upload(path, 'conversations/job_1/result.json');
      final before = gateway._nodes.length;
      await provider.upload(path, 'conversations/job_1/result.json');

      expect(gateway._nodes.length, before,
          reason: 'no new nodes when path already exists');
      final createCalls =
          gateway.calls.where((c) => c.startsWith('createFolder')).length;
      expect(createCalls, 3,
          reason: 'app folder, conversations, job_1 — each created only once');
    });

    test('overwrites an existing file instead of creating a duplicate',
        () async {
      final p1 = await localFile('v1.json', [1]);
      await provider.upload(p1, 'conversations/job_1/result.json');
      final p2 = await localFile('v2.json', [9, 9, 9, 9]);
      await provider.upload(p2, 'conversations/job_1/result.json');

      final app = gateway._findChild(
        "Look Whos Talking",
        FakeDriveGateway.rootId,
        isFolder: true,
      )!;
      final conv = gateway._findChild('conversations', app.id, isFolder: true)!;
      final job = gateway._findChild('job_1', conv.id, isFolder: true)!;
      final file =
          gateway._findChild('result.json', job.id, isFolder: false)!;
      expect(file.bytes, [9, 9, 9, 9]);
      // No duplicate file node created.
      final siblings =
          gateway._nodes.values.where((n) => n.parentId == job.id).length;
      expect(siblings, 1);
    });

    test('throws StorageException when remotePath is empty or root-only',
        () async {
      final path = await localFile('a.json');
      await expectLater(
        provider.upload(path, ''),
        throwsA(isA<StorageException>()),
      );
      await expectLater(
        provider.upload(path, '/'),
        throwsA(isA<StorageException>()),
      );
    });

    test('handles leading/trailing slashes and empty segments', () async {
      final path = await localFile('a.json');
      await provider.upload(path, '/conversations//job_1/result.json/');
      final app = gateway._findChild(
        "Look Whos Talking",
        FakeDriveGateway.rootId,
        isFolder: true,
      )!;
      final conv = gateway._findChild('conversations', app.id, isFolder: true);
      expect(conv, isNotNull);
    });
  });

  group('download', () {
    test('downloads an uploaded file to localPath', () async {
      final src = await localFile('a.json', [5, 6, 7]);
      await provider.upload(src, 'conversations/job_1/result.json');

      final dest = '${tempDir.path}/downloaded.json';
      await provider.download('conversations/job_1/result.json', dest);
      expect(await File(dest).readAsBytes(), [5, 6, 7]);
    });

    test('throws StorageException when the remote file is missing', () async {
      await expectLater(
        provider.download('conversations/job_9/result.json', '${tempDir.path}/x'),
        throwsA(isA<StorageException>()),
      );
    });
  });

  group('listFiles', () {
    test('returns empty list when the folder does not exist', () async {
      final result = await provider.listFiles('conversations');
      expect(result, isEmpty);
    });

    test('returns metadata for files with correct remotePath prefix', () async {
      final p1 = await localFile('r1.json', [1, 2]);
      final p2 = await localFile('r2.json', [3]);
      await provider.upload(p1, 'conversations/job_1/result.json');
      await provider.upload(p2, 'conversations/job_2/result.json');

      final conv = await provider.listFiles('conversations');
      expect(conv.length, 2);
      final names = conv.map((f) => f.filename).toSet();
      expect(names, {'job_1', 'job_2'});

      final job1 = await provider.listFiles('conversations/job_1');
      expect(job1.length, 1);
      expect(job1.single.remotePath, 'conversations/job_1/result.json');
      expect(job1.single.sizeBytes, 2);
    });
  });

  group('deleteFile', () {
    test('removes an existing remote file', () async {
      final src = await localFile('a.json', [1]);
      await provider.upload(src, 'conversations/job_1/result.json');
      await provider.deleteFile('conversations/job_1/result.json');

      await expectLater(
        provider.download('conversations/job_1/result.json', '${tempDir.path}/x'),
        throwsA(isA<StorageException>()),
      );
    });

    test('is a no-op for a missing file — no delete call made', () async {
      await provider.deleteFile('conversations/none/result.json');
      expect(gateway.calls.where((c) => c.startsWith('delete:')), isEmpty);
    });

    test('deletes a folder when the path names one (prunes empties)',
        () async {
      final src = await localFile('a.json', [1]);
      await provider.upload(src, 'conversations/job_1/result.json');
      final app = gateway._findChild(
        "Look Whos Talking",
        FakeDriveGateway.rootId,
        isFolder: true,
      )!;
      final conv = gateway._findChild('conversations', app.id, isFolder: true)!;
      expect(gateway._findChild('job_1', conv.id, isFolder: true), isNotNull);

      await provider.deleteFile('conversations/job_1/result.json');
      await provider.deleteFile('conversations/job_1');

      expect(gateway._findChild('job_1', conv.id, isFolder: true), isNull,
          reason: 'empty conversation folder should be pruned');
    });
  });

  group('auth delegation', () {
    test('delegates authenticate/isAuthenticated/signOut to the auth gateway',
        () async {
      expect(await provider.isAuthenticated(), isFalse);
      await provider.authenticate();
      expect(auth.authenticateCount, 1);
      expect(await provider.isAuthenticated(), isTrue);
      await provider.signOut();
      expect(auth.signOutCount, 1);
      expect(await provider.isAuthenticated(), isFalse);
    });
  });

  group('app folder cache invalidation', () {
    test('switches to a new app folder when the account changes', () async {
      final src = await localFile('a.json');
      await provider.upload(src, 'conversations/job_1/result.json');

      // Simulate a different account: the old app folder is gone and a new
      // one exists under the same name.
      final oldApp = gateway._findChild(
        "Look Whos Talking",
        FakeDriveGateway.rootId,
        isFolder: true,
      )!;
      gateway._nodes.remove(oldApp.id);
      gateway._new(
        name: "Look Whos Talking",
        parentId: FakeDriveGateway.rootId,
        isFolder: true,
      );

      await provider.upload(src, 'conversations/job_2/result.json');
      final newApp = gateway._findChild(
        "Look Whos Talking",
        FakeDriveGateway.rootId,
        isFolder: true,
      )!;
      expect(newApp.id, isNot(oldApp.id));
      final newConv =
          gateway._findChild('conversations', newApp.id, isFolder: true);
      expect(newConv, isNotNull,
          reason: 'conversations folder created under the new app folder');
      final job2 = gateway._findChild(
        'job_2',
        newConv!.id,
        isFolder: true,
      );
      expect(job2, isNotNull, reason: 'upload went into the new app folder');
    });
  });

  group('defaults', () {
    test('default app folder name is safe to use in Drive queries', () {
      // Drive `q` queries cannot escape a quote inside a name search, so a
      // folder name containing an apostrophe breaks every lookup (HTTP 400).
      final g = FakeDriveGateway();
      final p = _provider(g, FakeAuthGateway());
      expect(p.appFolderName, isNotEmpty);
      expect(p.appFolderName.contains("'"), isFalse,
          reason: 'apostrophe in the folder name breaks Drive q queries');
    });
  });
}

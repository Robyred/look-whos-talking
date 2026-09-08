import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:look_whos_talking/services/google_drive_gateway_impl.dart';

/// Scripted Drive REST backend: responds per (method, path) to exercise the
/// real googleapis request/response plumbing headlessly.
class ScriptedDrive {
  final List<http.Request> requests = [];
  String listBody = '{"files": []}';
  String createBody = '{"id": "created_id"}';
  String? updateBody;
  http.Response Function(http.Request)? mediaDownload;

  Future<http.Response> _handle(http.Request req) async {
    requests.add(req);
    final path = req.url.path;

    if (req.method == 'GET' && path.endsWith('/files')) {
      return http.Response(listBody, 200,
          headers: {'content-type': 'application/json'});
    }
    if (req.method == 'POST' && path.endsWith('/files')) {
      return http.Response(createBody, 200,
          headers: {'content-type': 'application/json'});
    }
    // Multipart media uploads go to /upload/drive/v3/files.
    if (req.method == 'POST' && path.contains('/upload/drive/v3/files')) {
      return http.Response(createBody, 200,
          headers: {'content-type': 'application/json'});
    }
    if (req.method == 'PATCH' && path.contains('/files/')) {
      return http.Response(updateBody ?? '{"id": "x"}', 200,
          headers: {'content-type': 'application/json'});
    }
    if (req.method == 'DELETE' && path.contains('/files/')) {
      return http.Response('', 204);
    }
    if (req.method == 'GET' && path.contains('/files/') && mediaDownload != null) {
      return mediaDownload!(req);
    }
    return http.Response('{"error":{"code":404}}', 404,
        headers: {'content-type': 'application/json'});
  }

  Future<GoogleDriveGatewayImpl> gateway() async {
    final api = drive.DriveApi(MockClient(_handle));
    return GoogleDriveGatewayImpl(api);
  }
}

void main() {
  late ScriptedDrive scripted;

  setUp(() {
    scripted = ScriptedDrive();
  });

  group('findFolder', () {
    test('returns null when Drive has no matching folder', () async {
      final gw = await scripted.gateway();
      final id = await gw.findFolder(name: 'Anything');
      expect(id, isNull);
    });

    test('queries by name + folder mimeType under root', () async {
      final gw = await scripted.gateway();
      scripted.listBody = jsonEncode({
        'files': [
          {'id': 'app_1', 'name': "Look Who's Talking", 'mimeType': 'application/vnd.google-apps.folder'}
        ]
      });
      final id = await gw.findFolder(name: "Look Who's Talking");
      expect(id, 'app_1');

      final q = scripted.requests.single.url.queryParameters['q']!;
      expect(q, contains("name = 'Look Who's Talking'"));
      expect(q, contains('application/vnd.google-apps.folder'));
      expect(q, contains("'root' in parents"));
      expect(q, contains('trashed = false'));
    });

    test('queries under a specific parent when given one', () async {
      scripted.listBody = jsonEncode({
        'files': [
          {'id': 'c_1', 'name': 'conversations', 'mimeType': 'application/vnd.google-apps.folder'}
        ]
      });
      final gw = await scripted.gateway();
      final id = await gw.findFolder(name: 'conversations', parentId: 'app_1');
      expect(id, 'c_1');
      final q = scripted.requests.single.url.queryParameters['q']!;
      expect(q, contains("'app_1' in parents"));
    });
  });

  group('createFolder', () {
    test('POSTs folder metadata and returns the new id', () async {
      final gw = await scripted.gateway();
      scripted.createBody = jsonEncode({'id': 'folder_9', 'name': 'conversations'});
      final id = await gw.createFolder(name: 'conversations', parentId: 'app_1');

      expect(id, 'folder_9');
      final req = scripted.requests.single;
      expect(req.method, 'POST');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['name'], 'conversations');
      expect(body['mimeType'], 'application/vnd.google-apps.folder');
      expect(body['parents'], ['app_1']);
    });

    test('defaults parent to root', () async {
      final gw = await scripted.gateway();
      scripted.createBody = jsonEncode({'id': 'f1'});
      await gw.createFolder(name: 'App');
      final body = jsonDecode(scripted.requests.single.body) as Map<String, dynamic>;
      expect(body['parents'], ['root']);
    });
  });

  group('listChildren', () {
    test('maps files and folders with size/modified parsing', () async {
      scripted.listBody = jsonEncode({
        'files': [
          {
            'id': 'folder_1',
            'name': 'job_1',
            'mimeType': 'application/vnd.google-apps.folder',
          },
          {
            'id': 'file_1',
            'name': 'result.json',
            'mimeType': 'application/json',
            'size': '4096',
            'modifiedTime': '2026-09-07T10:00:00.000Z',
          },
        ]
      });
      final gw = await scripted.gateway();
      final children = await gw.listChildren(folderId: 'conv_1');

      expect(children.length, 2);
      final folder = children.firstWhere((c) => c.id == 'folder_1');
      expect(folder.isFolder, isTrue);
      expect(folder.sizeBytes, isNull);
      final file = children.firstWhere((c) => c.id == 'file_1');
      expect(file.isFolder, isFalse);
      expect(file.sizeBytes, 4096);
      expect(file.modifiedAt, DateTime.parse('2026-09-07T10:00:00.000Z'));

      final q = scripted.requests.single.url.queryParameters['q']!;
      expect(q, contains("'conv_1' in parents"));
    });
  });

  group('media download', () {
    test('writes downloaded bytes to localPath', () async {
      final dir = await Directory.systemTemp.createTemp('lwt_media_test');
      addTearDown(() => dir.delete(recursive: true));
      scripted.mediaDownload = (req) => http.Response.bytes([1, 2, 3], 200, headers: {'content-type': 'application/octet-stream'});

      final gw = await scripted.gateway();
      final dest = '${dir.path}/out.bin';
      await gw.downloadToFile(fileId: 'file_1', localPath: dest);

      expect(await File(dest).readAsBytes(), [1, 2, 3]);
    });
  });

  group('deleteById', () {
    test('sends DELETE for the file id', () async {
      final gw = await scripted.gateway();
      await gw.deleteById(fileId: 'file_1');
      final req = scripted.requests.single;
      expect(req.method, 'DELETE');
      expect(req.url.path, endsWith('/files/file_1'));
    });
  });
}

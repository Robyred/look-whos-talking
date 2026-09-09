import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:look_whos_talking/services/dropbox_provider.dart';

import '../helpers/provider_fakes.dart';

void main() {
  late Directory tempDir;
  late File audioFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('db_test');
    audioFile = File('${tempDir.path}/clip.aac');
    await audioFile.writeAsBytes([1, 2, 3]);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  // Builds a provider that has already gone through a silent refresh (real
  // code path), so its _accessToken is populated without real OAuth.
  Future<DropboxProvider> authed(MockClient client) async {
    final tokens = InMemoryTokenStore()
      ..values['dropbox_refresh_token'] = 'stored-refresh';
    final broker = FakeTokenBroker();
    final provider = DropboxProvider(
      client: client,
      tokenStore: tokens,
      broker: broker,
    );
    expect(await provider.isAuthenticated(), isTrue);
    return provider;
  }

  group('upload', () {
    test('POSTs to the content endpoint with the right Dropbox-API-Arg',
        () async {
      final calls = <http.Request>[];
      final client = MockClient((req) async {
        calls.add(req);
        return http.Response('{}', 200);
      });
      final provider = await authed(client);

      await provider.upload(audioFile.path, 'conversations/abc/clip.aac');

      expect(calls, hasLength(1));
      final req = calls.single;
      expect(req.method, 'POST');
      expect(req.url.toString(),
          'https://content.dropboxapi.com/2/files/upload');
      expect(req.headers['Authorization'], 'Bearer access-1');
      final arg =
          jsonDecode(req.headers['Dropbox-API-Arg']!) as Map<String, dynamic>;
      expect(arg['path'], '/clip.aac');
      expect(arg['mode'], 'overwrite');
      expect(arg['autorename'], isFalse);
      expect(req.bodyBytes, [1, 2, 3]);
    });

    test('a server error surfaces as a StorageException', () async {
      final client = MockClient(
          (req) async => http.Response('{"error_summary":"bad"}', 409));
      final provider = await authed(client);
      await expectLater(
        provider.upload(audioFile.path, 'x.m4a'),
        throwsA(isA<Object>()),
      );
    });
  });

  group('download', () {
    test('requests the file via the content endpoint and writes bytes',
        () async {
      final client = MockClient((req) async {
        expect(req.url.toString(),
            'https://content.dropboxapi.com/2/files/download');
        expect(jsonDecode(req.headers['Dropbox-API-Arg']!),
            {'path': '/clip.aac'});
        return http.Response.bytes([4, 5, 6], 200);
      });
      final provider = await authed(client);
      await provider.download('dir/clip.aac', '${tempDir.path}/out.aac');
      expect(await File('${tempDir.path}/out.aac').readAsBytes(), [4, 5, 6]);
    });
  });

  group('listFiles', () {
    test('maps file entries, skipping folders', () async {
      final client = MockClient((req) async {
        expect(req.url.toString(),
            'https://api.dropboxapi.com/2/files/list_folder');
        expect(jsonDecode(req.body), {'path': '', 'recursive': false});
        return http.Response(
          jsonEncode({
            'entries': [
              {
                '.tag': 'file',
                'name': 'a.m4a',
                'path_lower': '/a.m4a',
                'size': 42,
                'server_modified': '2026-09-01T10:00:00Z',
              },
              {
                '.tag': 'folder',
                'name': 'sub',
                'path_lower': '/sub',
              },
            ],
          }),
          200,
        );
      });
      final provider = await authed(client);
      final files = await provider.listFiles('');
      expect(files, hasLength(1));
      expect(files.single.filename, 'a.m4a');
      expect(files.single.sizeBytes, 42);
    });
  });

  group('deleteFile', () {
    test('409 (path_not_found) is an idempotent no-op', () async {
      final client =
          MockClient((req) async => http.Response('{"error":{}}', 409));
      final provider = await authed(client);
      await expectLater(provider.deleteFile('x.m4a'), completes);
    });

    test('200 is a success', () async {
      final client = MockClient((req) async => http.Response('', 200));
      final provider = await authed(client);
      await expectLater(provider.deleteFile('x.m4a'), completes);
    });
  });

  group('authentication', () {
    test('authenticate() requests an offline refresh token and stores it',
        () async {
      final tokens = InMemoryTokenStore();
      final broker = FakeTokenBroker();
      final provider = DropboxProvider(
        client: MockClient((req) async => http.Response('', 500)),
        tokenStore: tokens,
        broker: broker,
      );

      await provider.authenticate();

      expect(broker.exchangeCount, 1);
      expect(
          broker.lastAdditionalParameters, {'token_access_type': 'offline'});
      expect(tokens.values['dropbox_refresh_token'], 'r1');
      expect(await provider.isAuthenticated(), isTrue);
    });

    test('isAuthenticated() with no stored token is false and silent',
        () async {
      final broker = FakeTokenBroker();
      final provider = DropboxProvider(
        client: MockClient((req) async => http.Response('', 500)),
        tokenStore: InMemoryTokenStore(),
        broker: broker,
      );
      expect(await provider.isAuthenticated(), isFalse);
      expect(broker.refreshCount, 0);
    });

    test('isAuthenticated() with a stored refresh token refreshes silently',
        () async {
      final tokens = InMemoryTokenStore()
        ..values['dropbox_refresh_token'] = 'stored';
      final broker = FakeTokenBroker();
      final provider = DropboxProvider(
        client: MockClient((req) async => http.Response('', 500)),
        tokenStore: tokens,
        broker: broker,
      );
      expect(await provider.isAuthenticated(), isTrue);
      expect(broker.refreshCount, 1);
      expect(broker.lastRefreshToken, 'stored');
    });

    test('signOut() clears the stored refresh token', () async {
      final tokens = InMemoryTokenStore()
        ..values['dropbox_refresh_token'] = 'r1';
      final broker = FakeTokenBroker();
      final provider = DropboxProvider(
        client: MockClient((req) async => http.Response('', 500)),
        tokenStore: tokens,
        broker: broker,
      );
      expect(await provider.isAuthenticated(), isTrue); // populates token

      await provider.signOut();
      expect(tokens.values, isEmpty);
      expect(await provider.isAuthenticated(), isFalse);
    });
  });
}

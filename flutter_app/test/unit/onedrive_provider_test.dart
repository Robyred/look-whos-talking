import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:look_whos_talking/services/onedrive_provider.dart';

import '../helpers/provider_fakes.dart';

void main() {
  late Directory tempDir;
  late File audioFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('od_test');
    audioFile = File('${tempDir.path}/clip.aac');
    await audioFile.writeAsBytes([1, 2, 3, 4, 5]);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  // Builds a provider that has already gone through a silent refresh (real
  // code path), so its _accessToken is populated without real OAuth.
  Future<OneDriveProvider> authed(MockClient client) async {
    final tokens = InMemoryTokenStore()
      ..values['onedrive_refresh_token'] = 'stored-refresh';
    final broker = FakeTokenBroker();
    final provider = OneDriveProvider(
      client: client,
      tokenStore: tokens,
      broker: broker,
    );
    expect(await provider.isAuthenticated(), isTrue);
    return provider;
  }

  group('upload', () {
    test('creates an upload session then PUTs the bytes', () async {
      final calls = <http.Request>[];
      final client = MockClient((req) async {
        calls.add(req);
        if (req.method == 'POST') {
          return http.Response('{"uploadUrl":"https://upload.example/s1"}', 200);
        }
        if (req.method == 'PUT') return http.Response('', 201);
        return http.Response('nope', 500);
      });
      final provider = await authed(client);

      await provider.upload(audioFile.path, 'conversations/abc/result.json');

      expect(calls, hasLength(2));
      final session = calls[0];
      expect(session.method, 'POST');
      // Graph path-based addressing needs the slash after "approot:".
      expect(session.url.path, contains('special/approot:/'));
      expect(session.url.path, contains('result.json:/createUploadSession'));
      expect(session.headers['Authorization'], 'Bearer access-1');
      final arg = jsonDecode(session.body) as Map;
      expect((arg['item'] as Map)['@microsoft.graph.conflictBehavior'],
          'replace');

      final put = calls[1];
      expect(put.method, 'PUT');
      expect(put.url.toString(), 'https://upload.example/s1');
      expect(put.headers['Content-Length'], '5');
      expect(put.bodyBytes, [1, 2, 3, 4, 5]);
    });

    test('a failed session creation surfaces a StorageException', () async {
      final client =
          MockClient((req) async => http.Response('{"error":1}', 403));
      final provider = await authed(client);
      await expectLater(
        provider.upload(audioFile.path, 'x.m4a'),
        throwsA(isA<Object>()),
      );
    });
  });

  group('download', () {
    test('resolves the download URL then writes the content', () async {
      final client = MockClient((req) async {
        if (req.url.toString().contains('graph.microsoft.com')) {
          return http.Response(
              '{"@microsoft.graph.downloadUrl":"https://dl.example/file"}',
              200);
        }
        return http.Response.bytes([9, 8, 7], 200);
      });
      final provider = await authed(client);
      await provider.download('remote/clip.aac', '${tempDir.path}/out.aac');
      expect(await File('${tempDir.path}/out.aac').readAsBytes(), [9, 8, 7]);
    });
  });

  group('deleteFile', () {
    test('404 is treated as an idempotent no-op', () async {
      final client = MockClient((req) async => http.Response('gone', 404));
      final provider = await authed(client);
      await expectLater(provider.deleteFile('remote/x.m4a'), completes);
    });

    test('204 is a success', () async {
      final client = MockClient((req) async => http.Response('', 204));
      final provider = await authed(client);
      await expectLater(provider.deleteFile('x.m4a'), completes);
    });
  });

  group('authentication', () {
    test('authenticate() exchanges the code and stores the refresh token',
        () async {
      final tokens = InMemoryTokenStore();
      final broker = FakeTokenBroker();
      final provider = OneDriveProvider(
        client: MockClient((req) async => http.Response('', 500)),
        tokenStore: tokens,
        broker: broker,
      );

      await provider.authenticate();

      expect(broker.exchangeCount, 1);
      expect(tokens.values['onedrive_refresh_token'], 'r1');
      expect(await provider.isAuthenticated(), isTrue);
    });

    test('isAuthenticated() with no stored token is false and silent',
        () async {
      final broker = FakeTokenBroker();
      final provider = OneDriveProvider(
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
        ..values['onedrive_refresh_token'] = 'stored';
      final broker = FakeTokenBroker();
      final provider = OneDriveProvider(
        client: MockClient((req) async => http.Response('', 500)),
        tokenStore: tokens,
        broker: broker,
      );
      expect(await provider.isAuthenticated(), isTrue);
      expect(broker.refreshCount, 1);
      expect(broker.lastRefreshToken, 'stored');
    });

    test('a failed silent refresh reports not authenticated', () async {
      final tokens = InMemoryTokenStore()
        ..values['onedrive_refresh_token'] = 'bad';
      final broker = FakeTokenBroker(failRefresh: true);
      final provider = OneDriveProvider(
        client: MockClient((req) async => http.Response('', 500)),
        tokenStore: tokens,
        broker: broker,
      );
      expect(await provider.isAuthenticated(), isFalse);
    });

    test('signOut() clears the access token and stored refresh token',
        () async {
      final tokens = InMemoryTokenStore()
        ..values['onedrive_refresh_token'] = 'r1';
      final broker = FakeTokenBroker();
      final provider = OneDriveProvider(
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

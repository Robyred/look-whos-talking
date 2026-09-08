import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:look_whos_talking/services/google_drive_gateway_impl.dart';

void main() {
  group('AuthHeaderClient', () {
    test('injects Authorization header on every request', () async {
      final inner = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer tok123');
        expect(request.headers['X-Goog-AuthUser'], '0');
        return http.Response('{}', 200);
      });
      final client = AuthHeaderClient(
        inner,
        () async => {
          'Authorization': 'Bearer tok123',
          'X-Goog-AuthUser': '0',
        },
      );

      final response = await client.get(Uri.parse('https://api.test/x'));
      expect(response.statusCode, 200);
    });

    test('adds no header when the provider returns null (signed out)',
        () async {
      final inner = MockClient((request) async {
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response('{}', 200);
      });
      final client = AuthHeaderClient(inner, () async => null);

      await client.get(Uri.parse('https://api.test/x'));
    });

    test('passes request bodies and methods through untouched', () async {
      late http.Request seen;
      final inner = MockClient((request) async {
        seen = request;
        return http.Response('{"ok":true}', 200,
            headers: {'content-type': 'application/json'});
      });
      final client = AuthHeaderClient(
        inner,
        () async => {'Authorization': 'Bearer t'},
      );

      final response = await client.post(
        Uri.parse('https://api.test/files'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'name': 'x'}),
      );

      expect(seen.method, 'POST');
      expect(seen.url.path, '/files');
      expect(seen.body, '{"name":"x"}');
      expect(jsonDecode(response.body), {'ok': true});
    });
  });
}

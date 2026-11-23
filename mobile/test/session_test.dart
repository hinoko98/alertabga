import 'dart:convert';
import 'dart:typed_data';

import 'package:alertabga/core/auth/session_store.dart';
import 'package:alertabga/core/network/api_client.dart';
import 'package:alertabga/core/network/api_error.dart';
import 'package:alertabga/core/storage/secure_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

String jwt(String sub) {
  String part(Map<String, dynamic> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'sub': sub})}.firma';
}

/// Servidor falso: responde según la ruta y registra lo recibido.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions o) handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    requests.add(o);
    return handler(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(int status, Object body) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });

void main() {
  group('SessionStore', () {
    test('guarda, recarga, expone userId y limpia', () async {
      final kv = MemoryKeyValueStore();
      final s = SessionStore(kv);
      var notified = 0;
      s.addListener(() => notified++);
      await s.save({'access_token': jwt('u-1'), 'refresh_token': 'r1'});
      expect(s.signedIn, isTrue);
      expect(s.userId, 'u-1');

      final reloaded = SessionStore(kv);
      await reloaded.load();
      expect(reloaded.refreshToken, 'r1');

      await s.clear();
      expect(s.signedIn, isFalse);
      expect(await kv.read('session_v1'), isNull);
      expect(notified, 2);
    });

    test('datos corruptos se descartan', () async {
      final kv = MemoryKeyValueStore()..data['session_v1'] = '{no-json';
      final s = SessionStore(kv);
      await s.load();
      expect(s.signedIn, isFalse);
      expect(kv.data.containsKey('session_v1'), isFalse);
    });
  });

  group('ApiClient: renovación de sesión', () {
    late SessionStore session;

    setUp(() async {
      session = SessionStore(MemoryKeyValueStore());
      await session.save({'access_token': 'viejo', 'refresh_token': 'r-viejo'});
    });

    test('ante 401 renueva una vez y reintenta con el token nuevo', () async {
      final adapter = FakeAdapter((o) {
        if (o.path.endsWith('/auth/refresh')) {
          return json(200, {'access_token': 'nuevo', 'refresh_token': 'r-nuevo'});
        }
        final auth = o.headers['Authorization'];
        return auth == 'Bearer nuevo' ? json(200, {'email': 'a@example.com'}) : json(401, {'detail': 'No autenticado'});
      });
      final c = ApiClient.create(baseUrl: 'http://api.test/api/py', session: session);
      c.setHttpAdapter(adapter);
      final me = await c.account();
      expect(me['email'], 'a@example.com');
      expect(session.accessToken, 'nuevo');
      expect(session.refreshToken, 'r-nuevo');
      expect(adapter.requests.where((r) => r.path.endsWith('/auth/refresh')), hasLength(1));
    });

    test('si la renovación falla, cierra la sesión y propaga 401', () async {
      final adapter = FakeAdapter((o) => o.path.endsWith('/auth/refresh')
          ? json(401, {'detail': 'Sesión vencida'})
          : json(401, {'detail': 'No autenticado'}));
      final c = ApiClient.create(baseUrl: 'http://api.test/api/py', session: session);
      c.setHttpAdapter(adapter);
      await expectLater(c.account(), throwsA(isA<ApiError>().having((e) => e.statusCode, 'status', 401)));
      expect(session.signedIn, isFalse);
    });

    test('las solicitudes anónimas no llevan token', () async {
      final adapter = FakeAdapter((o) => json(200, {
            'id': 'i', 'radicado': 'BGA-2026-000001', 'received_at': '2026-11-22T10:00:00+00:00',
            'out_of_scope': false, 'tracking_token': 't',
          }));
      final c = ApiClient.create(baseUrl: 'http://api.test/api/py', session: session);
      c.setHttpAdapter(adapter);
      await c.createReport({'x': 1}, anonymous: true);
      expect(adapter.requests.single.headers.containsKey('Authorization'), isFalse);
      expect(adapter.requests.single.path, endsWith('/reports/anonymous'));
    });

    test('mensaje de la API en español llega al usuario', () async {
      final adapter = FakeAdapter((o) => json(429, {'detail': 'Ha enviado demasiados reportes. Intente más tarde.'}));
      final c = ApiClient.create(baseUrl: 'http://api.test/api/py', session: session);
      c.setHttpAdapter(adapter);
      await expectLater(c.createReport({}, anonymous: true),
          throwsA(isA<ApiError>().having((e) => e.message, 'msg', contains('demasiados reportes'))));
    });
  });
}

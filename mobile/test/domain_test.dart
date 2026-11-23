import 'dart:typed_data';

import 'package:alertabga/core/domain/incident_status.dart';
import 'package:alertabga/core/domain/report_models.dart';
import 'package:alertabga/core/geo/territorial_scope.dart';
import 'package:alertabga/core/router/app_router.dart';
import 'package:alertabga/core/storage/secure_store.dart';
import 'package:alertabga/features/report/domain/report_draft.dart';
import 'package:flutter_test/flutter_test.dart';

const hurto = Category(id: 'c1', name: 'Hurto', description: '', icon: 'wallet');
const centro = ReportLocation(lat: 7.1193, lon: -73.1227, accuracyM: 10, manual: false);

PhotoAttachment photo({int size = 1000, String mime = 'image/jpeg'}) =>
    PhotoAttachment(name: 'f.jpg', mime: mime, bytes: Uint8List(size));

void main() {
  final now = DateTime(2026, 11, 22, 12);
  final valid = ReportDraft(
    category: hurto,
    location: centro,
    description: 'Me robaron el celular en la esquina',
    occurredAt: now.subtract(const Duration(hours: 1)),
  );

  group('ReportDraft.validate', () {
    test('borrador completo es válido', () => expect(valid.validate(now: now), isEmpty));

    test('exige categoría y ubicación', () {
      final e = const ReportDraft().validate(now: now);
      expect(e.keys, containsAll([ReportStep.category, ReportStep.location, ReportStep.details]));
    });

    test('descripción de 10 a 2000 caracteres (sin contar espacios extremos)', () {
      expect(valid.copyWith(description: '   corto   ').validate(now: now)[ReportStep.details], isNotNull);
      expect(valid.copyWith(description: 'x' * 10).validate(now: now), isEmpty);
      expect(valid.copyWith(description: 'x' * 2001).validate(now: now)[ReportStep.details], contains('2000'));
    });

    test('fecha futura no permitida (tolerancia 5 min)', () {
      expect(valid.copyWith(occurredAt: now.add(const Duration(minutes: 4))).validate(now: now), isEmpty);
      expect(valid.copyWith(occurredAt: now.add(const Duration(minutes: 10))).validate(now: now)[ReportStep.details],
          contains('futura'));
    });

    test('ubicación fuera del municipio bloquea el envío', () {
      final bogota = valid.copyWith(location: const ReportLocation(lat: 4.71, lon: -74.07, manual: true));
      expect(bogota.validate(now: now)[ReportStep.location], contains('fuera'));
    });

    test('máximo 3 fotos de hasta 5 MB y formato permitido', () {
      expect(valid.copyWith(photos: List.generate(3, (_) => photo())).validate(now: now), isEmpty);
      expect(valid.copyWith(photos: List.generate(4, (_) => photo())).validate(now: now)[ReportStep.photos], isNotNull);
      expect(valid.copyWith(photos: [photo(size: maxPhotoBytes + 1)]).validate(now: now)[ReportStep.photos], isNotNull);
      expect(valid.copyWith(photos: [photo(mime: 'image/gif')]).validate(now: now)[ReportStep.photos], isNotNull);
    });

    test('toRequest envía UTC, recorta textos y omite opcionales vacíos', () {
      final r = valid.copyWith(addressText: '  ', additionalInfo: ' extra ').toRequest();
      expect(r['category_id'], 'c1');
      expect(r['address_text'], isNull);
      expect(r['additional_info'], 'extra');
      expect((r['occurred_at'] as String).endsWith('Z'), isTrue);
      expect(r['location_manual'], isFalse);
    });

    test('mimeForPath', () {
      expect(mimeForPath('a.JPG'), 'image/jpeg');
      expect(mimeForPath('a.webp'), 'image/webp');
      expect(mimeForPath('a.heic'), isNull);
    });
  });

  group('TerritorialScope', () {
    const s = TerritorialScope.bucaramanga;
    test('contiene el centro de Bucaramanga', () => expect(s.contains(7.1193, -73.1227), isTrue));
    test('excluye Bogotá y bordes externos', () {
      expect(s.contains(4.71, -74.07), isFalse);
      expect(s.contains(7.26, -73.10), isFalse);
      expect(s.contains(7.10, -73.21), isFalse);
    });
    test('bordes incluidos', () => expect(s.contains(7.03, -73.20), isTrue));
  });

  group('IncidentStatus', () {
    test('mapea los 6 estados con etiqueta, icono y paso', () {
      expect(IncidentStatus.values, hasLength(6));
      final codes = {for (final s in IncidentStatus.values) s.code: s};
      expect(codes.keys, ['RECIBIDO', 'EN_REVISION', 'ASIGNADO', 'EN_ATENCION', 'CERRADO', 'NO_PROCEDE']);
      expect(IncidentStatus.values.map((s) => s.label).toSet(), hasLength(6));
      expect(IncidentStatus.values.map((s) => s.icon).toSet(), hasLength(6));
      expect([for (final s in IncidentStatus.values) s.step], [0, 1, 2, 3, 4, 4]);
    });
    test('estados finales', () {
      expect(IncidentStatus.cerrado.isFinal && IncidentStatus.noProcede.isFinal, isTrue);
      expect(IncidentStatus.asignado.isFinal, isFalse);
    });
    test('código desconocido cae en Recibido', () => expect(IncidentStatus.fromCode('X'), IncidentStatus.recibido));
  });

  group('ReportDetail.fromJson', () {
    test('parsea timeline con mensajes', () {
      final d = ReportDetail.fromJson({
        'id': 'i', 'radicado': 'BGA-2026-000001', 'category': 'Hurto', 'status': 'ASIGNADO',
        'description': 'desc', 'occurred_at': '2026-11-22T10:00:00+00:00', 'received_at': '2026-11-22T10:05:00+00:00',
        'address_text': null, 'out_of_scope': false, 'evidence_count': 2,
        'timeline': [
          {'at': '2026-11-22T10:05:00+00:00', 'kind': 'estado', 'status': 'RECIBIDO', 'text': 'Reporte recibido'},
          {'at': '2026-11-22T11:00:00+00:00', 'kind': 'mensaje', 'status': null, 'text': 'Patrulla en camino'},
        ],
      });
      expect(d.status, IncidentStatus.asignado);
      expect(d.timeline.last.kind, TimelineKind.message);
      expect(d.evidenceCount, 2);
    });
  });

  group('authRedirect', () {
    test('sin sesión no entra a rutas privadas', () {
      expect(authRedirect(path: '/home', signedIn: false), '/');
      expect(authRedirect(path: '/reports/BGA-2026-000001', signedIn: false), '/');
    });
    test('sin sesión puede reportar y consultar', () {
      expect(authRedirect(path: '/report', signedIn: false), isNull);
      expect(authRedirect(path: '/track', signedIn: false), isNull);
    });
    test('con sesión la bienvenida lleva al inicio', () {
      expect(authRedirect(path: '/', signedIn: true), '/home');
      expect(authRedirect(path: '/login', signedIn: true), '/home');
    });
  });

  group('AnonymousReportsStore', () {
    test('guarda, ordena por fecha, reemplaza y borra', () async {
      final store = AnonymousReportsStore(MemoryKeyValueStore());
      await store.add(SavedAnonymousReport(radicado: 'A', token: 't1', createdAt: DateTime(2026, 1, 1)));
      await store.add(SavedAnonymousReport(radicado: 'B', token: 't2', createdAt: DateTime(2026, 2, 1)));
      await store.add(SavedAnonymousReport(radicado: 'A', token: 't3', createdAt: DateTime(2026, 1, 1)));
      final list = await store.list();
      expect(list.map((e) => e.radicado), ['B', 'A']);
      expect(list.last.token, 't3');
      await store.remove('B');
      expect((await store.list()).map((e) => e.radicado), ['A']);
      await store.clear();
      expect(await store.list(), isEmpty);
    });
  });
}

import 'dart:async';
import 'dart:typed_data';

import 'package:alertabga/core/domain/report_models.dart';
import 'package:alertabga/core/network/api_error.dart';
import 'package:alertabga/features/report/application/report_controller.dart';
import 'package:alertabga/features/report/data/report_repository.dart';
import 'package:alertabga/features/report/domain/report_draft.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'domain_test.dart' show centro, hurto;

class FakeReportRepository implements ReportRepository {
  final calls = <bool>[];
  Completer<SubmitResult>? pending;

  @override
  Future<List<Category>> categories() async => [hurto];

  @override
  Future<SubmitResult> submit(ReportDraft draft, {required bool anonymous}) {
    calls.add(anonymous);
    pending = Completer<SubmitResult>();
    return pending!.future;
  }
}

SubmitResult result() => SubmitResult(
      report: ReportCreated(id: 'i', radicado: 'BGA-2026-000001', receivedAt: DateTime(2026), outOfScope: false, trackingToken: 't'),
      photosSent: 0,
      photosFailed: 0,
    );

void main() {
  late FakeReportRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = FakeReportRepository();
    container = ProviderContainer(overrides: [reportRepositoryProvider.overrideWithValue(repo)]);
  });
  tearDown(() => container.dispose());

  ReportController ctrl() => container.read(reportControllerProvider(true).notifier);
  ReportFormState state() => container.read(reportControllerProvider(true));

  void fill() {
    container.listen(reportControllerProvider(true), (_, _) {}); // mantiene vivo el autoDispose
    ctrl().update((d) => d.copyWith(category: hurto, location: centro, description: 'Descripción suficiente'));
  }

  test('no avanza con el paso inválido y muestra el error', () {
    container.listen(reportControllerProvider(true), (_, _) {});
    expect(ctrl().next(), isFalse);
    expect(state().step, ReportStep.category);
    expect(state().error, isNotNull);
  });

  test('avanza por los pasos cuando son válidos', () {
    fill();
    for (var i = 0; i < 4; i++) {
      expect(ctrl().next(), isTrue);
    }
    expect(state().step, ReportStep.review);
  });

  test('deshabilita el envío mientras submitting y evita doble envío', () async {
    fill();
    expect(state().canSubmit, isTrue);
    final first = ctrl().submit();
    expect(state().submitting, isTrue);
    expect(state().canSubmit, isFalse);
    expect(await ctrl().submit(), isNull); // segundo toque ignorado
    repo.pending!.complete(result());
    expect((await first)!.report.radicado, 'BGA-2026-000001');
    expect(repo.calls, [true]);
    expect(state().submitting, isFalse);
    expect(state().canSubmit, isFalse); // ya enviado
    expect(await ctrl().submit(), isNull);
    expect(repo.calls, hasLength(1));
  });

  test('error de red deja el borrador y permite reintentar', () async {
    fill();
    final f = ctrl().submit();
    repo.pending!.completeError(const ApiError('No hay conexión con el servidor.'));
    expect(await f, isNull);
    expect(state().error, contains('conexión'));
    expect(state().canSubmit, isTrue);
  });

  test('envío con borrador inválido lleva al paso con error', () async {
    container.listen(reportControllerProvider(true), (_, _) {});
    ctrl().update((d) => d.copyWith(category: hurto));
    expect(await ctrl().submit(), isNull);
    expect(state().step, ReportStep.location);
    expect(repo.calls, isEmpty);
  });

  test('addPhoto respeta límite, tamaño y formato', () {
    fill();
    for (var i = 0; i < 3; i++) {
      ctrl().addPhoto(PhotoAttachment(name: 'a.jpg', mime: 'image/jpeg', bytes: Uint8List(10)));
    }
    ctrl().addPhoto(PhotoAttachment(name: 'b.jpg', mime: 'image/jpeg', bytes: Uint8List(10)));
    expect(state().draft.photos, hasLength(3));
    expect(state().error, contains('Máximo'));
    ctrl().removePhoto(0);
    ctrl().addPhoto(PhotoAttachment(name: 'c.jpg', mime: 'image/jpeg', bytes: Uint8List(maxPhotoBytes + 1)));
    ctrl().addPhoto(PhotoAttachment(name: 'd.gif', mime: 'image/gif', bytes: Uint8List(10)));
    expect(state().draft.photos, hasLength(2));
  });
}

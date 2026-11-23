import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/report_models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_store.dart';
import '../domain/report_draft.dart';

class SubmitResult {
  const SubmitResult({required this.report, required this.photosSent, required this.photosFailed});

  final ReportCreated report;
  final int photosSent;
  final int photosFailed;
}

/// Envía el reporte y luego sus fotos (presign → PUT directo al almacenamiento → confirm).
/// Si una foto falla, el reporte ya quedó radicado: se informa sin perderlo.
class ReportRepository {
  ReportRepository(this._api, this._anonStore);

  final ApiClient _api;
  final AnonymousReportsStore _anonStore;

  Future<List<Category>> categories() => _api.categories();

  Future<SubmitResult> submit(ReportDraft draft, {required bool anonymous}) async {
    final created = await _api.createReport(draft.toRequest(), anonymous: anonymous);
    final token = created.trackingToken;
    if (anonymous && token != null) {
      await _anonStore.add(SavedAnonymousReport(radicado: created.radicado, token: token, createdAt: created.receivedAt));
    }
    var sent = 0;
    var failed = 0;
    for (final photo in draft.photos) {
      try {
        final p = await _api.presignEvidence(
            radicado: created.radicado, mime: photo.mime, size: photo.size, trackingToken: token);
        await _api.uploadEvidence(p, photo.bytes);
        final status = await _api.confirmEvidence(p.evidenceId, radicado: created.radicado, trackingToken: token);
        status == 'CONFIRMADA' ? sent++ : failed++;
      } catch (_) {
        failed++;
      }
    }
    return SubmitResult(report: created, photosSent: sent, photosFailed: failed);
  }
}

final reportRepositoryProvider = Provider<ReportRepository>(
    (ref) => ReportRepository(ref.watch(apiClientProvider), ref.watch(anonymousReportsStoreProvider)));

final categoriesProvider = FutureProvider.autoDispose<List<Category>>((ref) => ref.watch(reportRepositoryProvider).categories());

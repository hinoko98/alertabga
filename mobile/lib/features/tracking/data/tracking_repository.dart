import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/report_models.dart';
import '../../../core/network/api_client.dart';

/// Lecturas de seguimiento, siempre desde la API (que filtra notas internas).
class TrackingRepository {
  TrackingRepository(this._api);

  final ApiClient _api;

  Future<List<ReportSummary>> mine() => _api.myReports();
  Future<ReportDetail> detail(String radicado) => _api.reportDetail(radicado);
  Future<ReportDetail> track(String radicado, String token) => _api.track(radicado, token);
}

final trackingRepositoryProvider = Provider<TrackingRepository>((ref) => TrackingRepository(ref.watch(apiClientProvider)));

/// Intervalo de actualización automática mientras la pantalla de seguimiento está abierta.
const trackingPollInterval = Duration(seconds: 30);

final myReportsProvider = FutureProvider.autoDispose<List<ReportSummary>>((ref) => ref.watch(trackingRepositoryProvider).mine());

/// Programa una recarga periódica del proveedor mientras alguien lo escuche.
void _poll(Ref ref) {
  final timer = Timer(trackingPollInterval, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
}

/// Detalle del reporte propio; se actualiza solo cada 30 s (o al deslizar).
final ownReportProvider = FutureProvider.autoDispose.family<ReportDetail, String>((ref, radicado) async {
  _poll(ref);
  return ref.watch(trackingRepositoryProvider).detail(radicado);
});

/// Reporte anónimo con su código; misma actualización periódica.
final anonymousReportProvider = FutureProvider.autoDispose.family<ReportDetail, (String, String)>((ref, args) async {
  _poll(ref);
  return ref.watch(trackingRepositoryProvider).track(args.$1, args.$2);
});

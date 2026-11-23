import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/domain/report_models.dart';
import '../../../core/network/api_client.dart';

/// Lecturas de seguimiento. Los datos siempre vienen de la API (que filtra notas internas);
/// Realtime solo avisa que algo cambió.
class TrackingRepository {
  TrackingRepository(this._api, [this._supabase]);

  final ApiClient _api;
  final SupabaseClient? _supabase;

  Future<List<ReportSummary>> mine() => _api.myReports();
  Future<ReportDetail> detail(String radicado) => _api.reportDetail(radicado);
  Future<ReportDetail> track(String radicado, String token) => _api.track(radicado, token);

  /// Emite cada vez que cambia el incidente o llega un mensaje institucional (RLS filtra a los propios).
  Stream<void> changes(String incidentId) {
    final sb = _supabase;
    if (sb == null) return const Stream.empty();
    late final RealtimeChannel channel;
    final ctrl = StreamController<void>(onCancel: () => sb.removeChannel(channel));
    channel = sb
        .channel('incident-$incidentId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'incidents',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: incidentId),
          callback: (_) => ctrl.add(null),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'institutional_messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'incident_id', value: incidentId),
          callback: (_) => ctrl.add(null),
        )
        .subscribe();
    return ctrl.stream;
  }
}

final trackingRepositoryProvider = Provider<TrackingRepository>(
    (ref) => TrackingRepository(ref.watch(apiClientProvider), Supabase.instance.client));

final myReportsProvider = FutureProvider.autoDispose<List<ReportSummary>>((ref) => ref.watch(trackingRepositoryProvider).mine());

/// Detalle del reporte propio, que se recarga solo cuando Realtime avisa un cambio.
final ownReportProvider = FutureProvider.autoDispose.family<ReportDetail, String>((ref, radicado) async {
  final repo = ref.watch(trackingRepositoryProvider);
  final detail = await repo.detail(radicado);
  final sub = repo.changes(detail.id).listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return detail;
});

final anonymousReportProvider =
    FutureProvider.autoDispose.family<ReportDetail, (String, String)>((ref, args) => ref.watch(trackingRepositoryProvider).track(args.$1, args.$2));

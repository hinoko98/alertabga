import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/domain/report_models.dart';
import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../data/tracking_repository.dart';
import '../widgets/status_timeline.dart';

/// Seguimiento de un reporte. Autenticado: se actualiza en tiempo real.
/// Anónimo (con código): deslizar hacia abajo para refrescar.
class TrackingScreen extends ConsumerWidget {
  const TrackingScreen.own({super.key, required this.radicado}) : token = null;
  const TrackingScreen.anonymous({super.key, required this.radicado, required String this.token});

  final String radicado;
  final String? token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tok = token;
    final provider = tok == null ? ownReportProvider(radicado) : anonymousReportProvider((radicado, tok));
    final async = ref.watch(provider);

    return Scaffold(
      appBar: AppBar(title: Text(radicado)),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(provider.future),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(padding: const EdgeInsets.all(16), children: [
            ErrorBox(ApiError.from(e).isNotFound ? 'Radicado o código no válido.' : ApiError.from(e).message),
          ]),
          data: (d) => _DetailView(detail: d, live: tok == null),
        ),
      ),
    );
  }
}

class _DetailView extends StatelessWidget {
  const _DetailView({required this.detail, required this.live});

  final ReportDetail detail;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final fmt = DateFormat('d MMM yyyy, h:mm a', 'es_CO');
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(d.category, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                  StatusChip(d.status),
                ]),
                const SizedBox(height: 6),
                Text(d.status.description, style: const TextStyle(color: BrandColors.slate500)),
                const SizedBox(height: 16),
                StatusProgress(d.status),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.description),
                const SizedBox(height: 10),
                _meta(Icons.event, 'Ocurrió: ${fmt.format(d.occurredAt.toLocal())}'),
                _meta(Icons.inbox_outlined, 'Recibido: ${fmt.format(d.receivedAt.toLocal())}'),
                if (d.addressText != null) _meta(Icons.place_outlined, d.addressText!),
                _meta(Icons.photo_outlined, d.evidenceCount == 0 ? 'Sin fotos' : '${d.evidenceCount} foto(s) recibidas'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          const Text('Historial', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const Spacer(),
          Icon(live ? Icons.sensors : Icons.swipe_down_alt, size: 16, color: BrandColors.slate500),
          const SizedBox(width: 4),
          Text(live ? 'En tiempo real' : 'Deslice para actualizar', style: const TextStyle(color: BrandColors.slate500, fontSize: 12)),
        ]),
        const SizedBox(height: 12),
        StatusTimeline(entries: d.timeline),
      ],
    );
  }

  Widget _meta(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          Icon(icon, size: 16, color: BrandColors.slate500),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(color: BrandColors.slate500))),
        ]),
      );
}

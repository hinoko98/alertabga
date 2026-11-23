import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../application/report_controller.dart';
import '../domain/report_draft.dart';

class ReviewStep extends ConsumerWidget {
  const ReviewStep({super.key, required this.anonymous});

  final bool anonymous;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(reportControllerProvider(anonymous));
    final c = ref.read(reportControllerProvider(anonymous).notifier);
    final d = s.draft;
    final errors = d.validate();
    final fmt = DateFormat("d MMM yyyy, h:mm a", 'es_CO');

    Widget row(ReportStep step, IconData icon, String title, String value) => Card(
          child: ListTile(
            leading: Icon(icon, color: BrandColors.navy900),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(errors[step] ?? value, style: errors[step] != null ? const TextStyle(color: BrandColors.danger) : null),
            trailing: TextButton(onPressed: s.submitting ? null : () => c.goTo(step), child: const Text('Editar')),
          ),
        );

    final loc = d.location;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        row(ReportStep.category, Icons.category_outlined, 'Tipo', d.category?.name ?? '—'),
        row(ReportStep.location, Icons.place_outlined, 'Ubicación',
            loc == null ? '—' : '${loc.lat.toStringAsFixed(5)}, ${loc.lon.toStringAsFixed(5)}${loc.manual ? ' (marcada en mapa)' : ' (GPS)'}'),
        row(ReportStep.details, Icons.notes, 'Descripción',
            '${d.description.trim()}\n${d.occurredAt == null ? '' : fmt.format(d.occurredAt!)}'),
        row(ReportStep.photos, Icons.photo_outlined, 'Fotos', d.photos.isEmpty ? 'Sin fotos' : '${d.photos.length} adjunta(s)'),
        const SizedBox(height: 12),
        InfoBox(anonymous
            ? 'Reporte anónimo: no guardamos su identidad. Recibirá un radicado y un código de seguimiento; '
                'guárdelos, son la única forma de consultar el caso.'
            : 'El reporte quedará asociado a su cuenta y podrá seguirlo en “Mis reportes”.'),
        const SizedBox(height: 8),
        const Text(
          'Un reporte ciudadano no equivale a una denuncia penal. Para denunciar, acuda a la Fiscalía o a la Policía.',
          style: TextStyle(color: BrandColors.slate500),
        ),
      ],
    );
  }
}

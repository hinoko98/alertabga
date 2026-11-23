import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/domain/incident_status.dart';
import '../../../core/domain/report_models.dart';
import '../../../core/theme/app_theme.dart';

/// Insignia de estado: icono + texto (no depende solo del color).
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final IncidentStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: status.color.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(status.icon, size: 16, color: status.color),
        const SizedBox(width: 6),
        Text(status.label, style: TextStyle(color: status.color, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Barra de progreso por pasos: Recibido → En revisión → Asignado → En atención → Final.
class StatusProgress extends StatelessWidget {
  const StatusProgress(this.status, {super.key});

  final IncidentStatus status;

  @override
  Widget build(BuildContext context) {
    final labels = ['Recibido', 'En revisión', 'Asignado', 'En atención', status.isFinal ? status.label : 'Cierre'];
    return Semantics(
      label: 'Progreso: paso ${status.step + 1} de ${IncidentStatus.totalSteps}, ${status.label}',
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 0; i < IncidentStatus.totalSteps; i++)
              Expanded(
                child: Column(
                  children: [
                    Container(
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: i <= status.step ? status.color : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(labels[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: i == status.step ? FontWeight.w800 : FontWeight.w400,
                          color: i <= status.step ? BrandColors.navy900 : BrandColors.slate500,
                        )),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Historial visible al ciudadano: cambios de estado y mensajes institucionales.
class StatusTimeline extends StatelessWidget {
  const StatusTimeline({super.key, required this.entries});

  final List<TimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const Text('Sin novedades todavía.');
    final fmt = DateFormat('d MMM yyyy, h:mm a', 'es_CO');
    final items = entries.reversed.toList(); // lo más reciente arriba
    return Column(
      children: [
        for (final e in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: e.kind == TimelineKind.message ? const Color(0xFFE0F2FE) : (e.status?.color ?? BrandColors.slate500).withValues(alpha: 0.12),
                  child: Icon(
                    e.kind == TimelineKind.message ? Icons.forum_outlined : (e.status?.icon ?? Icons.circle_outlined),
                    size: 18,
                    color: e.kind == TimelineKind.message ? const Color(0xFF0369A1) : (e.status?.color ?? BrandColors.slate500),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.kind == TimelineKind.message ? 'Mensaje de la institución' : 'Estado: ${e.status?.label ?? '—'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (e.text != null && e.text!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(e.text!)),
                      Text(fmt.format(e.at.toLocal()), style: const TextStyle(fontSize: 12, color: BrandColors.slate500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

/// Estados del reporte (espejo del enum `incident_status` de la base de datos).
/// Cada estado tiene etiqueta e icono propios: nunca se comunica solo con color.
enum IncidentStatus {
  recibido('RECIBIDO', 'Recibido', 'Su reporte llegó a la plataforma.', Icons.inbox_outlined, 0),
  enRevision('EN_REVISION', 'En revisión', 'Un operador está revisando la información.', Icons.manage_search, 1),
  asignado('ASIGNADO', 'Asignado', 'El caso fue asignado al cuadrante responsable.', Icons.assignment_ind_outlined, 2),
  enAtencion('EN_ATENCION', 'En atención', 'El cuadrante está atendiendo el caso.', Icons.local_police_outlined, 3),
  cerrado('CERRADO', 'Cerrado', 'La atención del caso finalizó.', Icons.task_alt, 4),
  noProcede('NO_PROCEDE', 'No procede', 'El reporte fue revisado y no procede.', Icons.block, 4);

  const IncidentStatus(this.code, this.label, this.description, this.icon, this.step);

  final String code;
  final String label;
  final String description;
  final IconData icon;

  /// Paso en la línea de progreso (0..4). Los dos estados finales comparten el último paso.
  final int step;

  static const totalSteps = 5;

  bool get isFinal => this == cerrado || this == noProcede;

  Color get color => switch (this) {
        recibido => const Color(0xFF475569),
        enRevision => const Color(0xFF0369A1),
        asignado => const Color(0xFF7C3AED),
        enAtencion => const Color(0xFFB45309),
        cerrado => const Color(0xFF047857),
        noProcede => const Color(0xFFB91C1C),
      };

  static IncidentStatus fromCode(String? code) =>
      values.firstWhere((s) => s.code == code, orElse: () => recibido);
}

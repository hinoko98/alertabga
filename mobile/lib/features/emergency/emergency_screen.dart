import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';

class EmergencyLine {
  const EmergencyLine(this.number, this.name, this.description);

  final String number;
  final String name;
  final String description;
}

/// Líneas nacionales de Colombia (públicas y gratuitas).
const emergencyLines = [
  EmergencyLine('123', 'Línea única de emergencias', 'Policía, bomberos, ambulancias. Peligro inmediato.'),
  EmergencyLine('155', 'Violencia contra la mujer', 'Orientación a mujeres víctimas de violencia.'),
  EmergencyLine('141', 'ICBF — Niños, niñas y adolescentes', 'Maltrato o riesgo de menores de edad.'),
  EmergencyLine('122', 'Fiscalía — Denuncias', 'Para presentar una denuncia penal.'),
];

class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

  Future<void> _call(BuildContext context, String number) async {
    final ok = await launchUrl(Uri(scheme: 'tel', path: number));
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Marque $number desde su teléfono')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emergencias')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'AlertaBGA no reemplaza las líneas de emergencia. Si usted o alguien está en peligro ahora, llame al 123.',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 88,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: BrandColors.danger),
              onPressed: () => _call(context, '123'),
              icon: const Icon(Icons.phone, size: 32),
              label: const Text('Llamar al 123', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 24),
          for (final l in emergencyLines.skip(1))
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(l.number, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
                title: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(l.description),
                trailing: IconButton(tooltip: 'Llamar al ${l.number}', icon: const Icon(Icons.phone), onPressed: () => _call(context, l.number)),
              ),
            ),
        ],
      ),
    );
  }
}

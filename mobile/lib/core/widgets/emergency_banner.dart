import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';

/// Aviso permanente: la app no reemplaza la línea de emergencias 123.
class EmergencyBanner extends StatelessWidget {
  const EmergencyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFEF2F2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFFECACA)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/emergency'),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.phone_in_talk, color: BrandColors.danger, semanticLabel: 'Emergencia'),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  '¿Peligro inmediato? Llame al 123. Esta app no reemplaza la línea de emergencias.',
                  style: TextStyle(color: Color(0xFF7F1D1D), fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.chevron_right, color: Color(0xFF7F1D1D)),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../../core/widgets/emergency_banner.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          children: [
            const Center(child: BrandLogo(size: 96)),
            const SizedBox(height: 16),
            Text('AlertaBGA', textAlign: TextAlign.center, style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              'Reporte incidentes de seguridad en Bucaramanga y haga seguimiento a la respuesta institucional.',
              textAlign: TextAlign.center,
              style: t.bodyLarge?.copyWith(color: BrandColors.slate500),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => context.push('/login'),
              icon: const Icon(Icons.login),
              label: const Text('Ingresar'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              onPressed: () => context.push('/register'),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Crear cuenta'),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => context.push('/report', extra: true),
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Reportar sin cuenta'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => context.push('/track'),
              icon: const Icon(Icons.search),
              label: const Text('Consultar radicado'),
            ),
            const SizedBox(height: 28),
            const EmergencyBanner(),
          ],
        ),
      ),
    );
  }
}

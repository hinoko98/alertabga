import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/emergency_banner.dart';
import '../profile/profile_screen.dart';
import '../tracking/presentation/my_reports_screen.dart';

/// Inicio del ciudadano autenticado: Reportar · Mis reportes · Perfil.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _titles = ['AlertaBGA', 'Mis reportes', 'Mi perfil'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          IconButton(tooltip: 'Configuración', icon: const Icon(Icons.settings_outlined), onPressed: () => context.push('/settings')),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          const _HomeTab(),
          if (_tab == 1) const MyReportsScreen() else const SizedBox.shrink(),
          if (_tab == 2) const ProfileScreen() else const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: 'Mis reportes'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const EmergencyBanner(),
        const SizedBox(height: 24),
        SizedBox(
          height: 120,
          child: FilledButton(
            onPressed: () => context.push('/report', extra: false),
            child: const Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.campaign, size: 40),
              SizedBox(height: 8),
              Text('Reportar un incidente', style: TextStyle(fontSize: 19)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: () => context.push('/report', extra: true),
          icon: const Icon(Icons.visibility_off_outlined),
          label: const Text('Reportar de forma anónima'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: () => context.push('/track'),
          icon: const Icon(Icons.search),
          label: const Text('Consultar un reporte anónimo'),
        ),
        const SizedBox(height: 24),
        const Text(
          'Su reporte llega al cuadrante de policía responsable. Un reporte ciudadano no equivale a una denuncia penal.',
          style: TextStyle(color: BrandColors.slate500),
        ),
      ],
    );
  }
}

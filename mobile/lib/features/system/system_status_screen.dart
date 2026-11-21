import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_logo.dart';

final apiHealthProvider = FutureProvider.autoDispose<String>((ref) async {
  final data = await ref.watch(apiClientProvider).health();
  return data['status'] == 'ok' ? 'API operativa' : 'Respuesta inesperada';
});

/// Lectura pública de categorías activas: verifica Supabase + RLS para usuarios sin sesión.
final categoriesProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  final rows = await Supabase.instance.client.from('categories').select('name').order('name');
  return [for (final r in rows) r['name'] as String];
});

/// Pantalla de verificación de la Fase 1: conexión de la app con FastAPI y Supabase.
class SystemStatusScreen extends ConsumerWidget {
  const SystemStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiHealthProvider);
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Estado de conexión')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(apiHealthProvider);
          ref.invalidate(categoriesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Center(child: BrandLogo(size: 88)),
            const SizedBox(height: 12),
            Text('AlertaBGA', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            _StatusTile(
              title: 'API Python (FastAPI)',
              value: api.when(data: (v) => v, loading: () => 'Verificando…', error: (e, _) => 'Sin conexión'),
              ok: api.hasValue,
              failed: api.hasError,
            ),
            _StatusTile(
              title: 'Supabase (categorías públicas)',
              value: categories.when(
                data: (v) => v.isEmpty ? 'Sin categorías activas' : v.join(' · '),
                loading: () => 'Verificando…',
                error: (e, _) => 'Sin conexión',
              ),
              ok: categories.hasValue,
              failed: categories.hasError,
            ),
            const SizedBox(height: 24),
            const Text(
              'Esta aplicación no reemplaza la línea de emergencias 123. '
              'Ante un peligro inmediato, llame al 123.',
              textAlign: TextAlign.center,
              style: TextStyle(color: BrandColors.slate500),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.title, required this.value, required this.ok, required this.failed});

  final String title;
  final String value;
  final bool ok;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    // Icono + texto: el estado no depende solo del color.
    final (icon, color, label) = failed
        ? (Icons.error_outline, BrandColors.danger, 'Con fallas')
        : ok
            ? (Icons.check_circle_outline, BrandColors.success, 'Operativo')
            : (Icons.hourglass_empty, BrandColors.slate500, 'Verificando');
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color, semanticLabel: label),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('$label · $value'),
      ),
    );
  }
}

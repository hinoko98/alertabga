import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/storage/secure_store.dart';
import '../../../core/theme/app_theme.dart';

/// Consulta de reportes anónimos: los guardados en este teléfono o ingresando radicado + código.
class TrackLookupScreen extends ConsumerStatefulWidget {
  const TrackLookupScreen({super.key});

  @override
  ConsumerState<TrackLookupScreen> createState() => _TrackLookupScreenState();
}

class _TrackLookupScreenState extends ConsumerState<TrackLookupScreen> {
  final _form = GlobalKey<FormState>();
  final _radicado = TextEditingController();
  final _token = TextEditingController();

  @override
  void dispose() {
    _radicado.dispose();
    _token.dispose();
    super.dispose();
  }

  void _open() {
    if (!_form.currentState!.validate()) return;
    context.push('/track/view', extra: (_radicado.text.trim().toUpperCase(), _token.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(savedAnonymousReportsProvider);
    final fmt = DateFormat('d MMM yyyy', 'es_CO');
    return Scaffold(
      appBar: AppBar(title: const Text('Consultar radicado')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...saved.maybeWhen(
            data: (list) => list.isEmpty
                ? const <Widget>[]
                : [
                    const Text('Guardados en este teléfono', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 8),
                    for (final r in list)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.key),
                          title: Text(r.radicado, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('Enviado el ${fmt.format(r.createdAt.toLocal())}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/track/view', extra: (r.radicado, r.token)),
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],
            orElse: () => const <Widget>[],
          ),
          const Text('Consultar con radicado y código', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 12),
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _radicado,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Radicado', hintText: 'BGA-2026-000123', border: OutlineInputBorder()),
                  validator: (v) => RegExp(r'^BGA-\d{4}-\d{6,}$').hasMatch((v ?? '').trim().toUpperCase())
                      ? null
                      : 'Formato: BGA-AAAA-NNNNNN',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _token,
                  decoration: const InputDecoration(labelText: 'Código de seguimiento', border: OutlineInputBorder()),
                  validator: (v) => (v ?? '').trim().length < 20 ? 'Ingrese el código completo' : null,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(onPressed: _open, icon: const Icon(Icons.search), label: const Text('Consultar')),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Si tiene cuenta, sus reportes aparecen en “Mis reportes” sin necesidad de código.',
              style: TextStyle(color: BrandColors.slate500)),
        ],
      ),
    );
  }
}

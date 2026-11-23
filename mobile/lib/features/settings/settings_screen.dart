import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/secure_store.dart';
import '../../core/auth/session_store.dart';
import '../auth/data/auth_repository.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _clearAnonymous(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Borrar reportes anónimos guardados?'),
        content: const Text('Se borran el radicado y el código de este teléfono. Los reportes siguen existiendo, '
            'pero solo podrá consultarlos si tiene anotado el código.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(anonymousReportsStoreProvider).clear();
    ref.invalidate(savedAnonymousReportsProvider);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Borrados')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionStoreProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacidad y tratamiento de datos'),
            onTap: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Privacidad'),
                content: const SingleChildScrollView(
                  child: Text(
                    '• Los reportes anónimos no guardan su identidad; solo un código cifrado para el seguimiento.\n'
                    '• Su ubicación se usa únicamente para ubicar el hecho reportado.\n'
                    '• Las fotos se almacenan de forma privada y solo las ve personal autorizado.\n'
                    '• La dirección IP no se guarda en claro.\n'
                    '• Puede solicitar la consulta, corrección o supresión de sus datos (Ley 1581 de 2012).',
                  ),
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Entendido'))],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.key_off_outlined),
            title: const Text('Borrar reportes anónimos de este teléfono'),
            onTap: () => _clearAnonymous(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.wifi_tethering),
            title: const Text('Estado de conexión'),
            onTap: () => context.push('/system'),
          ),
          ListTile(
            leading: const Icon(Icons.phone_in_talk_outlined),
            title: const Text('Líneas de emergencia'),
            onTap: () => context.push('/emergency'),
          ),
          if (session.signedIn) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Cerrar sesión'),
              onTap: () async {
                await ref.read(authRepositoryProvider).signOut();
                if (context.mounted) context.go('/');
              },
            ),
          ],
          const AboutListTile(
            icon: Icon(Icons.info_outline),
            applicationName: 'AlertaBGA',
            applicationVersion: '1.0.0',
            aboutBoxChildren: [Text('Plataforma de reporte ciudadano de incidentes de seguridad — Bucaramanga.')],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../data/report_repository.dart';

class ConfirmationScreen extends StatelessWidget {
  const ConfirmationScreen({super.key, required this.result});

  final SubmitResult result;

  @override
  Widget build(BuildContext context) {
    final r = result.report;
    final token = r.trackingToken;
    final t = Theme.of(context).textTheme;

    void copy(String label, String value) {
      Clipboard.setData(ClipboardData(text: value));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copiado')));
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/');
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Reporte enviado'), automaticallyImplyLeading: false),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.check_circle, color: BrandColors.success, size: 72, semanticLabel: 'Enviado'),
              const SizedBox(height: 12),
              Text('Recibimos su reporte', textAlign: TextAlign.center, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 24),
              Card(
                child: ListTile(
                  title: const Text('Radicado'),
                  subtitle: SelectableText(r.radicado, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1)),
                  trailing: IconButton(tooltip: 'Copiar radicado', icon: const Icon(Icons.copy), onPressed: () => copy('Radicado', r.radicado)),
                ),
              ),
              if (token != null) ...[
                Card(
                  child: ListTile(
                    title: const Text('Código de seguimiento'),
                    subtitle: SelectableText(token, style: const TextStyle(fontFamily: 'monospace')),
                    trailing: IconButton(tooltip: 'Copiar código', icon: const Icon(Icons.copy), onPressed: () => copy('Código', token)),
                  ),
                ),
                const SizedBox(height: 8),
                const InfoBox('Guarde el radicado y el código. Quedaron guardados en este teléfono, pero si lo pierde '
                    'o borra la app no podremos recuperarlos: el reporte es anónimo.', icon: Icons.key),
              ],
              if (result.photosFailed > 0) ...[
                const SizedBox(height: 8),
                ErrorBox('${result.photosFailed} foto(s) no se pudieron enviar. El reporte sí quedó radicado.'),
              ] else if (result.photosSent > 0) ...[
                const SizedBox(height: 8),
                InfoBox('${result.photosSent} foto(s) enviadas correctamente.', icon: Icons.photo_library_outlined),
              ],
              if (r.outOfScope) ...[
                const SizedBox(height: 8),
                const ErrorBox('La ubicación quedó fuera del ámbito del municipio; el equipo revisará el caso.'),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => token != null
                    ? context.go('/track/view', extra: (r.radicado, token))
                    : context.go('/reports/${r.radicado}'),
                icon: const Icon(Icons.timeline),
                label: const Text('Ver seguimiento'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: () => context.go('/'),
                child: const Text('Volver al inicio'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

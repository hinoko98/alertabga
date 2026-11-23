import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_widgets.dart';
import '../application/report_controller.dart';
import '../domain/report_draft.dart';
import 'category_step.dart';
import 'details_step.dart';
import 'location_step.dart';
import 'photos_step.dart';
import 'review_step.dart';

const _titles = {
  ReportStep.category: '¿Qué ocurrió?',
  ReportStep.location: '¿Dónde ocurrió?',
  ReportStep.details: 'Detalles',
  ReportStep.photos: 'Fotos (opcional)',
  ReportStep.review: 'Revisar y enviar',
};

class ReportFlowScreen extends ConsumerWidget {
  const ReportFlowScreen({super.key, required this.anonymous});

  final bool anonymous;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = reportControllerProvider(anonymous);
    final s = ref.watch(provider);
    final c = ref.read(provider.notifier);
    final step = s.step;
    final last = step == ReportStep.review;

    final body = switch (step) {
      ReportStep.category => CategoryStep(anonymous: anonymous),
      ReportStep.location => LocationStep(anonymous: anonymous),
      ReportStep.details => DetailsStep(anonymous: anonymous),
      ReportStep.photos => PhotosStep(anonymous: anonymous),
      ReportStep.review => ReviewStep(anonymous: anonymous),
    };

    return PopScope(
      canPop: step == ReportStep.category && !s.submitting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !s.submitting) c.back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(anonymous ? 'Reporte anónimo' : 'Nuevo reporte'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(34),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(children: [
                Text('Paso ${step.index + 1} de ${ReportStep.values.length} · ${_titles[step]}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
        body: Column(
          children: [
            LinearProgressIndicator(value: (step.index + 1) / ReportStep.values.length, minHeight: 4),
            Expanded(child: body),
            if (s.error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: ErrorBox(s.error!)),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    if (step != ReportStep.category) ...[
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                          onPressed: s.submitting ? null : c.back,
                          child: const Text('Atrás'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      flex: 2,
                      child: last
                          ? FilledButton.icon(
                              key: const Key('enviar-reporte'),
                              onPressed: s.canSubmit
                                  ? () async {
                                      final r = await c.submit();
                                      if (r != null && context.mounted) {
                                        context.pushReplacement('/report/done', extra: r);
                                      }
                                    }
                                  : null,
                              icon: s.submitting ? const ButtonSpinner() : const Icon(Icons.send),
                              label: Text(s.submitting ? 'Enviando…' : 'Enviar reporte'),
                            )
                          : FilledButton(onPressed: c.next, child: const Text('Siguiente')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

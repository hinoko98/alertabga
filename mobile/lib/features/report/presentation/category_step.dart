import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../application/report_controller.dart';
import '../data/report_repository.dart';

IconData categoryIcon(String name) => switch (name) {
      'wallet' => Icons.account_balance_wallet_outlined,
      'car' => Icons.directions_car_outlined,
      'users' => Icons.groups_outlined,
      _ => Icons.report_gmailerrorred_outlined,
    };

class CategoryStep extends ConsumerWidget {
  const CategoryStep({super.key, required this.anonymous});

  final bool anonymous;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(categoriesProvider);
    final selected = ref.watch(reportControllerProvider(anonymous).select((s) => s.draft.category?.id));
    final c = ref.read(reportControllerProvider(anonymous).notifier);

    return cats.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ListView(padding: const EdgeInsets.all(16), children: [
        const ErrorBox('No se pudieron cargar las categorías. Revise su conexión.'),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: () => ref.invalidate(categoriesProvider), child: const Text('Reintentar')),
      ]),
      data: (list) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final cat in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                      color: selected == cat.id ? BrandColors.cyan : const Color(0xFFDDE4EE),
                      width: selected == cat.id ? 2.5 : 1),
                ),
                child: ListTile(
                  minVerticalPadding: 18,
                  leading: Icon(categoryIcon(cat.icon), size: 32, color: BrandColors.navy900),
                  title: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                  subtitle: cat.description.isEmpty ? null : Text(cat.description),
                  trailing: Icon(selected == cat.id ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: selected == cat.id ? BrandColors.cyan : BrandColors.slate500,
                      semanticLabel: selected == cat.id ? 'Seleccionada' : 'No seleccionada'),
                  onTap: () {
                    c.update((d) => d.copyWith(category: cat));
                    c.next();
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../data/tracking_repository.dart';
import '../widgets/status_timeline.dart';

class MyReportsScreen extends ConsumerWidget {
  const MyReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myReportsProvider);
    final fmt = DateFormat('d MMM yyyy, h:mm a', 'es_CO');
    return RefreshIndicator(
      onRefresh: () => ref.refresh(myReportsProvider.future),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(padding: const EdgeInsets.all(16), children: [ErrorBox(ApiError.from(e).message)]),
        data: (list) => list.isEmpty
            ? ListView(padding: const EdgeInsets.all(32), children: const [
                Icon(Icons.inbox_outlined, size: 56, color: BrandColors.slate500),
                SizedBox(height: 12),
                Text('Aún no tiene reportes.', textAlign: TextAlign.center),
              ])
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final r = list[i];
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      title: Text(r.category, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${r.radicado}\n${fmt.format(r.receivedAt.toLocal())}'),
                      isThreeLine: true,
                      trailing: StatusChip(r.status),
                      onTap: () => context.push('/reports/${r.radicado}'),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

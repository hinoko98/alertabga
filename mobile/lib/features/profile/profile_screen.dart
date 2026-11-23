import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/data/auth_repository.dart';
import '../auth/presentation/auth_widgets.dart';
import '../auth/presentation/validators.dart';

class Profile {
  const Profile({required this.fullName, required this.phone, required this.notify});

  final String fullName;
  final String phone;
  final bool notify;
}

/// Perfil propio vía Supabase con RLS (solo puede leer/editar su fila; rol y estado están protegidos).
class ProfileRepository {
  ProfileRepository(this._sb);

  final SupabaseClient _sb;

  Future<Profile> load(String userId) async {
    final r = await _sb.from('profiles').select('full_name, phone, notify_status_changes').eq('id', userId).single();
    return Profile(
      fullName: (r['full_name'] as String?) ?? '',
      phone: (r['phone'] as String?) ?? '',
      notify: (r['notify_status_changes'] as bool?) ?? false,
    );
  }

  Future<void> save(String userId, Profile p) => _sb.from('profiles').update({
        'full_name': p.fullName.trim().isEmpty ? null : p.fullName.trim(),
        'phone': p.phone.trim().isEmpty ? null : p.phone.trim(),
        'notify_status_changes': p.notify,
      }).eq('id', userId);
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository(Supabase.instance.client));

final profileProvider = FutureProvider.autoDispose<Profile>((ref) {
  final id = ref.watch(sessionStateProvider).userId;
  if (id == null) throw StateError('Sin sesión');
  return ref.watch(profileRepositoryProvider).load(id);
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ListView(padding: const EdgeInsets.all(16), children: [
        const ErrorBox('No se pudo cargar el perfil.'),
        TextButton(onPressed: () => ref.invalidate(profileProvider), child: const Text('Reintentar')),
      ]),
      data: (p) => _ProfileForm(initial: p),
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.initial});

  final Profile initial;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial.fullName);
  late final _phone = TextEditingController(text: widget.initial.phone);
  late bool _notify = widget.initial.notify;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final id = ref.read(sessionStateProvider).userId!;
      await ref.read(profileRepositoryProvider).save(id, Profile(fullName: _name.text, phone: _phone.text, notify: _notify));
      messenger.showSnackBar(const SnackBar(content: Text('Perfil actualizado')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('No se pudo guardar. Intente de nuevo.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(sessionStateProvider).email ?? '';
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(email),
            subtitle: const Text('Cuenta ciudadana'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nombre completo', border: OutlineInputBorder()),
            validator: validateName,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Teléfono (opcional)', border: OutlineInputBorder()),
            validator: validatePhone,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _notify,
            onChanged: (v) => setState(() => _notify = v),
            title: const Text('Avisarme cuando cambie el estado de mis reportes'),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : _save, child: _busy ? const ButtonSpinner() : const Text('Guardar cambios')),
        ],
      ),
    );
  }
}

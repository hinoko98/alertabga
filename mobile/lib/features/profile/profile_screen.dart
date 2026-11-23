import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/presentation/auth_widgets.dart';
import '../auth/presentation/validators.dart';

class Profile {
  const Profile({required this.email, required this.fullName, required this.phone, required this.notify});

  final String email;
  final String fullName;
  final String phone;
  final bool notify;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        email: (j['email'] as String?) ?? '',
        fullName: (j['full_name'] as String?) ?? '',
        phone: (j['phone'] as String?) ?? '',
        notify: (j['notify_status_changes'] as bool?) ?? false,
      );
}

/// Perfil propio a través de la API (la cuenta vive en MongoDB; ADR 0003).
class ProfileRepository {
  ProfileRepository(this._api);

  final ApiClient _api;

  Future<Profile> load() async => Profile.fromJson(await _api.account());

  Future<Profile> save(Profile p) async => Profile.fromJson(await _api.updateAccount({
        'full_name': p.fullName.trim(),
        'phone': p.phone.trim().isEmpty ? null : p.phone.trim(),
        'notify_status_changes': p.notify,
      }));
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository(ref.watch(apiClientProvider)));

final profileProvider = FutureProvider.autoDispose<Profile>((ref) => ref.watch(profileRepositoryProvider).load());

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
      await ref
          .read(profileRepositoryProvider)
          .save(Profile(email: widget.initial.email, fullName: _name.text, phone: _phone.text, notify: _notify));
      messenger.showSnackBar(const SnackBar(content: Text('Perfil actualizado')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('No se pudo guardar. Intente de nuevo.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.initial.email;
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_repository.dart';
import 'auth_widgets.dart';

/// Se abre tras el enlace de recuperación (evento passwordRecovery de Supabase).
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).updatePassword(_password.text);
      ref.read(sessionStateProvider).finishRecovery();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contraseña actualizada')));
      context.go('/home');
    } catch (e) {
      setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Nueva contraseña',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PasswordField(controller: _password, label: 'Nueva contraseña', newPassword: true),
            const SizedBox(height: 16),
            PasswordField(
              controller: _confirm,
              label: 'Confirmar contraseña',
              newPassword: true,
              validator: (v) => v != _password.text ? 'Las contraseñas no coinciden' : null,
            ),
            if (_error != null) ErrorBox(_error!),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const ButtonSpinner() : const Text('Guardar contraseña')),
          ],
        ),
      ),
    );
  }
}

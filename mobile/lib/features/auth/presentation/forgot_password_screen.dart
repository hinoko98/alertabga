import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_repository.dart';
import 'auth_widgets.dart';
import 'validators.dart';

/// Recuperación en dos pasos: 1) correo → 2) código de 6 dígitos + contraseña nueva.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _codeSent = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_email, _code, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() => _run(() async {
        await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
        if (mounted) setState(() => _codeSent = true);
      });

  Future<void> _reset() => _run(() async {
        await ref
            .read(authRepositoryProvider)
            .resetPassword(email: _email.text, code: _code.text, newPassword: _password.text);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contraseña actualizada')));
        context.go('/home');
      });

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Recuperar contraseña',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_codeSent
                ? 'Si el correo está registrado, le enviamos un código de 6 dígitos. Vence en 15 minutos.'
                : 'Ingrese el correo de su cuenta y le enviaremos un código para crear una contraseña nueva.'),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              enabled: !_codeSent,
              decoration: const InputDecoration(labelText: 'Correo electrónico', prefixIcon: Icon(Icons.email_outlined)),
              keyboardType: TextInputType.emailAddress,
              validator: validateEmail,
            ),
            if (_codeSent) ...[
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('codigo'),
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'Código de 6 dígitos', prefixIcon: Icon(Icons.pin_outlined)),
                validator: (v) => RegExp(r'^\d{6}$').hasMatch((v ?? '').trim()) ? null : 'Ingrese los 6 dígitos',
              ),
              const SizedBox(height: 8),
              PasswordField(controller: _password, label: 'Nueva contraseña', newPassword: true),
              const SizedBox(height: 16),
              PasswordField(
                controller: _confirm,
                label: 'Confirmar contraseña',
                newPassword: true,
                validator: (v) => v != _password.text ? 'Las contraseñas no coinciden' : null,
              ),
            ],
            if (_error != null) ErrorBox(_error!),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : (_codeSent ? _reset : _sendCode),
              child: _busy ? const ButtonSpinner() : Text(_codeSent ? 'Cambiar contraseña' : 'Enviar código'),
            ),
            if (_codeSent)
              TextButton(
                onPressed: _busy ? null : () => setState(() => _codeSent = false),
                child: const Text('Usar otro correo o reenviar el código'),
              ),
          ],
        ),
      ),
    );
  }
}

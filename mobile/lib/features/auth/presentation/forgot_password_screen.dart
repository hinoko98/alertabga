import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import 'auth_widgets.dart';
import 'validators.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
      setState(() => _sent = true);
    } catch (e) {
      setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Recuperar contraseña',
      child: _sent
          // Mismo mensaje exista o no la cuenta: no se revela qué correos están registrados.
          ? const InfoBox('Si el correo está registrado, recibirá un enlace para crear una contraseña nueva. '
              'Ábralo desde este teléfono.', icon: Icons.mark_email_read_outlined)
          : Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Ingrese el correo de su cuenta y le enviaremos un enlace de recuperación.'),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Correo electrónico', prefixIcon: Icon(Icons.email_outlined)),
                    keyboardType: TextInputType.emailAddress,
                    validator: validateEmail,
                  ),
                  if (_error != null) ErrorBox(_error!),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const ButtonSpinner() : const Text('Enviar enlace')),
                ],
              ),
            ),
    );
  }
}

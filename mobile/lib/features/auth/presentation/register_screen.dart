import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_repository.dart';
import 'auth_widgets.dart';
import 'validators.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _accepted = false;
  bool _busy = false;
  String? _error;
  bool _checkEmail = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (!_accepted) {
      setState(() => _error = 'Debe aceptar el tratamiento de datos personales.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final signedIn = await ref
          .read(authRepositoryProvider)
          .signUp(email: _email.text, password: _password.text, fullName: _name.text);
      if (!mounted) return;
      if (signedIn) {
        context.go('/home');
      } else {
        setState(() => _checkEmail = true);
      }
    } catch (e) {
      setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkEmail) {
      return const AuthScaffold(
        title: 'Crear cuenta',
        child: InfoBox('Le enviamos un correo para confirmar su cuenta. Abra el enlace desde este teléfono.',
            icon: Icons.mark_email_read_outlined),
      );
    }
    return AuthScaffold(
      title: 'Crear cuenta',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nombre completo', prefixIcon: Icon(Icons.person_outline)),
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              validator: validateName,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Correo electrónico', prefixIcon: Icon(Icons.email_outlined)),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              validator: validateEmail,
            ),
            const SizedBox(height: 16),
            PasswordField(controller: _password, newPassword: true),
            const SizedBox(height: 16),
            PasswordField(
              controller: _confirm,
              label: 'Confirmar contraseña',
              newPassword: true,
              validator: (v) => v != _password.text ? 'Las contraseñas no coinciden' : null,
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _accepted,
              onChanged: (v) => setState(() => _accepted = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Autorizo el tratamiento de mis datos personales para gestionar mis reportes (Ley 1581 de 2012).'),
            ),
            if (_error != null) ErrorBox(_error!),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const ButtonSpinner() : const Text('Crear cuenta')),
          ],
        ),
      ),
    );
  }
}

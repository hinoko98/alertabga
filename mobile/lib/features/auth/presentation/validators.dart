final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

String? validateEmail(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return 'Ingrese su correo';
  if (!_emailRe.hasMatch(s)) return 'Correo no válido';
  return null;
}

String? validatePassword(String? v) {
  final s = v ?? '';
  if (s.isEmpty) return 'Ingrese una contraseña';
  if (s.length < 8) return 'Mínimo 8 caracteres';
  if (s.length > 72) return 'Máximo 72 caracteres';
  return null;
}

String? validateName(String? v) {
  final s = (v ?? '').trim();
  if (s.length < 3) return 'Ingrese su nombre';
  if (s.length > 120) return 'Máximo 120 caracteres';
  return null;
}

String? validatePhone(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return null;
  if (!RegExp(r'^\+?[0-9 ]{7,20}$').hasMatch(s)) return 'Teléfono no válido';
  return null;
}

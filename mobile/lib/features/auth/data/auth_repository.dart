import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const authRedirectUrl = 'co.gov.alertabga://login-callback';

/// Traduce errores de Supabase Auth a mensajes en español (sin revelar si un correo existe).
String authErrorMessage(Object e) {
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login credentials')) return 'Correo o contraseña incorrectos.';
    if (m.contains('email not confirmed')) return 'Debe confirmar su correo antes de ingresar.';
    if (m.contains('already registered') || m.contains('already been registered')) {
      return 'No fue posible crear la cuenta con ese correo.';
    }
    if (m.contains('password')) return 'La contraseña no cumple los requisitos (mínimo 8 caracteres).';
    if (e.statusCode == '429' || m.contains('rate limit')) return 'Demasiados intentos. Espere unos minutos.';
    return 'No fue posible completar la operación. Intente de nuevo.';
  }
  return 'Sin conexión. Revise su internet e intente de nuevo.';
}

class AuthRepository {
  AuthRepository(this._auth);

  final GoTrueClient _auth;

  Session? get session => _auth.currentSession;
  User? get user => _auth.currentUser;
  Stream<AuthState> get changes => _auth.onAuthStateChange;

  Future<void> signIn(String email, String password) =>
      _auth.signInWithPassword(email: email.trim(), password: password);

  /// Devuelve true si la cuenta quedó con sesión (sin confirmación de correo pendiente).
  Future<bool> signUp({required String email, required String password, required String fullName}) async {
    final res = await _auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': fullName.trim()},
      emailRedirectTo: authRedirectUrl,
    );
    return res.session != null;
  }

  Future<void> sendPasswordReset(String email) => _auth.resetPasswordForEmail(email.trim(), redirectTo: authRedirectUrl);

  Future<void> updatePassword(String password) => _auth.updateUser(UserAttributes(password: password));

  Future<void> signOut() => _auth.signOut();
}

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(Supabase.instance.client.auth));

/// Sesión actual como estado observable; también avisa al router cuando cambia.
class SessionState extends ChangeNotifier {
  SessionState(this._repo) {
    _session = _repo.session;
    _sub = _repo.changes.listen((s) {
      _session = s.session;
      if (s.event == AuthChangeEvent.passwordRecovery) recovering = true;
      if (s.event == AuthChangeEvent.signedOut) recovering = false;
      notifyListeners();
    });
  }

  final AuthRepository _repo;
  late final StreamSubscription<AuthState> _sub;
  Session? _session;

  /// El usuario abrió el enlace de recuperación: debe definir una contraseña nueva.
  bool recovering = false;

  bool get signedIn => _session != null;
  String? get userId => _session?.user.id;
  String? get email => _session?.user.email;

  void finishRecovery() {
    recovering = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final sessionStateProvider = Provider<SessionState>((ref) {
  final s = SessionState(ref.watch(authRepositoryProvider));
  ref.onDispose(s.dispose);
  return s;
});

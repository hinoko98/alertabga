import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_store.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';

/// Mensaje en español para errores de cuenta (la API ya responde con mensajes genéricos).
String authErrorMessage(Object e) => ApiError.from(e).message;

class AuthRepository {
  AuthRepository(this._api, this._session);

  final ApiClient _api;
  final SessionStore _session;

  Future<void> signIn(String email, String password) async =>
      _session.save(await _api.login(email.trim(), password));

  Future<void> signUp({required String email, required String password, required String fullName}) async =>
      _session.save(await _api.register(email.trim(), password, fullName.trim()));

  Future<void> sendPasswordReset(String email) => _api.forgotPassword(email.trim());

  Future<void> resetPassword({required String email, required String code, required String newPassword}) async =>
      _session.save(await _api.resetPassword(email.trim(), code.trim(), newPassword));

  Future<void> signOut() async {
    final refresh = _session.refreshToken;
    await _session.clear();
    if (refresh != null) {
      try {
        await _api.logout(refresh);
      } catch (_) {
        // Sin red la sesión igual queda cerrada en el teléfono; el refresh vence solo.
      }
    }
  }
}

final authRepositoryProvider =
    Provider<AuthRepository>((ref) => AuthRepository(ref.watch(apiClientProvider), ref.watch(sessionStoreProvider)));

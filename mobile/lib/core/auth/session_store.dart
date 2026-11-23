import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_store.dart';

/// Sesión de la app ciudadana emitida por la API AlertaBGA (no Supabase; ver ADR 0003).
/// Los tokens se guardan cifrados en el dispositivo.
class SessionStore extends ChangeNotifier {
  SessionStore(this._kv);

  static const _key = 'session_v1';
  final KeyValueStore _kv;

  String? _access;
  String? _refresh;

  String? get accessToken => _access;
  String? get refreshToken => _refresh;
  bool get signedIn => _refresh != null;

  /// `sub` del JWT de acceso (solo lectura local; la API valida la firma).
  String? get userId {
    final parts = _access?.split('.');
    if (parts == null || parts.length != 3) return null;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      return (payload as Map)['sub'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> load() async {
    final raw = await _kv.read(_key);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _access = j['access_token'] as String?;
      _refresh = j['refresh_token'] as String?;
    } catch (_) {
      await _kv.delete(_key);
    }
  }

  Future<void> save(Map<String, dynamic> tokens) async {
    _access = tokens['access_token'] as String?;
    _refresh = tokens['refresh_token'] as String?;
    await _kv.write(_key, jsonEncode({'access_token': _access, 'refresh_token': _refresh}));
    notifyListeners();
  }

  Future<void> clear() async {
    final had = signedIn;
    _access = null;
    _refresh = null;
    await _kv.delete(_key);
    if (had) notifyListeners();
  }
}

/// Se sustituye en `main` con la instancia ya cargada desde el almacenamiento seguro.
final sessionStoreProvider = Provider<SessionStore>((ref) {
  final s = SessionStore(ref.watch(keyValueStoreProvider));
  ref.onDispose(s.dispose);
  return s;
});

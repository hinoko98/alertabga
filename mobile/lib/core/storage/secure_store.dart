import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Almacén clave-valor cifrado del dispositivo (Keystore en Android).
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureKeyValueStore implements KeyValueStore {
  const SecureKeyValueStore([this._s = const FlutterSecureStorage()]);

  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);

  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}

final keyValueStoreProvider = Provider<KeyValueStore>((ref) => const SecureKeyValueStore());

/// Reporte anónimo guardado en el teléfono para poder consultarlo después.
class SavedAnonymousReport {
  const SavedAnonymousReport({required this.radicado, required this.token, required this.createdAt});

  final String radicado;
  final String token;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {'radicado': radicado, 'token': token, 'created_at': createdAt.toIso8601String()};

  factory SavedAnonymousReport.fromJson(Map<String, dynamic> j) => SavedAnonymousReport(
        radicado: j['radicado'] as String,
        token: j['token'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

class AnonymousReportsStore {
  AnonymousReportsStore(this._kv);

  static const _key = 'anonymous_reports_v1';
  final KeyValueStore _kv;

  Future<List<SavedAnonymousReport>> list() async {
    final raw = await _kv.read(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final items = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return items.map(SavedAnonymousReport.fromJson).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } on FormatException {
      return [];
    }
  }

  Future<void> add(SavedAnonymousReport r) async {
    final items = [...(await list()).where((e) => e.radicado != r.radicado), r];
    await _kv.write(_key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  Future<void> remove(String radicado) async {
    final items = (await list()).where((e) => e.radicado != radicado).toList();
    await _kv.write(_key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  Future<void> clear() => _kv.delete(_key);
}

final anonymousReportsStoreProvider =
    Provider<AnonymousReportsStore>((ref) => AnonymousReportsStore(ref.watch(keyValueStoreProvider)));

final savedAnonymousReportsProvider = FutureProvider.autoDispose<List<SavedAnonymousReport>>(
    (ref) => ref.watch(anonymousReportsStoreProvider).list());

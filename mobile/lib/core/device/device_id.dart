import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_store.dart';

/// Identificador aleatorio de esta instalación (no del hardware). Solo sirve para el control
/// de abuso por dispositivo en reportes anónimos; no identifica a la persona.
class DeviceId {
  DeviceId(this._kv);

  static const _key = 'device_id_v1';
  final KeyValueStore _kv;
  String? _cached;

  Future<String> get() async {
    if (_cached != null) return _cached!;
    var id = await _kv.read(_key);
    if (id == null || id.length < 16) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await _kv.write(_key, id);
    }
    return _cached = id;
  }
}

final deviceIdProvider = Provider<DeviceId>((ref) => DeviceId(ref.watch(keyValueStoreProvider)));

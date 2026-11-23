import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/auth/session_store.dart';
import 'core/config/env.dart';
import 'core/storage/secure_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_CO');

  final missing = Env.missing();
  if (missing.isNotEmpty) {
    runApp(MissingConfigApp(missing: missing));
    return;
  }

  // La sesión se carga antes de construir el router para no mostrar la bienvenida a quien ya ingresó.
  final session = SessionStore(const SecureKeyValueStore());
  await session.load();
  runApp(ProviderScope(
    overrides: [sessionStoreProvider.overrideWithValue(session)],
    child: const AlertaBgaApp(),
  ));
}

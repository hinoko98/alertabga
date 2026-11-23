import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_CO');

  final missing = Env.missing();
  if (missing.isNotEmpty) {
    runApp(MissingConfigApp(missing: missing));
    return;
  }

  // PKCE: el enlace de recuperación/confirmación vuelve a la app por co.gov.alertabga://login-callback
  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  runApp(const ProviderScope(child: AlertaBgaApp()));
}

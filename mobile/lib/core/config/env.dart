/// Configuración inyectada en compilación con `--dart-define-from-file=env.json`.
/// La app solo recibe valores públicos: nunca service role ni claves de R2.
class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Claves obligatorias que faltan (vacío = configuración completa).
  static List<String> missing({
    String url = supabaseUrl,
    String anonKey = supabaseAnonKey,
    String api = apiBaseUrl,
  }) =>
      [
        if (url.isEmpty) 'SUPABASE_URL',
        if (anonKey.isEmpty) 'SUPABASE_ANON_KEY',
        if (api.isEmpty) 'API_BASE_URL',
      ];
}

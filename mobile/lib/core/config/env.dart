/// Configuración inyectada en compilación con `--dart-define-from-file=env.json`.
/// La app solo conoce la URL pública de la API AlertaBGA: nunca claves de bases de datos (ADR 0003).
class Env {
  const Env._();

  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Claves obligatorias que faltan (vacío = configuración completa).
  static List<String> missing({String api = apiBaseUrl}) => [if (api.isEmpty) 'API_BASE_URL'];
}

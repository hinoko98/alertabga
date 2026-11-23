import 'package:flutter/foundation.dart' show kReleaseMode;

/// Configuración de la app. La app solo conoce la URL pública de la API AlertaBGA: nunca claves de
/// bases de datos (ADR 0003).
///
/// En desarrollo basta `flutter run`: por defecto usa la API local vista desde el emulador Android
/// (10.0.2.2 = el PC). Para otro destino (teléfono físico, servidor de pruebas, producción):
/// `flutter run --dart-define=API_BASE_URL=https://...`. En release la URL es obligatoria.
class Env {
  const Env._();

  static const localEmulatorApi = 'http://10.0.2.2:8000/api/py';

  static const apiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: kReleaseMode ? '' : localEmulatorApi);

  /// Claves obligatorias que faltan (vacío = configuración completa).
  static List<String> missing({String api = apiBaseUrl}) => [if (api.isEmpty) 'API_BASE_URL'];
}

import 'package:dio/dio.dart';

/// Error de la API convertido en un mensaje en español apto para mostrar al ciudadano.
class ApiError implements Exception {
  const ApiError(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isNotFound => statusCode == 404;
  bool get isRateLimited => statusCode == 429;

  factory ApiError.from(Object error) {
    if (error is ApiError) return error;
    if (error is DioException) {
      final code = error.response?.statusCode;
      final detail = _detail(error.response?.data);
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.connectionError:
          return const ApiError('No hay conexión con el servidor. Revise su internet e intente de nuevo.');
        default:
          break;
      }
      if (code == 401) return const ApiError('Su sesión venció. Ingrese de nuevo.', statusCode: 401);
      if (code == 429) {
        return ApiError(detail ?? 'Demasiadas solicitudes. Intente más tarde.', statusCode: 429);
      }
      if (code != null && code >= 500) {
        return ApiError('El servicio no está disponible en este momento.', statusCode: code);
      }
      return ApiError(detail ?? 'No se pudo completar la solicitud.', statusCode: code);
    }
    return const ApiError('Ocurrió un error inesperado.');
  }

  static String? _detail(Object? data) {
    if (data is Map && data['detail'] is String) return data['detail'] as String;
    if (data is Map && data['detail'] is List) return 'Revise los datos ingresados.';
    return null;
  }

  @override
  String toString() => message;
}

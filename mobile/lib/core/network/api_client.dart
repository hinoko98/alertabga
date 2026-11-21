import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

/// Cliente HTTP hacia FastAPI. Adjunta el JWT de Supabase cuando hay sesión.
class ApiClient {
  ApiClient(this._dio);

  factory ApiClient.create({String baseUrl = Env.apiBaseUrl}) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    }));
    return ApiClient(dio);
  }

  final Dio _dio;

  Future<Map<String, dynamic>> health() async {
    final res = await _dio.get<Map<String, dynamic>>('/health');
    return res.data ?? const {};
  }
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient.create());

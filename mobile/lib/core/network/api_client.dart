import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../config/env.dart';
import '../device/device_id.dart';
import '../domain/report_models.dart';
import 'api_error.dart';

/// Cliente HTTP hacia FastAPI. Adjunta el JWT de Supabase cuando hay sesión y el identificador
/// de instalación (control de abuso de reportes anónimos).
class ApiClient {
  ApiClient(this._dio, {Dio? uploadDio}) : _upload = uploadDio ?? Dio();

  factory ApiClient.create({String baseUrl = Env.apiBaseUrl, DeviceId? deviceId}) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token != null && options.extra['anonymous'] != true) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      if (deviceId != null) options.headers['X-Device-Id'] = await deviceId.get();
      handler.next(options);
    }));
    // Cliente aparte para el almacenamiento: sin Authorization (rompería la firma S3).
    final upload = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 90),
      receiveTimeout: const Duration(seconds: 30),
    ));
    return ApiClient(dio, uploadDio: upload);
  }

  final Dio _dio;
  final Dio _upload;

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  Future<Map<String, dynamic>> health() => _guard(() async {
        final res = await _dio.get<Map<String, dynamic>>('/health');
        return res.data ?? const {};
      });

  Future<List<Category>> categories() => _guard(() async {
        final res = await _dio.get<List<dynamic>>('/categories');
        return [for (final c in res.data ?? const []) Category.fromJson(c as Map<String, dynamic>)];
      });

  /// Crea el reporte. `anonymous` envía sin JWT aunque haya sesión.
  Future<ReportCreated> createReport(Map<String, dynamic> body, {required bool anonymous}) => _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          anonymous ? '/reports/anonymous' : '/reports',
          data: body,
          options: Options(extra: {'anonymous': anonymous}),
        );
        return ReportCreated.fromJson(res.data!);
      });

  Future<List<ReportSummary>> myReports() => _guard(() async {
        final res = await _dio.get<List<dynamic>>('/reports/mine');
        return [for (final r in res.data ?? const []) ReportSummary.fromJson(r as Map<String, dynamic>)];
      });

  Future<ReportDetail> reportDetail(String radicado) => _guard(() async {
        final res = await _dio.get<Map<String, dynamic>>('/reports/${Uri.encodeComponent(radicado)}');
        return ReportDetail.fromJson(res.data!);
      });

  Future<ReportDetail> track(String radicado, String token) => _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>('/reports/track',
            data: {'radicado': radicado, 'token': token}, options: Options(extra: {'anonymous': true}));
        return ReportDetail.fromJson(res.data!);
      });

  Future<PresignedUpload> presignEvidence({
    required String radicado,
    required String mime,
    required int size,
    String? trackingToken,
  }) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/evidence/presign',
          data: {'radicado': radicado, 'mime': mime, 'size': size, 'tracking_token': ?trackingToken},
          options: Options(extra: {'anonymous': trackingToken != null}),
        );
        return PresignedUpload.fromJson(res.data!);
      });

  Future<void> uploadEvidence(PresignedUpload p, Uint8List bytes) => _guard(() async {
        await _upload.put<void>(
          p.uploadUrl,
          data: Stream.fromIterable([bytes]),
          options: Options(headers: {...p.headers, Headers.contentLengthHeader: bytes.length}),
        );
      });

  Future<String> confirmEvidence(String evidenceId, {required String radicado, String? trackingToken}) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/evidence/$evidenceId/confirm',
          data: {'radicado': radicado, 'tracking_token': ?trackingToken},
          options: Options(extra: {'anonymous': trackingToken != null}),
        );
        return res.data!['status'] as String;
      });
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient.create(deviceId: ref.watch(deviceIdProvider)));

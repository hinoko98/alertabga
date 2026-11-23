import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_store.dart';
import '../config/env.dart';
import '../device/device_id.dart';
import '../domain/report_models.dart';
import 'api_error.dart';

/// Cliente HTTP hacia la API AlertaBGA (única puerta de la app: ADR 0003).
/// Adjunta el token de sesión, lo renueva una vez ante un 401 y envía el identificador de instalación.
class ApiClient {
  ApiClient(this._dio, {Dio? uploadDio, Dio? rawDio, this.session})
      : _upload = uploadDio ?? Dio(),
        _raw = rawDio ?? Dio(_dio.options);

  factory ApiClient.create({String baseUrl = Env.apiBaseUrl, DeviceId? deviceId, SessionStore? session}) {
    final options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    );
    final dio = Dio(options);
    final upload = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 90),
      receiveTimeout: const Duration(seconds: 30),
    ));
    final client = ApiClient(dio, uploadDio: upload, rawDio: Dio(options), session: session);
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (o, h) async {
        final token = session?.accessToken;
        if (token != null && o.extra['anonymous'] != true) o.headers['Authorization'] = 'Bearer $token';
        if (deviceId != null) o.headers['X-Device-Id'] = await deviceId.get();
        h.next(o);
      },
      onError: (e, h) async {
        final o = e.requestOptions;
        final retriable = e.response?.statusCode == 401 &&
            o.headers.containsKey('Authorization') &&
            o.extra['retried'] != true &&
            session?.refreshToken != null;
        if (!retriable) return h.next(e);
        if (!await client._refreshSession()) return h.next(e);
        o.extra['retried'] = true;
        o.headers['Authorization'] = 'Bearer ${session!.accessToken}';
        try {
          h.resolve(await dio.fetch<dynamic>(o));
        } on DioException catch (err) {
          h.next(err);
        }
      },
    ));
    return client;
  }

  final Dio _dio;
  final Dio _upload;
  final Dio _raw;
  final SessionStore? session;
  Future<bool>? _refreshing;

  /// Sustituye el transporte HTTP de la API (pruebas).
  @visibleForTesting
  void setHttpAdapter(HttpClientAdapter adapter) {
    _dio.httpClientAdapter = adapter;
    _raw.httpClientAdapter = adapter;
  }

  /// Una sola renovación a la vez aunque fallen varias solicitudes en paralelo.
  Future<bool> _refreshSession() => _refreshing ??= () async {
        try {
          final res = await _raw.post<Map<String, dynamic>>('/auth/refresh',
              data: {'refresh_token': session!.refreshToken});
          await session!.save(res.data!);
          return true;
        } catch (_) {
          await session!.clear(); // sesión vencida: vuelve a la bienvenida
          return false;
        } finally {
          _refreshing = null;
        }
      }();

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  // ------------------------------------------------------------ sistema
  Future<Map<String, dynamic>> health() => _guard(() async {
        final res = await _dio.get<Map<String, dynamic>>('/health');
        return res.data ?? const {};
      });

  // ------------------------------------------------------------ cuenta ciudadana
  Future<Map<String, dynamic>> register(String email, String password, String fullName) => _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>('/auth/register',
            data: {'email': email, 'password': password, 'full_name': fullName},
            options: Options(extra: {'anonymous': true}));
        return res.data!;
      });

  Future<Map<String, dynamic>> login(String email, String password) => _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>('/auth/login',
            data: {'email': email, 'password': password}, options: Options(extra: {'anonymous': true}));
        return res.data!;
      });

  Future<void> logout(String refreshToken) => _guard(() async {
        await _dio.post<void>('/auth/logout',
            data: {'refresh_token': refreshToken}, options: Options(extra: {'anonymous': true}));
      });

  Future<void> forgotPassword(String email) => _guard(() async {
        await _dio.post<void>('/auth/password/forgot', data: {'email': email}, options: Options(extra: {'anonymous': true}));
      });

  Future<Map<String, dynamic>> resetPassword(String email, String code, String newPassword) => _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>('/auth/password/reset',
            data: {'email': email, 'code': code, 'new_password': newPassword},
            options: Options(extra: {'anonymous': true}));
        return res.data!;
      });

  Future<Map<String, dynamic>> account() => _guard(() async {
        final res = await _dio.get<Map<String, dynamic>>('/account');
        return res.data!;
      });

  Future<Map<String, dynamic>> updateAccount(Map<String, dynamic> values) => _guard(() async {
        final res = await _dio.patch<Map<String, dynamic>>('/account', data: values);
        return res.data!;
      });

  Future<void> changePassword(String current, String newPassword) => _guard(() async {
        await _dio.post<void>('/account/password', data: {'current_password': current, 'new_password': newPassword});
      });

  // ------------------------------------------------------------ reportes
  Future<List<Category>> categories() => _guard(() async {
        final res = await _dio.get<List<dynamic>>('/categories');
        return [for (final c in res.data ?? const []) Category.fromJson(c as Map<String, dynamic>)];
      });

  /// Crea el reporte. `anonymous` envía sin token aunque haya sesión.
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

  // ------------------------------------------------------------ evidencias
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

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient.create(
      deviceId: ref.watch(deviceIdProvider),
      session: ref.watch(sessionStoreProvider),
    ));

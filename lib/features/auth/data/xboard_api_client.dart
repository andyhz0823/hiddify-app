import 'package:dio/dio.dart';
import 'package:hiddify/utils/custom_loggers.dart';

class XboardApiClient with InfraLogger {
  final Dio _dio;

  XboardApiClient({required String baseUrl}) : _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl.replaceAll(RegExp(r'/+$'), ''),
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent': 'kuaifei',
        'Accept': 'application/json',
      },
    ),
  );

  void setToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  void clearToken() {
    _dio.options.headers.remove('Authorization');
  }

  /// POST /api/v1/passport/auth/login
  /// Returns { token, auth_data, is_admin }
  Future<XboardLoginResult> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post(
      '/api/v1/passport/auth/login',
      data: {'email': email, 'password': password},
    );

    final body = response.data;
    if (body == null || body['status'] != 'success') {
      throw XboardApiException(
        body?['message']?.toString() ?? '登录失败，请检查账号密码',
      );
    }

    final data = body['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw XboardApiException('登录返回数据异常');
    }

    final subscriptionToken = data['token']?.toString();
    final authData = data['auth_data']?.toString();

    if (subscriptionToken == null || authData == null) {
      throw XboardApiException('登录返回数据不完整');
    }

    // auth_data format is "Bearer <token>"
    final sanctumToken = authData.startsWith('Bearer ')
        ? authData.substring(7)
        : authData;

    return XboardLoginResult(
      subscriptionToken: subscriptionToken,
      sanctumToken: sanctumToken,
      isAdmin: data['is_admin'] as bool? ?? false,
    );
  }

  /// GET /api/v1/user/getSubscribe
  /// Requires Bearer token set via [setToken]
  Future<XboardSubscribeResult> getSubscribe() async {
    final response = await _dio.get('/api/v1/user/getSubscribe');

    final body = response.data;
    if (body == null || body['status'] != 'success') {
      throw XboardApiException(
        body?['message']?.toString() ?? '获取订阅信息失败',
      );
    }

    final data = body['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw XboardApiException('订阅数据异常');
    }

    return XboardSubscribeResult(
      subscribeUrl: data['subscribe_url']?.toString() ?? '',
      planId: data['plan_id'] as int?,
      expiredAt: data['expired_at']?.toString(),
      email: data['email']?.toString(),
      token: data['token']?.toString(),
    );
  }
}

class XboardLoginResult {
  final String subscriptionToken;
  final String sanctumToken;
  final bool isAdmin;

  XboardLoginResult({
    required this.subscriptionToken,
    required this.sanctumToken,
    required this.isAdmin,
  });
}

class XboardSubscribeResult {
  final String subscribeUrl;
  final int? planId;
  final String? expiredAt;
  final String? email;
  final String? token;

  XboardSubscribeResult({
    required this.subscribeUrl,
    this.planId,
    this.expiredAt,
    this.email,
    this.token,
  });
}

class XboardApiException implements Exception {
  final String message;
  XboardApiException(this.message);

  @override
  String toString() => message;
}

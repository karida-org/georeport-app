import 'package:dio/dio.dart';

import '../auth/token_manager.dart';

/// How a [GttSyncClient] authenticates: Redmine API key or OAuth bearer
/// tokens. Both ride the same `accept_api_auth` server surface.
sealed class ClientAuth {
  const ClientAuth();

  void install(Dio dio);
}

class ApiKeyAuth extends ClientAuth {
  const ApiKeyAuth(this.apiKey);

  final String apiKey;

  @override
  void install(Dio dio) {
    dio.options.headers['X-Redmine-API-Key'] = apiKey;
  }
}

class OAuthAuth extends ClientAuth {
  const OAuthAuth(this.manager);

  final TokenManager manager;

  @override
  void install(Dio dio) {
    dio.interceptors.add(_BearerInterceptor(manager, dio));
  }
}

/// Sets the bearer header per request (refreshing near expiry) and retries a
/// request exactly once after a 401 by forcing a refresh, so a token expiring
/// mid-session heals invisibly. A second 401 propagates: the session needs a
/// real re-authorization.
class _BearerInterceptor extends Interceptor {
  _BearerInterceptor(this._manager, this._dio);

  static const _retried = 'georeport.auth.retried';

  final TokenManager _manager;
  final Dio _dio;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.headers['Authorization'] = 'Bearer ${await _manager.accessToken()}';
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    if (err.response?.statusCode != 401 || options.extra[_retried] == true) {
      return handler.next(err);
    }
    if (!await _manager.forceRefresh()) {
      return handler.next(err);
    }
    options.extra[_retried] = true;
    try {
      final response = await _dio.fetch<dynamic>(options);
      return handler.resolve(response);
    } on DioException catch (retryError) {
      return handler.next(retryError);
    }
  }
}

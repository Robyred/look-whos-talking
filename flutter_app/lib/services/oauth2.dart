import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'cloud_storage_provider.dart';

/// Tokens returned by an OAuth2 exchange.
class OAuthTokens {
  final String accessToken;
  final String? refreshToken;
  const OAuthTokens({required this.accessToken, this.refreshToken});
}

/// Seam over secure token persistence, so provider logic is testable headless.
abstract class TokenStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

/// Real [TokenStore] over flutter_secure_storage (Keychain/Keystore).
class SecureTokenStore implements TokenStore {
  const SecureTokenStore();
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);
  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

/// Seam over the flutter_appauth OAuth2 flow, so provider logic is testable
/// headless with a fake broker.
abstract class TokenBroker {
  /// Runs the interactive authorization-code + token exchange.
  Future<OAuthTokens> exchangeCode({
    required String clientId,
    required String redirectUrl,
    required String authorizationEndpoint,
    required String tokenEndpoint,
    required List<String> scopes,
    Map<String, String>? additionalParameters,
  });

  /// Exchanges a stored refresh token for fresh tokens.
  Future<OAuthTokens> refreshToken({
    required String clientId,
    required String redirectUrl,
    required String tokenEndpoint,
    required List<String> scopes,
    required String refreshToken,
  });
}

/// Real [TokenBroker] over flutter_appauth.
class FlutterAppAuthBroker implements TokenBroker {
  const FlutterAppAuthBroker();
  static const _appAuth = FlutterAppAuth();

  static AuthorizationServiceConfiguration _config(
    String authorizationEndpoint,
    String tokenEndpoint,
  ) =>
      AuthorizationServiceConfiguration(
        authorizationEndpoint: authorizationEndpoint,
        tokenEndpoint: tokenEndpoint,
      );

  @override
  Future<OAuthTokens> exchangeCode({
    required String clientId,
    required String redirectUrl,
    required String authorizationEndpoint,
    required String tokenEndpoint,
    required List<String> scopes,
    Map<String, String>? additionalParameters,
  }) async {
    try {
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          clientId,
          redirectUrl,
          serviceConfiguration:
              _config(authorizationEndpoint, tokenEndpoint),
          scopes: scopes,
          additionalParameters: additionalParameters,
        ),
      );
      return _toTokens(result.accessToken, result.refreshToken);
    } on FlutterAppAuthUserCancelledException {
      // User backing out of the browser is not an error — the UI treats it
      // as a quiet cancel, so surface it through [AuthException].
      throw const AuthException('Sign-in cancelled');
    }
  }

  @override
  Future<OAuthTokens> refreshToken({
    required String clientId,
    required String redirectUrl,
    required String tokenEndpoint,
    required List<String> scopes,
    required String refreshToken,
  }) async {
    final result = await _appAuth.token(
      TokenRequest(
        clientId,
        redirectUrl,
        serviceConfiguration: _config(
          // Refresh only needs the token endpoint, but the request requires
          // a service configuration — reuse the provider's endpoints.
          tokenEndpoint,
          tokenEndpoint,
        ),
        scopes: scopes,
        refreshToken: refreshToken,
      ),
    );
    return _toTokens(result.accessToken, result.refreshToken);
  }

  OAuthTokens _toTokens(String? access, String? refresh) {
    final accessToken = access;
    if (accessToken == null) {
      throw const AuthException('No access token returned');
    }
    return OAuthTokens(accessToken: accessToken, refreshToken: refresh);
  }
}

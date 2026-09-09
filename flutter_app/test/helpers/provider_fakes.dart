// Fakes for testing the OneDrive/Dropbox providers headless: an in-memory
// TokenStore and a TokenBroker that records calls instead of touching
// flutter_appauth.
import 'package:look_whos_talking/services/oauth2.dart';

class InMemoryTokenStore implements TokenStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read({required String key}) async => values[key];
  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

class FakeTokenBroker implements TokenBroker {
  FakeTokenBroker({
    this.tokens = const OAuthTokens(accessToken: 'access-1', refreshToken: 'r1'),
    this.failExchange = false,
    this.failRefresh = false,
  });

  OAuthTokens tokens;
  bool failExchange;
  bool failRefresh;

  int exchangeCount = 0;
  int refreshCount = 0;
  List<String>? lastScopes;
  Map<String, String>? lastAdditionalParameters;
  String? lastRefreshToken;

  @override
  Future<OAuthTokens> exchangeCode({
    required String clientId,
    required String redirectUrl,
    required String authorizationEndpoint,
    required String tokenEndpoint,
    required List<String> scopes,
    Map<String, String>? additionalParameters,
  }) async {
    exchangeCount++;
    lastScopes = scopes;
    lastAdditionalParameters = additionalParameters;
    if (failExchange) throw Exception('exchange failed');
    return tokens;
  }

  @override
  Future<OAuthTokens> refreshToken({
    required String clientId,
    required String redirectUrl,
    required String tokenEndpoint,
    required List<String> scopes,
    required String refreshToken,
  }) async {
    refreshCount++;
    lastScopes = scopes;
    lastRefreshToken = refreshToken;
    if (failRefresh) throw Exception('refresh failed');
    return tokens;
  }
}

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'google_drive_gateway_impl.dart';
import 'google_drive_provider.dart';

/// Real [AuthGateway] over google_sign_in 7.x.
///
/// Token persistence and refresh are handled by the platform's sign-in session
/// (iOS Keychain / Android Keystore-backed storage), which is the secure store
/// google_sign_in manages — mirroring tokens into a second store would only
/// create stale-copy bugs. Needs a device to verify the interactive flow.
class GoogleDriveAuthImpl implements AuthGateway {
  GoogleDriveAuthImpl({this.scopes = const [driveFileScope]});

  static const driveFileScope =
      'https://www.googleapis.com/auth/drive.file';

  final List<String> scopes;

  static bool _initialized = false;

  GoogleSignInAccount? _account;

  static Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await GoogleSignIn.instance.initialize();
      _initialized = true;
    }
  }

  @override
  Future<void> authenticate() async {
    await _ensureInitialized();
    _account ??= await GoogleSignIn.instance.authenticate(
      scopeHint: scopes,
    );
    // Make sure the Drive scope is actually granted, not just hinted.
    final client = _account!.authorizationClient;
    if (await client.authorizationForScopes(scopes) == null) {
      await client.authorizeScopes(scopes);
    }
  }

  @override
  Future<bool> isAuthenticated() async {
    await _ensureInitialized();
    final account = _account ??
        await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (account == null) return false;
    _account = account;
    return await account.authorizationClient.authorizationForScopes(scopes) !=
        null;
  }

  @override
  Future<void> signOut() async {
    await _ensureInitialized();
    await GoogleSignIn.instance.signOut();
    _account = null;
  }

  /// Authorization headers for the granted scopes, or null when signed out.
  Future<Map<String, String>?> headers() async {
    if (!await isAuthenticated()) return null;
    return _account!.authorizationClient.authorizationHeaders(scopes);
  }
}

/// Builds a fully-wired Google Drive provider.
///
/// The DriveApi is created over a client that injects the sign-in
/// Authorization header on every request (googleapis has no auth layer).
/// [headersProvider] lets tests substitute their own token source.
Future<GoogleDriveProvider> createGoogleDriveProvider({
  http.Client? innerClient,
  Future<Map<String, String>?> Function()? headersProvider,
  AuthGateway? auth,
}) async {
  final authGateway = auth ?? GoogleDriveAuthImpl();
  final googleAuth = authGateway is GoogleDriveAuthImpl ? authGateway : null;
  final inner = innerClient ?? http.Client();

  Future<Map<String, String>?> resolveHeaders() async {
    if (headersProvider != null) return headersProvider();
    return googleAuth?.headers();
  }

  final headersClient = AuthHeaderClient(inner, resolveHeaders);
  final driveApi = drive.DriveApi(headersClient);
  return GoogleDriveProvider(
    gateway: GoogleDriveGatewayImpl(driveApi),
    auth: authGateway,
  );
}

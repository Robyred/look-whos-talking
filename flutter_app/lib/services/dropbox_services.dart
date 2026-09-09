import 'dropbox_provider.dart';

/// Builds a Dropbox provider. No async setup needed — the stored refresh
/// token is loaded lazily on the first isAuthenticated() check.
DropboxProvider createDropboxProvider() => DropboxProvider();

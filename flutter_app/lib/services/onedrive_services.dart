import 'onedrive_provider.dart';

/// Builds a OneDrive provider. No async setup needed — the stored refresh
/// token is loaded lazily on the first isAuthenticated() check.
OneDriveProvider createOneDriveProvider() => OneDriveProvider();

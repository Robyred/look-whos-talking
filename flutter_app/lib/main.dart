import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/cloud_storage_provider.dart';
import 'services/conversation_store.dart';
import 'services/dropbox_services.dart';
import 'services/google_drive_services.dart';
import 'services/onedrive_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // One shared store + Google Drive provider drive the sync pipeline (as
  // before); OneDrive and Dropbox are connect/disconnect only for now, listed
  // on the Settings screen. They plug into sync in a later task.
  final ConversationStore store = ConversationStore();
  final google = await createGoogleDriveProvider();
  final oneDrive = createOneDriveProvider();
  final dropbox = createDropboxProvider();

  runApp(LookWhosTalkingApp(
    store: store,
    cloud: google, // primary (existing wiring)
    cloudProviders: [google, oneDrive, dropbox], // for the Settings screen
  ));
}

class LookWhosTalkingApp extends StatelessWidget {
  final ConversationStore store;
  final CloudStorageProvider cloud;
  final List<CloudStorageProvider> cloudProviders;

  const LookWhosTalkingApp({
    super.key,
    required this.store,
    required this.cloud,
    this.cloudProviders = const [],
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Look Who\'s Talking',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        cardTheme: const CardThemeData(elevation: 1),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      home: HomeScreen(
        store: store,
        cloud: cloud,
        cloudProviders: cloudProviders,
      ),
    );
  }
}

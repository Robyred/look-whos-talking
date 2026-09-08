import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/cloud_storage_provider.dart';
import 'services/conversation_store.dart';
import 'services/google_drive_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // One shared store + cloud provider for the whole app: ProcessingScreen
  // saves into the same store the History screen reads, and both sync
  // through the same Google Drive provider.
  final ConversationStore store = ConversationStore();
  final CloudStorageProvider cloud = await createGoogleDriveProvider();

  runApp(LookWhosTalkingApp(store: store, cloud: cloud));
}

class LookWhosTalkingApp extends StatelessWidget {
  final ConversationStore store;
  final CloudStorageProvider cloud;

  const LookWhosTalkingApp({
    super.key,
    required this.store,
    required this.cloud,
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
      home: HomeScreen(store: store, cloud: cloud),
    );
  }
}

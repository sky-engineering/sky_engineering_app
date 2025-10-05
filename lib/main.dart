// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'src/app/shell.dart';
import 'src/integrations/dropbox/dropbox_page.dart';
import 'src/pages/auth_page.dart';
import 'src/theme/app_theme.dart';

Future<void> _configureFirestorePersistence() async {
  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
  } catch (e) {
    // If persistence cannot be enabled (e.g., multiple tabs on web), fallback silently.
    // ignore: avoid_print
    print('Firestore persistence not enabled: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const SkyApp());
}

class SkyApp extends StatelessWidget {
  const SkyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sky Engineering',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      routes: {'/dropbox': (context) => DropboxPage()},
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snap.data;
        if (user == null) return const AuthPage();
        return Shell(user: user);
      },
    );
  }
}

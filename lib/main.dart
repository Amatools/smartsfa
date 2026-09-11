import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';
import 'src/features/auth/presentation/pages/firebase_auth_gate_page.dart';
import 'src/features/catalog_preview/presentation/pages/catalog_preview_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _configureFirestoreOffline();
  runApp(const SmartSfaApp());
}

Future<void> _configureFirestoreOffline() async {
  final firestore = FirebaseFirestore.instance;

  try {
    firestore.settings = const Settings(persistenceEnabled: true);
  } catch (_) {
    // Best effort: if persistence configuration fails, app still runs online.
  }
}

class SmartSfaApp extends StatelessWidget {
  const SmartSfaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final previewMode = kIsWeb && Uri.base.queryParameters['preview'] == 'catalogs';

    return MaterialApp(
      title: 'SmartSFA',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B5D4B)),
        useMaterial3: true,
      ),
      home: previewMode
          ? const CatalogPreviewPage()
          : kIsWeb
              ? const FirebaseAuthGatePage()
              : const SplashFlowPage(),
    );
  }
}

class SplashFlowPage extends StatefulWidget {
  const SplashFlowPage({super.key});

  @override
  State<SplashFlowPage> createState() => _SplashFlowPageState();
}

class _SplashFlowPageState extends State<SplashFlowPage> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _ready = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return const FirebaseAuthGatePage();
    }

    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.android,
                      size: 88,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Smart SFA',
                      style: textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Forca de Vendas Smart',
                      style: textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Inicializando autenticacao segura',
                      style: textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: CircularProgressIndicator(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

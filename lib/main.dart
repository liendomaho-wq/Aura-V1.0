import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'infrastructure/security/aura_dynamic_whitelist.dart';
import 'providers/aura_state_provider.dart';
import 'screens/splash_screen.dart';
import 'theme/aura_tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await AuraDynamicWhitelist.instance.initialize();
  } on Object catch (error, stackTrace) {
    developer.log(
      'No se pudo sincronizar la allowlist dinámica con el firewall nativo; '
      'se conserva la lista cargada en Dart y permanece activa la estática.',
      name: 'AuraDynamicWhitelist',
      error: error,
      stackTrace: stackTrace,
      level: 1000,
    );
  }
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuraStateProvider()),
      ],
      child: const AuraApp(),
    ),
  );
}

class AuraApp extends StatelessWidget {
  const AuraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aura Mobile Defens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AuraTokens.bg,
        fontFamily: 'sans-serif',
      ),
      home: const SplashScreen(),
    );
  }
}
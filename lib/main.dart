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
      providers: [ChangeNotifierProvider(create: (_) => AuraStateProvider())],
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
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AuraTokens.bg,
        fontFamily: 'sans-serif',
        colorScheme: const ColorScheme.dark(
          primary: AuraTokens.accent,
          secondary: AuraTokens.accentViolet,
          surface: AuraTokens.surface,
          error: AuraTokens.danger,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AuraTokens.bg,
          foregroundColor: AuraTokens.textPrimary,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AuraTokens.surface,
          hintStyle: const TextStyle(color: AuraTokens.textMuted),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(AuraTokens.rXl)),
            borderSide: BorderSide(color: AuraTokens.border),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(AuraTokens.rXl)),
            borderSide: BorderSide(color: AuraTokens.accent, width: 1.4),
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'agent/agent_controller.dart';
import 'infrastructure/security/aura_dynamic_whitelist.dart';
import 'llm/aura_llm_model_source.dart';
import 'llm/aura_llm_setup_controller.dart';
import 'llm/local_llm_planner.dart';
import 'providers/aura_state_provider.dart';
import 'screens/splash_screen.dart';
import 'theme/aura_tokens.dart';
import 'widgets/aura_llm_setup_scope.dart';

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
  final modelSource = AuraLlmModelSource.fromEnvironment();
  final planner = LocalLlmPlanner(
    contextTokens: modelSource.runtimeContextTokens,
    modelSizeBytes: modelSource.sizeBytes,
  );
  AgentController.instance.bindLocalLlmPlanner(planner);
  final llmSetup = AuraLlmSetupController(
    source: modelSource,
    warmUp: planner.prefetchModel,
    unload: planner.unloadModel,
  );
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AuraStateProvider())],
      child: AuraLlmSetupScope(controller: llmSetup, child: const AuraApp()),
    ),
  );
  unawaited(llmSetup.initialize());
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

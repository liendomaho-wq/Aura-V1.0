import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../agent/agent_controller.dart';
import '../ai_brain.dart';
import '../secure_vault.dart';
import '../theme/aura_tokens.dart';
import '../widgets/aura_avatar.dart';
import 'aura_core_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final AuraSecureVault _secureVault;
  late final AuraAIBrain _aiBrain;
  double _loadingProgress = 0;
  String _bootStatusText = 'INICIALIZANDO BÓVEDA SEGURA...';
  bool _isAuthFailed = false;
  bool _isAuthenticating = false;
  bool _showLockDecision = false;

  @override
  void initState() {
    super.initState();
    AuraAIBrain.onModelIntegrityFailure = (message) {
      AgentController.instance.reportCriticalError(message);
    };
    _secureVault = AuraSecureVault();
    _aiBrain = AuraAIBrain(secureVault: _secureVault);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    unawaited(_initializeSystem());
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initializeSystem() async {
    setState(() {
      _isAuthFailed = false;
      _showLockDecision = false;
      _loadingProgress = 0;
      _bootStatusText = 'VERIFICANDO BLOQUEO LOCAL...';
    });
    await _authenticateUser();
  }

  Future<void> _authenticateUser() async {
    if (_isAuthenticating) return;
    setState(() {
      _isAuthenticating = true;
      _isAuthFailed = false;
      _showLockDecision = false;
      _bootStatusText = 'VERIFICANDO BLOQUEO LOCAL...';
    });

    try {
      final status = await AgentController.instance.getLocalAuthStatus();
      final hasStrongBiometric = status['hasStrongBiometric'] == true;
      final deviceSecure = status['deviceSecure'] == true;

      if (hasStrongBiometric) {
        final authenticated =
            await AgentController.instance.authenticateBiometricDevice();
        if (!authenticated) {
          _showAuthenticationFailure('ACCESO DENEGADO - NÚCLEO BLOQUEADO.');
          return;
        }
      } else if (deviceSecure) {
        setState(() {
          _bootStatusText =
              'HUELLA NO CONFIGURADA; USANDO BLOQUEO DEL TELÉFONO...';
        });
        final authenticated =
            await AgentController.instance.authenticateDeviceCredential();
        if (!authenticated) {
          _showAuthenticationFailure('BLOQUEO DEL TELÉFONO NO CONFIRMADO.');
          return;
        }
      } else {
        setState(() {
          _showLockDecision = true;
          _bootStatusText = 'SIN BLOQUEO LOCAL CONFIGURADO.';
        });
        return;
      }

      await _runPostAuthBootSequence();
    } on PlatformException catch (error) {
      _showAuthenticationFailure(
        'ERROR DE ACCESO BIOMÉTRICO: ${error.message ?? error.code}',
      );
    } on Object catch (error) {
      _showAuthenticationFailure('ERROR DE INICIALIZACIÓN: $error');
    } finally {
      if (mounted) setState(() => _isAuthenticating = false);
    }
  }

  Future<void> _runPostAuthBootSequence() async {
    try {
      if (!mounted) return;
      setState(() {
        _isAuthenticating = true;
        _showLockDecision = false;
        _isAuthFailed = false;
        _loadingProgress = 0.35;
        _bootStatusText =
            'ACCESO LOCAL VALIDADO; INICIALIZANDO BÓVEDA SEGURA...';
      });
      await _secureVault.getOrCreateModelMasterKey();
      if (!mounted) return;
      setState(() {
        _loadingProgress = 0.55;
        _bootStatusText = 'DESCIFRANDO MODELO AES-256...';
      });
      final modelReady = await _aiBrain.preloadModel();
      if (!mounted) return;
      setState(() {
        _loadingProgress = 0.85;
        _bootStatusText = modelReady
            ? 'BOSQUE LOCAL VALIDADO: 500 ÁRBOLES.'
            : 'MODELO NO VERIFICADO; REGLAS LOCALES ACTIVAS.';
      });
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      setState(() {
        _loadingProgress = 1;
        _bootStatusText = 'AURA LISTA; EL TÚNEL VPN REQUIERE CONSENTIMIENTO.';
      });
      await Future<void>.delayed(const Duration(milliseconds: 350));
      _navigateToCore();
    } on PlatformException catch (error) {
      _showAuthenticationFailure(
        'ERROR DE ACCESO BIOMÉTRICO: ${error.message ?? error.code}',
      );
    } on Object catch (error) {
      _showAuthenticationFailure('ERROR DE INICIALIZACIÓN: $error');
    } finally {
      if (mounted) setState(() => _isAuthenticating = false);
    }
  }

  void _showAuthenticationFailure(String message) {
    if (!mounted) return;
    setState(() {
      _isAuthFailed = true;
      _showLockDecision = false;
      _bootStatusText = message;
    });
    AgentController.instance.reportError(message);
  }

  void _allowUnsecuredLocalAccess() {
    AgentController.instance.allowUnsecuredLocalSession();
    AgentController.instance.reportError(
      'Acceso sin verificación local: dispositivo sin bloqueo configurado.',
    );
    unawaited(_runPostAuthBootSequence());
  }

  Widget _buildDecisionButton({
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.08),
          foregroundColor: color,
          side: BorderSide(color: color),
          padding: const EdgeInsets.symmetric(
            horizontal: AuraTokens.s2,
            vertical: AuraTokens.s3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AuraTokens.rSm),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _navigateToCore() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const AuraCoreScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.fastOutSlowIn,
          ),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuraTokens.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.035,
              child: GridPaper(
                color: AuraTokens.accent,
                interval: 30,
                divisions: 1,
                subdivisions: 1,
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AuraTokens.s4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AuraAvatar(size: 148),
                    const SizedBox(height: AuraTokens.s8),
                    const Text(
                      'AURA',
                      style: TextStyle(
                        color: AuraTokens.textPrimary,
                        fontSize: 38,
                        fontWeight: FontWeight.w200,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: AuraTokens.s1),
                    const Text(
                      'SOVEREIGN MOBILE DEFENSE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AuraTokens.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: AuraTokens.s8),
                    SizedBox(
                      width: 280,
                      child: Column(
                        children: [
                          LinearProgressIndicator(
                            value: _loadingProgress,
                            minHeight: 2,
                            backgroundColor: AuraTokens.surfaceAlt,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _isAuthFailed
                                  ? AuraTokens.danger
                                  : AuraTokens.accent,
                            ),
                          ),
                          const SizedBox(height: AuraTokens.s3),
                          Text(
                            _bootStatusText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _isAuthFailed
                                  ? AuraTokens.danger
                                  : AuraTokens.accent,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                          if (_isAuthFailed && !_isAuthenticating) ...[
                            const SizedBox(height: AuraTokens.s2),
                            IconButton(
                              tooltip: 'REINTENTAR AUTENTICACIÓN LOCAL',
                              onPressed: _initializeSystem,
                              icon: const Icon(
                                Icons.refresh,
                                color: AuraTokens.warning,
                              ),
                            ),
                          ],
                          if (_showLockDecision && !_isAuthenticating) ...[
                            const SizedBox(height: AuraTokens.s3),
                            _buildDecisionButton(
                              label: 'CONFIGURAR BLOQUEO DEL TELÉFONO',
                              color: AuraTokens.accent,
                              onPressed: () => unawaited(
                                AgentController.instance.openSecuritySettings(),
                              ),
                            ),
                            const SizedBox(height: AuraTokens.s2),
                            _buildDecisionButton(
                              label: 'REINTENTAR',
                              color: AuraTokens.warning,
                              onPressed: _initializeSystem,
                            ),
                            const SizedBox(height: AuraTokens.s2),
                            _buildDecisionButton(
                              label: 'CONTINUAR SIN BLOQUEO LOCAL (INSEGURO)',
                              color: AuraTokens.danger,
                              onPressed: _allowUnsecuredLocalAccess,
                            ),
                            const SizedBox(height: AuraTokens.s1),
                            const Text(
                              'ALTO RIESGO: CONFIGURA UN PIN PARA PROTEGER AURA.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AuraTokens.danger,
                                fontFamily: 'monospace',
                                fontSize: 8,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

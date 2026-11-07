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
      await _secureVault.initializeModelMasterKey();
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
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.18),
                radius: 1.18,
                colors: [
                  Color(0xFF183A70),
                  Color(0xFF0A1730),
                  Color(0xFF030711),
                ],
                stops: [0, 0.48, 1],
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.09,
                child: GridPaper(
                  color: AuraTokens.accent,
                  interval: 26,
                  divisions: 1,
                  subdivisions: 1,
                ),
              ),
            ),
          ),
          Positioned(
            top: -150,
            right: -120,
            child: IgnorePointer(
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AuraTokens.accentViolet.withValues(alpha: 0.22),
                      blurRadius: 130,
                      spreadRadius: 35,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 700;
                // Compact phones need a genuinely smaller core. A 220 px
                // minimum consumed too much of a 568 px viewport before the
                // authentication choices and made the first-run screen
                // unnecessarily difficult to use.
                final coreSize = compact
                    ? (constraints.maxWidth * 0.52)
                        .clamp(148.0, 180.0)
                        .toDouble()
                    : (constraints.maxWidth * 0.72)
                        .clamp(220.0, 310.0)
                        .toDouble();
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        18,
                        compact ? 6 : 22,
                        18,
                        compact ? 8 : 24,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: AuraTokens.success,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AuraTokens.success,
                                      blurRadius: 9,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 9),
                              const Text(
                                'SISTEMA DE DEFENSA PERSONAL',
                                style: TextStyle(
                                  color: AuraTokens.textMuted,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 2.0,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: compact ? 8 : 26),
                          AuraAvatar(size: coreSize),
                          SizedBox(height: compact ? 6 : 18),
                          const Text(
                            'A U R A',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AuraTokens.textPrimary,
                              fontSize: 42,
                              height: 1.0,
                              fontWeight: FontWeight.w200,
                              letterSpacing: 7,
                              fontFamily: 'sans-serif',
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'INTELIGENCIA QUE PROTEGE',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AuraTokens.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2.8,
                            ),
                          ),
                          SizedBox(height: compact ? 10 : 28),
                          Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(maxWidth: 390),
                            padding: EdgeInsets.fromLTRB(18, compact ? 12 : 16, 18, compact ? 12 : 16),
                            decoration: BoxDecoration(
                              color: const Color(0xA6091730),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: AuraTokens.accent.withValues(alpha: 0.22),
                              ),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xCC10284A),
                                  Color(0xA609142A),
                                  Color(0xB10B1027),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AuraTokens.accentBlue.withValues(alpha: 0.12),
                                  blurRadius: 32,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'TU CENTRO DE CIBERDEFENSA',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AuraTokens.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                const Text(
                                  'Una inteligencia local para ayudarte a comprender, '
                                  'supervisar y proteger tu entorno digital.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AuraTokens.textMuted,
                                    fontSize: 11,
                                    height: 1.45,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: LinearProgressIndicator(
                                    value: _loadingProgress,
                                    minHeight: 3,
                                    backgroundColor: AuraTokens.surfaceAlt,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      _isAuthFailed
                                          ? AuraTokens.danger
                                          : AuraTokens.accent,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _bootStatusText,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _isAuthFailed
                                        ? AuraTokens.danger
                                        : AuraTokens.accent,
                                    fontSize: 9,
                                    height: 1.4,
                                    fontFamily: 'monospace',
                                    letterSpacing: 0.35,
                                  ),
                                ),
                                if (_isAuthFailed && !_isAuthenticating) ...[
                                  const SizedBox(height: 8),
                                  IconButton(
                                    tooltip: 'REINTENTAR AUTENTICACIÓN LOCAL',
                                    onPressed: _initializeSystem,
                                    icon: const Icon(
                                      Icons.refresh_rounded,
                                      color: AuraTokens.warning,
                                    ),
                                  ),
                                ],
                                if (_showLockDecision && !_isAuthenticating) ...[
                                  const SizedBox(height: 14),
                                  _buildDecisionButton(
                                    label: 'CONFIGURAR BLOQUEO DEL TELÉFONO',
                                    color: AuraTokens.accent,
                                    onPressed: () => unawaited(
                                      AgentController.instance.openSecuritySettings(),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildDecisionButton(
                                    label: 'REINTENTAR',
                                    color: AuraTokens.warning,
                                    onPressed: _initializeSystem,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildDecisionButton(
                                    label: 'CONTINUAR SIN BLOQUEO LOCAL (INSEGURO)',
                                    color: AuraTokens.danger,
                                    onPressed: _allowUnsecuredLocalAccess,
                                  ),
                                  const SizedBox(height: 8),
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
                          SizedBox(height: compact ? 8 : 22),
                          const Text(
                            'AURA QUANTUM  /  ANDROID',
                            style: TextStyle(
                              color: AuraTokens.textMuted,
                              fontSize: 8,
                              letterSpacing: 1.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

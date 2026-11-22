import 'package:flutter/material.dart';

import '../agent/agent_controller.dart';
import '../theme/aura_tokens.dart';
import '../voice_engine.dart';
import '../widgets/aura_neural_core.dart';

/// First-run introduction. It can be skipped at any step and does not replace
/// the unlock that already happened on the splash.
class AuraIntro extends StatefulWidget {
  const AuraIntro({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<AuraIntro> createState() => _AuraIntroState();
}

class _AuraIntroState extends State<AuraIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _assemble;
  int _step = 0;
  bool _spoke = false;

  static const _steps = <_IntroStep>[
    _IntroStep('AURA', 'Hola, soy Aura. Vigilo este teléfono desde aquí.'),
    _IntroStep(
      'Qué protejo',
      'El túnel local mira dominios y el nombre de los sitios cifrados. '
          'No leo el contenido de tus mensajes.',
    ),
    _IntroStep(
      'Nada sale solo',
      'Los eventos se quedan en el teléfono, salvo que actives la telemetría.',
    ),
    _IntroStep(
      'Permisos',
      'La defensa necesita el permiso VPN de Android. Las avisos usan las '
          'notificaciones. La voz usa el micrófono solo cuando tú hablas.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _assemble = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _assemble.value = 1;
      } else {
        _assemble.forward();
      }
      _speakStep();
    });
  }

  @override
  void dispose() {
    _assemble.dispose();
    super.dispose();
  }

  Future<void> _speakStep() async {
    if (_spoke || AuraVoiceEngine.muted.value) return;
    _spoke = true;
    await AgentController.instance.speakAloud(
      'Hola, soy Aura. Vigilo este teléfono desde aquí. '
      'Nada sale del dispositivo salvo que actives la telemetría.',
    );
  }

  void _next() {
    if (_step >= _steps.length - 1) {
      widget.onFinished();
      return;
    }
    setState(() => _step++);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final step = _steps[_step];
    return Material(
      color: AuraTokens.bg.withValues(alpha: 0.94),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const ValueKey<String>('aura-intro-skip'),
                  onPressed: widget.onFinished,
                  child: const Text('Saltar'),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _assemble,
                      builder: (context, _) => AuraNeuralCore(
                        state: AuraCoreVisualState.calm,
                        size: 180,
                        assemble: reduced ? 1 : _assemble.value,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      step.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AuraTokens.textPrimary,
                        fontSize: 32,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      step.body,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AuraTokens.textMuted,
                        fontSize: 15,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AuraTokens.accent,
                  foregroundColor: const Color(0xFF041018),
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _next,
                child: Text(_step == _steps.length - 1 ? 'Listo' : 'Seguir'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroStep {
  const _IntroStep(this.title, this.body);

  final String title;
  final String body;
}

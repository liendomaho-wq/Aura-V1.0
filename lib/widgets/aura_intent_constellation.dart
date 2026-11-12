import 'package:flutter/material.dart';

import '../theme/aura_tokens.dart';

/// One intent Aura can carry out. Intents are shown as connected nodes, not as
/// cards or a grid of generic shortcuts.
class AuraIntentSpec {
  const AuraIntentSpec({
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
}

class AuraIntentConstellation extends StatelessWidget {
  const AuraIntentConstellation({super.key, required this.intents});

  final List<AuraIntentSpec> intents;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          for (var i = 0; i < intents.length; i++) ...[
            if (i > 0) const _IntentLink(),
            _IntentNode(intent: intents[i]),
          ],
        ],
      ),
    );
  }
}

class _IntentNode extends StatelessWidget {
  const _IntentNode({required this.intent});

  final AuraIntentSpec intent;

  @override
  Widget build(BuildContext context) {
    final enabled = intent.onTap != null;
    final color = enabled ? intent.color : AuraTokens.textMuted;
    return TextButton(
      onPressed: intent.onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(intent.icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            intent.label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _IntentLink extends StatelessWidget {
  const _IntentLink();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 10,
            height: 1,
            color: AuraTokens.border.withValues(alpha: 0.7),
          ),
          Container(
            width: 2,
            height: 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AuraTokens.accent.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}

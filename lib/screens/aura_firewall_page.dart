import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../firewall/aura_firewall_policy.dart';
import '../secure_vault.dart';
import '../theme/aura_tokens.dart';
import '../widgets/aura_neural_core.dart';
import '../widgets/aura_neural_field.dart';

/// Per-app tunnel policy. Exclusion is not a block: Android sends that app
/// around the VPN. Allow-list mode only filters the chosen apps.
class AuraFirewallPage extends StatefulWidget {
  const AuraFirewallPage({
    super.key,
    required this.defenseActive,
    required this.commandsEnabled,
    required this.onRestartDefense,
  });

  final bool defenseActive;
  final bool commandsEnabled;
  final Future<void> Function() onRestartDefense;

  @override
  State<AuraFirewallPage> createState() => _AuraFirewallPageState();
}

class _AuraFirewallPageState extends State<AuraFirewallPage> {
  static const MethodChannel _shield = MethodChannel(
    'com.ciberdefensa.aura/shield',
  );

  final AuraSecureVault _vault = AuraSecureVault();
  AuraFirewallPolicy _policy = const AuraFirewallPolicy();
  List<({String packageName, String label})> _apps = const [];
  String? _note;
  bool _busy = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final encoded = await _vault.readFirewallPolicy();
      if (encoded != null && encoded.isNotEmpty) {
        final decoded = jsonDecode(encoded);
        if (decoded is Map) {
          _policy = AuraFirewallPolicy.parse(
            Map<String, dynamic>.from(decoded),
          );
        }
      }
    } on Object catch (error) {
      _note = 'No pude leer la política guardada: $error';
    }
    try {
      final raw = await _shield.invokeMethod<Object>('listUserApps');
      if (raw is List) {
        _apps = [
          for (final entry in raw)
            if (entry is Map && entry['package'] is String)
              (
                packageName: entry['package'] as String,
                label: entry['label'] is String
                    ? entry['label'] as String
                    : entry['package'] as String,
              ),
        ];
      }
    } on Object {
      _note ??= 'No pude leer las apps instaladas en este teléfono.';
    }
    if (mounted) setState(() => _loaded = true);
  }

  bool _selected(String packageName) => switch (_policy.mode) {
    AuraFirewallMode.normal => _policy.bypass.contains(packageName),
    AuraFirewallMode.estricto => false,
    AuraFirewallMode.paranoico => _policy.tunnelOnly.contains(packageName),
  };

  void _toggleApp(String packageName) {
    if (_policy.mode == AuraFirewallMode.estricto) return;
    final current = _policy.mode == AuraFirewallMode.paranoico
        ? List<String>.of(_policy.tunnelOnly)
        : List<String>.of(_policy.bypass);
    if (current.contains(packageName)) {
      current.remove(packageName);
    } else {
      current.add(packageName);
    }
    setState(() {
      _policy = AuraFirewallPolicy(
        mode: _policy.mode,
        bypass: _policy.mode == AuraFirewallMode.normal
            ? current
            : _policy.bypass,
        tunnelOnly: _policy.mode == AuraFirewallMode.paranoico
            ? current
            : _policy.tunnelOnly,
      );
    });
  }

  Future<void> _apply() async {
    if (!widget.commandsEnabled || _busy) return;
    try {
      _policy.decide('com.ciberdefensa.aura');
    } on FormatException catch (error) {
      setState(() => _note = error.message);
      return;
    }
    final restart = widget.defenseActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AuraTokens.surface,
        title: const Text('CONFIRMO'),
        content: Text(
          restart
              ? 'Se guardará la política y se reabrirá la defensa para aplicarla. '
                    'Habrá un momento sin túnel. ${auraFirewallModeDetail(_policy.mode)}'
              : 'Se guardará la política. Se aplicará cuando actives la defensa. '
                    '${auraFirewallModeDetail(_policy.mode)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('CONFIRMO'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _vault.writeFirewallPolicy(jsonEncode(_policy.toJson()));
      await _shield.invokeMethod<Object>('setFirewallPolicy', _policy.toJson());
      if (restart) await widget.onRestartDefense();
      if (mounted) {
        setState(
          () => _note = restart
              ? 'Política guardada. La defensa se reabrió para aplicarla.'
              : 'Política guardada. Se aplicará al activar la defensa.',
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => _note = 'No se aplicó: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuraTokens.bg,
      appBar: AppBar(title: const Text('Firewall')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AuraNeuralField(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: [
                const Center(
                  child: AuraNeuralCore(
                    state: AuraCoreVisualState.calm,
                    size: 120,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Una app fuera del túnel no está bloqueada: su internet sale directo y Aura no la ve.',
                  style: TextStyle(color: AuraTokens.textMuted, height: 1.4),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final mode in AuraFirewallMode.values)
                      ChoiceChip(
                        label: Text(auraFirewallModeTitle(mode)),
                        selected: _policy.mode == mode,
                        onSelected: (_) => setState(() {
                          _policy = AuraFirewallPolicy(
                            mode: mode,
                            bypass: _policy.bypass,
                            tunnelOnly: _policy.tunnelOnly,
                          );
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  auraFirewallModeDetail(_policy.mode),
                  style: const TextStyle(
                    color: AuraTokens.textPrimary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                if (!_loaded)
                  const LinearProgressIndicator(minHeight: 2)
                else if (_apps.isEmpty)
                  const Text(
                    'No hay apps de usuario que mostrar.',
                    style: TextStyle(color: AuraTokens.textMuted),
                  )
                else
                  for (final app in _apps)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        app.label,
                        style: const TextStyle(color: AuraTokens.textPrimary),
                      ),
                      subtitle: Text(
                        _policy.mode == AuraFirewallMode.paranoico
                            ? '${app.packageName}\nEncendida: entra al túnel.'
                            : _policy.mode == AuraFirewallMode.estricto
                            ? '${app.packageName}\nEn Estricto todas entran al túnel.'
                            : '${app.packageName}\nEncendida: sale directa, sin filtro.',
                        style: const TextStyle(
                          color: AuraTokens.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      value: _selected(app.packageName),
                      onChanged:
                          _policy.mode == AuraFirewallMode.estricto || _busy
                          ? null
                          : (_) => _toggleApp(app.packageName),
                    ),
                if (_note != null) ...[
                  const SizedBox(height: 8),
                  Text(_note!, style: const TextStyle(color: AuraTokens.gold)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: widget.commandsEnabled && !_busy ? _apply : null,
                  child: const Text('Guardar con CONFIRMO'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

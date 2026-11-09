import 'dart:convert';

import 'agent_execution_guard.dart';

/// A suggestion from untrusted model output, not an authorization or execution.
/// This initial boundary accepts only a small read-only subset of Aura tools.
class LlmToolProposal {
  const LlmToolProposal._(this.tool, this.arguments);

  final String tool;
  final Map<String, dynamic> arguments;

  static const int maxOutputBytes = 8192;
  static const Set<String> _readOnlyTools = <String>{
    'analyze_domain',
    'audit_device',
    'scan_apps',
  };

  /// Returns null for malformed or unsupported output. Does not execute tools.
  /// Model-provided confirmation is never accepted, including for read-only tools.
  static LlmToolProposal? parse(String output) {
    if (output.length > maxOutputBytes ||
        utf8.encode(output).length > maxOutputBytes) {
      return null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(output);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 2 ||
        !decoded.containsKey('tool') ||
        !decoded.containsKey('arguments')) {
      return null;
    }
    final tool = decoded['tool'];
    final arguments = decoded['arguments'];
    if (tool is! String ||
        !_readOnlyTools.contains(tool) ||
        arguments is! Map<String, dynamic> ||
        arguments.containsKey('confirmed_by_user')) {
      return null;
    }
    if (AuraToolExecutionPolicy.validate(tool, arguments) != null) return null;
    return LlmToolProposal._(
      tool,
      Map<String, dynamic>.unmodifiable(arguments),
    );
  }
}

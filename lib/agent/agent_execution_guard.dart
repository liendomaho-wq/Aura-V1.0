/// Cancellation is guaranteed only before a tool crosses its execution
/// boundary. Android MethodChannel calls and already-started native work
/// cannot be safely interrupted by Dart.
class AgentCancellationToken {
  bool _cancelled = false;
  bool _executionStarted = false;

  bool get isCancelled => _cancelled;
  bool get executionStarted => _executionStarted;

  bool cancel() {
    if (_executionStarted || _cancelled) return false;
    _cancelled = true;
    return true;
  }

  void markExecutionStarted() {
    if (_cancelled) {
      throw const AgentOperationCancelled();
    }
    _executionStarted = true;
  }

  void throwIfCancelled() {
    if (_cancelled) throw const AgentOperationCancelled();
  }
}

class AgentOperationCancelled implements Exception {
  const AgentOperationCancelled();
}

abstract final class AuraToolExecutionPolicy {
  static const int maxArgumentDepth = 6;
  static const int maxCollectionEntries = 128;
  static const int maxStringLength = 2048;

  static const Set<String> allowedTools = <String>{
    'update_defenses',
    'audit_device',
    'scan_apps',
    'analyze_domain',
    'toggle_defenses',
    'block_domain',
    'isolate_app',
    'panic_isolation',
    'resume_network',
    'cryptographic_purge',
  };

  static const Set<String> confirmationRequired = <String>{
    'toggle_defenses',
    'block_domain',
    'isolate_app',
    'panic_isolation',
    'resume_network',
    'cryptographic_purge',
  };

  static const Map<String, Set<String>> _allowedArguments =
      <String, Set<String>>{
        'update_defenses': <String>{'confirmed_by_user'},
        'audit_device': <String>{'confirmed_by_user'},
        'scan_apps': <String>{'confirmed_by_user'},
        'analyze_domain': <String>{'domain', 'confirmed_by_user'},
        'toggle_defenses': <String>{'activate', 'confirmed_by_user'},
        'block_domain': <String>{'domain', 'confirmed_by_user'},
        'isolate_app': <String>{'package_name', 'reason', 'confirmed_by_user'},
        'panic_isolation': <String>{'confirmed_by_user'},
        'resume_network': <String>{'confirmed_by_user'},
        'cryptographic_purge': <String>{'confirmed_by_user'},
      };

  static Duration timeoutFor(String tool) => switch (tool) {
    'update_defenses' => const Duration(seconds: 100),
    'analyze_domain' => const Duration(seconds: 45),
    // Native consent and service confirmation each have a 30 s deadline.
    // Extra time accommodates channel delivery; timeout still means unknown.
    'toggle_defenses' => const Duration(seconds: 80),
    'scan_apps' || 'audit_device' => const Duration(seconds: 30),
    'cryptographic_purge' => const Duration(seconds: 30),
    _ => const Duration(seconds: 20),
  };

  /// Returns a stable error code; never includes user data in the error.
  static String? validate(String tool, Map<String, dynamic> arguments) {
    if (!allowedTools.contains(tool)) return 'unknown_tool';
    final allowed = _allowedArguments[tool]!;
    if (arguments.keys.any((key) => !allowed.contains(key))) {
      return 'unexpected_tool_argument';
    }
    if (arguments.length > maxCollectionEntries) {
      return 'too_many_tool_arguments';
    }
    for (final entry in arguments.entries) {
      if (!_isSafeValue(entry.value, 0)) return 'invalid_tool_argument';
    }

    if (confirmationRequired.contains(tool) &&
        arguments['confirmed_by_user'] != true) {
      return 'user_confirmation_required';
    }
    if (tool == 'toggle_defenses' && arguments['activate'] is! bool) {
      return 'invalid_activation_state';
    }
    if (tool == 'analyze_domain' || tool == 'block_domain') {
      final domain = arguments['domain'];
      if (domain is! String || !_isValidDnsName(domain)) {
        return 'invalid_domain';
      }
    }
    if (tool == 'isolate_app') {
      final packageName = arguments['package_name'];
      if (packageName is! String ||
          packageName.length > 255 ||
          !RegExp(
            r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
          ).hasMatch(packageName)) {
        return 'invalid_package_name';
      }
      final reason = arguments['reason'];
      if (reason != null && reason is! String) return 'invalid_tool_argument';
      if (reason is String && reason.length > 512) {
        return 'invalid_tool_argument';
      }
    }
    return null;
  }

  static bool _isValidDnsName(String value) {
    if (value.isEmpty || value.length > 253 || value != value.trim()) {
      return false;
    }
    final labels = value.split('.');
    if (labels.length < 2) return false;
    return labels.every(
          (label) =>
              label.isNotEmpty &&
              label.length <= 63 &&
              RegExp(
                r'^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$',
              ).hasMatch(label),
        ) &&
        RegExp(r'^[A-Za-z]{2,63}$').hasMatch(labels.last);
  }

  static bool _isSafeValue(Object? value, int depth) {
    if (depth > maxArgumentDepth) return false;
    if (value == null || value is bool || value is int || value is double) {
      return value is! double || value.isFinite;
    }
    if (value is String) return value.length <= maxStringLength;
    if (value is List) {
      if (value.length > maxCollectionEntries) return false;
      return value.every((item) => _isSafeValue(item, depth + 1));
    }
    if (value is Map) {
      if (value.length > maxCollectionEntries) return false;
      return value.entries.every(
        (entry) =>
            entry.key is String &&
            (entry.key as String).length <= 64 &&
            _isSafeValue(entry.value, depth + 1),
      );
    }
    return false;
  }
}

import 'dart:convert';

import 'agent_execution_guard.dart';

/// Small structural scanner that rejects ambiguous JSON object keys before
/// dart:convert decodes them (jsonDecode otherwise silently keeps the last key).
/// It also bounds nesting and collection sizes to keep hostile model output cheap.
class _StrictJsonStructureScanner {
  _StrictJsonStructureScanner(this.source);

  static const int _maxDepth = 16;
  static const int _maxObjectMembers = 64;
  static const int _maxArrayItems = 256;

  final String source;
  int _index = 0;

  static bool accepts(String source) {
    final scanner = _StrictJsonStructureScanner(source);
    try {
      scanner._readValue(0);
      scanner._skipWhitespace();
      return scanner._index == source.length;
    } on FormatException {
      return false;
    }
  }

  void _readValue(int depth) {
    if (depth > _maxDepth) {
      throw const FormatException('JSON nesting too deep.');
    }
    _skipWhitespace();
    if (_index >= source.length) {
      throw const FormatException('Missing JSON value.');
    }
    switch (source.codeUnitAt(_index)) {
      case 0x7b: // {
        _readObject(depth + 1);
        break;
      case 0x5b: // [
        _readArray(depth + 1);
        break;
      case 0x22: // "
        _readString();
        break;
      default:
        _readPrimitive();
        break;
    }
  }

  void _readObject(int depth) {
    _index++;
    _skipWhitespace();
    final keys = <String>{};
    if (_consume(0x7d)) return;
    var members = 0;
    while (true) {
      _skipWhitespace();
      if (_index >= source.length || source.codeUnitAt(_index) != 0x22) {
        throw const FormatException('Object key must be a string.');
      }
      final key = _readString();
      if (!keys.add(key)) {
        throw const FormatException('Duplicate JSON object key.');
      }
      members++;
      if (members > _maxObjectMembers) {
        throw const FormatException('Too many JSON object members.');
      }
      _skipWhitespace();
      _expect(0x3a); // :
      _readValue(depth);
      _skipWhitespace();
      if (_consume(0x7d)) return;
      _expect(0x2c); // ,
    }
  }

  void _readArray(int depth) {
    _index++;
    _skipWhitespace();
    if (_consume(0x5d)) return;
    var items = 0;
    while (true) {
      _readValue(depth);
      items++;
      if (items > _maxArrayItems) {
        throw const FormatException('Too many JSON array items.');
      }
      _skipWhitespace();
      if (_consume(0x5d)) return;
      _expect(0x2c); // ,
    }
  }

  String _readString() {
    final start = _index;
    _expect(0x22);
    while (_index < source.length) {
      final unit = source.codeUnitAt(_index++);
      if (unit == 0x22) {
        return jsonDecode(source.substring(start, _index)) as String;
      }
      if (unit < 0x20) {
        throw const FormatException('Control character in JSON string.');
      }
      if (unit == 0x5c) {
        if (_index >= source.length) {
          throw const FormatException('Incomplete escape.');
        }
        final escaped = source.codeUnitAt(_index++);
        if (escaped == 0x75) {
          for (var count = 0; count < 4; count++) {
            if (_index >= source.length) {
              throw const FormatException('Incomplete unicode escape.');
            }
            _index++;
          }
        }
      }
    }
    throw const FormatException('Unterminated JSON string.');
  }

  void _readPrimitive() {
    final start = _index;
    while (_index < source.length) {
      final unit = source.codeUnitAt(_index);
      if (unit == 0x2c ||
          unit == 0x5d ||
          unit == 0x7d ||
          unit == 0x20 ||
          unit == 0x09 ||
          unit == 0x0a ||
          unit == 0x0d) {
        break;
      }
      _index++;
    }
    if (_index == start) {
      throw const FormatException('Invalid JSON value.');
    }
  }

  void _skipWhitespace() {
    while (_index < source.length) {
      final unit = source.codeUnitAt(_index);
      if (unit != 0x20 && unit != 0x09 && unit != 0x0a && unit != 0x0d) {
        break;
      }
      _index++;
    }
  }

  bool _consume(int expected) {
    if (_index < source.length && source.codeUnitAt(_index) == expected) {
      _index++;
      return true;
    }
    return false;
  }

  void _expect(int expected) {
    if (!_consume(expected)) {
      throw const FormatException('Unexpected JSON token.');
    }
  }
}

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
    if (!_StrictJsonStructureScanner.accepts(output)) return null;
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

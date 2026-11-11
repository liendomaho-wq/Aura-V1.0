import 'package:aura_mobile_defens/agent/agent_execution_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuraToolExecutionPolicy', () {
    test('accepts a well-formed read-only domain analysis', () {
      expect(
        AuraToolExecutionPolicy.validate('analyze_domain', <String, dynamic>{
          'domain': 'example.com',
        }),
        isNull,
      );
    });

    test('rejects unknown tools and unexpected arguments', () {
      expect(
        AuraToolExecutionPolicy.validate('execute_shell', <String, dynamic>{}),
        'unknown_tool',
      );
      expect(
        AuraToolExecutionPolicy.validate('scan_apps', <String, dynamic>{
          'shell': 'id',
        }),
        'unexpected_tool_argument',
      );
    });

    test('requires explicit confirmation for side-effecting tools', () {
      expect(
        AuraToolExecutionPolicy.validate('block_domain', <String, dynamic>{
          'domain': 'malware.example',
        }),
        'user_confirmation_required',
      );
    });

    test('rejects malformed domains and package identifiers', () {
      expect(
        AuraToolExecutionPolicy.validate('block_domain', <String, dynamic>{
          'domain': 'https://malware.example/path',
          'confirmed_by_user': true,
        }),
        'invalid_domain',
      );
      expect(
        AuraToolExecutionPolicy.validate('isolate_app', <String, dynamic>{
          'package_name': '../../bad',
          'confirmed_by_user': true,
        }),
        'invalid_package_name',
      );
    });

    test('rejects non-finite and deeply nested argument values', () {
      expect(
        AuraToolExecutionPolicy.validate('analyze_domain', <String, dynamic>{
          'domain': double.nan,
        }),
        'invalid_tool_argument',
      );
      Object nested = 'leaf';
      for (var i = 0; i < 8; i++) {
        nested = <String, Object>{'child': nested};
      }
      expect(
        AuraToolExecutionPolicy.validate('analyze_domain', <String, dynamic>{
          'domain': nested,
        }),
        'invalid_tool_argument',
      );
    });

    test('uses bounded per-tool execution deadlines', () {
      expect(
        AuraToolExecutionPolicy.timeoutFor('update_defenses'),
        const Duration(seconds: 100),
      );
      expect(
        AuraToolExecutionPolicy.timeoutFor('scan_apps'),
        const Duration(seconds: 30),
      );
      expect(
        AuraToolExecutionPolicy.timeoutFor('toggle_defenses'),
        const Duration(seconds: 80),
      );
    });
  });

  group('AgentCancellationToken', () {
    test('cancels before the execution boundary', () {
      final token = AgentCancellationToken();
      expect(token.cancel(), isTrue);
      expect(token.isCancelled, isTrue);
      expect(token.executionStarted, isFalse);
      expect(
        () => token.throwIfCancelled(),
        throwsA(isA<AgentOperationCancelled>()),
      );
    });

    test('refuses cancellation after a tool starts', () {
      final token = AgentCancellationToken();
      token.markExecutionStarted();
      expect(token.executionStarted, isTrue);
      expect(token.cancel(), isFalse);
      expect(token.isCancelled, isFalse);
    });

    test('notifies registered cancellation observers exactly once', () {
      final token = AgentCancellationToken();
      var calls = 0;
      expect(token.addCancelListener(() => calls++), isTrue);
      expect(token.cancel(), isTrue);
      expect(token.cancel(), isFalse);
      expect(calls, 1);
    });

    test('removed observers are not notified', () {
      final token = AgentCancellationToken();
      var calls = 0;
      void observer() => calls++;
      token.addCancelListener(observer);
      token.removeCancelListener(observer);
      expect(token.cancel(), isTrue);
      expect(calls, 0);
    });

    test('a failing observer cannot block cancellation', () {
      final token = AgentCancellationToken();
      var calls = 0;
      token.addCancelListener(() => throw StateError('observer failed'));
      token.addCancelListener(() => calls++);
      expect(token.cancel(), isTrue);
      expect(calls, 1);
    });

    test('observers are refused after execution or cancellation', () {
      final running = AgentCancellationToken()..markExecutionStarted();
      expect(running.addCancelListener(() {}), isFalse);
      final cancelled = AgentCancellationToken();
      expect(cancelled.cancel(), isTrue);
      expect(cancelled.addCancelListener(() {}), isFalse);
    });
  });
}

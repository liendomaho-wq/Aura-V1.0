import 'package:aura_mobile_defens/agent/llm_tool_proposal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Untrusted LLM tool proposals', () {
    test('accepts a valid read-only proposal without executing it', () {
      final proposal = LlmToolProposal.parse(
        '{"tool":"analyze_domain","arguments":{"domain":"example.org"}}',
      );
      expect(proposal?.tool, 'analyze_domain');
      expect(proposal?.arguments, <String, dynamic>{'domain': 'example.org'});
      expect(
        () => proposal!.arguments['domain'] = 'other.org',
        throwsUnsupportedError,
      );
    });

    test('accepts read-only no-argument tools', () {
      for (final tool in <String>['audit_device', 'scan_apps']) {
        expect(
          LlmToolProposal.parse('{"tool":"$tool","arguments":{}}'),
          isNotNull,
        );
      }
    });

    test('rejects confirmation claims and all side-effecting tools', () {
      expect(
        LlmToolProposal.parse(
          '{"tool":"scan_apps","arguments":{"confirmed_by_user":true}}',
        ),
        isNull,
      );
      expect(
        LlmToolProposal.parse(
          '{"tool":"block_domain","arguments":{"domain":"example.org","confirmed_by_user":true}}',
        ),
        isNull,
      );
      expect(
        LlmToolProposal.parse('{"tool":"execute_shell","arguments":{}}'),
        isNull,
      );
    });

    test('rejects invalid schemas and malformed arguments', () {
      for (final output in <String>[
        'not json',
        '[]',
        '{"tool":"scan_apps"}',
        '{"tool":"scan_apps","arguments":{},"extra":true}',
        '{"tool":"scan_apps","arguments":[]}',
        '{"tool":"scan_apps","arguments":{"shell":"id"}}',
        '{"tool":"analyze_domain","arguments":{"domain":"https://example.org/path"}}',
        '{"tool":"analyze_domain","arguments":{"domain":5}}',
      ]) {
        expect(LlmToolProposal.parse(output), isNull, reason: output);
      }
    });

    test('rejects oversized model output in bytes', () {
      expect(LlmToolProposal.parse(' ' * 8193), isNull);
      expect(LlmToolProposal.parse('ñ' * 4097), isNull);
    });
  });
}

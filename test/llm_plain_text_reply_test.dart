import 'package:aura_mobile_defens/agent/llm_tool_proposal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LlmConversationReply.fromPlainText', () {
    test('acepta una respuesta normal', () {
      final reply = LlmConversationReply.fromPlainText(
        'La ciberdefensa protege sistemas, redes y datos.',
      );
      expect(reply, isNotNull);
      expect(reply!.text, startsWith('La ciberdefensa'));
    });

    test('quita las vallas de Markdown', () {
      final reply = LlmConversationReply.fromPlainText(
        '```\nQUIC viaja sobre UDP.\n```',
      );
      expect(reply, isNotNull);
      expect(reply!.text, 'QUIC viaja sobre UDP.');
    });

    test('quita el prefijo del hablante', () {
      final reply = LlmConversationReply.fromPlainText(
        'Aura: El DNS resuelve nombres.',
      );
      expect(reply, isNotNull);
      expect(reply!.text, 'El DNS resuelve nombres.');
    });

    test('rechaza texto vacío', () {
      expect(LlmConversationReply.fromPlainText('   \n  '), isNull);
      expect(LlmConversationReply.fromPlainText('```\n```'), isNull);
    });

    test('rechaza caracteres de control', () {
      expect(
        LlmConversationReply.fromPlainText('hola\u0000mundo'),
        isNull,
      );
    });

    test('acota una respuesta larga sin cortar a mitad de palabra', () {
      final long = '${'Frase de prueba. ' * 400}';
      final reply = LlmConversationReply.fromPlainText(long);
      expect(reply, isNotNull);
      expect(reply!.text.length, lessThanOrEqualTo(4097));
      expect(reply.text, endsWith('…'));
    });

    test('sigue exigiendo JSON en la ruta de propuestas', () {
      expect(LlmConversationReply.parse('texto llano'), isNull);
      expect(LlmConversationReply.parse('{"answer":"texto"}'), isNotNull);
    });
  });
}

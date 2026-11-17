import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/services/providers/kilo_gateway_provider.dart';

void main() {
  group('Kilo anonymous model gateway', () {
    test('uses the documented Kilo OpenAI-compatible endpoint', () {
      expect(KiloGatewayProvider.chatCompletionsUri.toString(),
        'https://ai-gateway.kilo.ai/api/v1/chat/completions');
    });
    test('catalog contains the requested free model IDs without duplicates', () {
      final ids = KiloGatewayProvider.models.map((model) => model.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids, containsAll([
        'kilo-auto/free',
        'baidu/ernie-5.5-flash-preview:free',
        'cohere/north-mini-code:free',
        'dots-studio/dots-3-note-preview:free',
        'liquid/lfm-3-1.7b:free',
        'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free',
        'nvidia/nemotron-3-ultra-550b-a55b:free',
        'nvidia/nemotron-3.5-lightning:free',
        'nvidia/nemotron-3.5-super-vl:free',
        'openrouter/free',
        'particle-ai/particle-1:free',
        'reflection/beam-free',
        'stealth/glyph-cluster',
      ]));
    });
    test('extracts OpenAI-compatible completion text', () {
      expect(KiloGatewayProvider.extractText({
        'choices': [{'message': {'content': 'OK'}}]
      }), 'OK');
    });
    test('rejects responses without text', () {
      expect(() => KiloGatewayProvider.extractText({'choices': []}), throwsFormatException);
    });
  });
}

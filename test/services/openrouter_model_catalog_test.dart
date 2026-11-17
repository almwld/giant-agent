import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/services/openrouter_model_catalog.dart';

void main() {
  group('OpenRouterModelCatalog', () {
    test('contains unique, non-empty model identifiers', () {
      final ids = OpenRouterModelCatalog.options.map((item) => item.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids.every((id) => id.trim().isNotEmpty), isTrue);
    });
    test('contains only verified free models or the free router', () {
      for (final option in OpenRouterModelCatalog.options) {
        expect(option.id == 'openrouter/free' || option.id.endsWith(':free'), isTrue, reason: option.id);
        expect(option.name, isNotEmpty);
        expect(option.contextWindow, isNotEmpty);
      }
    });
    test('uses the verified Nemotron Super VL identifier', () {
      expect(OpenRouterModelCatalog.find('nvidia/nemotron-3.5-super-vl:free')?.name, 'NVIDIA Nemotron 3.5 Super VL');
      expect(OpenRouterModelCatalog.find('nvidia/nemotron-3.5-super-v:free'), isNull);
    });
    test('excludes unverified provider labels', () {
      expect(OpenRouterModelCatalog.find('kilo-auto/free'), isNull);
      expect(OpenRouterModelCatalog.find('openai-fast'), isNull);
      expect(OpenRouterModelCatalog.find('stealth/glyph-cluster'), isNull);
      expect(OpenRouterModelCatalog.find('reflection/beam-free'), isNull);
    });
  });
}
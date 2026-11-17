/// Verified OpenRouter chat models curated for the model picker.
/// IDs were checked against OpenRouter's public /api/v1/models catalog.
class OpenRouterModelOption {
  const OpenRouterModelOption({required this.id, required this.name, required this.contextWindow, this.note});
  final String id;
  final String name;
  final String contextWindow;
  final String? note;
}

class OpenRouterModelCatalog {
  OpenRouterModelCatalog._();
  static const options = <OpenRouterModelOption>[
    OpenRouterModelOption(id: 'nvidia/nemotron-3-ultra-550b-a55b:free', name: 'NVIDIA Nemotron 3 Ultra', contextWindow: '1M', note: 'Reasoning and orchestration'),
    OpenRouterModelOption(id: 'baidu/ernie-5.5-flash-preview:free', name: 'Baidu ERNIE 5.5 Flash Preview', contextWindow: '1M', note: 'Provider-managed reasoning'),
    OpenRouterModelOption(id: 'nvidia/nemotron-3.5-super-vl:free', name: 'NVIDIA Nemotron 3.5 Super VL', contextWindow: '1M', note: 'Text, image and video input'),
    OpenRouterModelOption(id: 'nvidia/nemotron-3.5-lightning:free', name: 'NVIDIA Nemotron 3.5 Lightning', contextWindow: '1M', note: 'Fast text and tool workflows'),
    OpenRouterModelOption(id: 'cohere/north-mini-code:free', name: 'Cohere North Mini Code', contextWindow: '256K', note: 'Agentic coding'),
    OpenRouterModelOption(id: 'dots-studio/dots-3-note-preview:free', name: 'Dots3-Note Preview', contextWindow: '512K', note: 'Preview endpoint expires 2026-12-31'),
    OpenRouterModelOption(id: 'particle-ai/particle-1:free', name: 'Particle-1', contextWindow: '1M', note: 'Agentic software engineering'),
    OpenRouterModelOption(id: 'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free', name: 'NVIDIA Nemotron 3 Nano Omni', contextWindow: '256K', note: 'Multimodal perception model'),
    OpenRouterModelOption(id: 'liquid/lfm-3-1.7b:free', name: 'Liquid LFM3 1.7B', contextWindow: '256K', note: 'Compact model with tool calling'),
    OpenRouterModelOption(id: 'openrouter/free', name: 'OpenRouter Free Router', contextWindow: '200K', note: 'Routes to an available free model'),
  ];
  static OpenRouterModelOption? find(String id) {
    for (final option in options) { if (option.id == id) return option; }
    return null;
  }
}
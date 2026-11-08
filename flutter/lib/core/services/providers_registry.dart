/// Provider capability registry — port of `src/chat/providers.ts`.
///
/// Every supported LLM provider is declared here with its capabilities and
/// model catalogue. Application logic MUST NOT hard-code model names — always
/// read from this list.

enum ProviderState { available, rateLimited, degraded, down }

class ModelOption {
  final String id;
  final String label;
  final int contextLimit;
  final int maxOutput;
  final bool vision;
  final bool tools;
  final bool isLive;
  const ModelOption({
    required this.id,
    required this.label,
    required this.contextLimit,
    required this.maxOutput,
    required this.vision,
    required this.tools,
    this.isLive = false,
  });
}

class LlmProvider {
  final String id;
  final String name;
  final String baseUrl;
  final String model;
  final List<ModelOption> models;
  final bool supportsStreaming;
  final bool supportsTools;
  final bool supportsUsage;
  final bool supportsStructuredOutput;
  final int contextLimit;
  final String envKey;
  final ProviderState state;
  const LlmProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    required this.models,
    required this.supportsStreaming,
    required this.supportsTools,
    required this.supportsUsage,
    required this.supportsStructuredOutput,
    required this.contextLimit,
    required this.envKey,
    this.state = ProviderState.available,
  });
}

ModelOption _m(String id, String label, int contextLimit, int maxOutput,
    {bool vision = false, bool tools = true, bool isLive = false}) {
  return ModelOption(
    id: id,
    label: label,
    contextLimit: contextLimit,
    maxOutput: maxOutput,
    vision: vision,
    tools: tools,
    isLive: isLive,
  );
}

/// Canonical ordered list (first = highest priority). Failover walks top-down.
final List<LlmProvider> providers = [
  LlmProvider(
    id: 'openrouter',
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    model: 'anthropic/claude-sonnet-4',
    models: [
      _m('anthropic/claude-sonnet-4', 'Claude Sonnet 4', 200000, 64000, vision: true),
      _m('openai/gpt-4.1', 'GPT-4.1', 1047576, 32768, vision: true),
      _m('google/gemini-2.5-pro', 'Gemini 2.5 Pro', 1048576, 65536, vision: true),
      _m('deepseek/deepseek-chat-v3-0324', 'DeepSeek V3', 163840, 8192),
      _m('mistralai/mistral-small-3.2-24b-instruct:free', 'Mistral Small 3.2 (free)', 128000, 8192, vision: true),
    ],
    supportsStreaming: true,
    supportsTools: true,
    supportsUsage: true,
    supportsStructuredOutput: true,
    contextLimit: 200000,
    envKey: 'OPENROUTER_API_KEY',
  ),
  LlmProvider(
    id: 'groq',
    name: 'Groq',
    baseUrl: 'https://api.groq.com/openai/v1',
    model: 'llama-3.3-70b-versatile',
    models: [
      _m('llama-3.3-70b-versatile', 'Llama 3.3 70B', 131072, 32768),
      _m('llama-3.1-8b-instant', 'Llama 3.1 8B Instant', 131072, 8192),
      _m('qwen/qwen3-32b', 'Qwen 3 32B', 131072, 32768),
      _m('moonshotai/kimi-k2-instruct', 'Kimi K2', 131072, 16384),
    ],
    supportsStreaming: true,
    supportsTools: true,
    supportsUsage: true,
    supportsStructuredOutput: true,
    contextLimit: 131072,
    envKey: 'GROQ_API_KEY',
  ),
  LlmProvider(
    id: 'google',
    name: 'Google AI Studio',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    model: 'gemini-3.1-flash-lite-image',
    models: [
      _m('gemini-3.1-flash-lite-image', 'Gemini 3.1 Flash Lite Image (Nano Banana 2 Lite)', 65536, 4096, vision: true, tools: false, isLive: true),
      _m('gemini-2.5-flash', 'Gemini 2.5 Flash', 1048576, 65536, vision: true),
      _m('gemini-2.5-pro', 'Gemini 2.5 Pro', 1048576, 65536, vision: true),
      _m('gemini-2.5-flash-lite', 'Gemini 2.5 Flash Lite', 1048576, 65536, vision: true),
      _m('gemini-2.0-flash', 'Gemini 2.0 Flash', 1048576, 8192, vision: true),
    ],
    supportsStreaming: true,
    supportsTools: true,
    supportsUsage: false,
    supportsStructuredOutput: true,
    contextLimit: 1048576,
    envKey: 'GOOGLE_AI_KEY',
  ),
  LlmProvider(
    id: 'mistral',
    name: 'Mistral',
    baseUrl: 'https://api.mistral.ai/v1',
    model: 'mistral-large-latest',
    models: [
      _m('mistral-large-latest', 'Mistral Large', 131072, 32768),
      _m('mistral-medium-latest', 'Mistral Medium', 131072, 8192, vision: true),
      _m('magistral-medium-latest', 'Magistral Medium', 40960, 40960),
      _m('pixtral-large-latest', 'Pixtral Large', 131072, 32768, vision: true),
    ],
    supportsStreaming: true,
    supportsTools: true,
    supportsUsage: false,
    supportsStructuredOutput: true,
    contextLimit: 131072,
    envKey: 'MISTRAL_API_KEY',
  ),
  LlmProvider(
    id: 'ollama',
    name: 'Ollama (Local)',
    baseUrl: 'http://localhost:11434/v1',
    model: 'llama3',
    models: [
      _m('llama3', 'Llama 3 (Local)', 8192, 4096),
      _m('mistral', 'Mistral (Local)', 8192, 4096),
      _m('phi3', 'Phi-3 (Local)', 4096, 2048, tools: false),
    ],
    supportsStreaming: true,
    supportsTools: true,
    supportsUsage: false,
    supportsStructuredOutput: false,
    contextLimit: 8192,
    envKey: 'OLLAMA_HOST',
  ),
  LlmProvider(
    id: 'prototype',
    name: 'Lively Prototype Engine',
    baseUrl: 'http://localhost:3001/api',
    model: 'lively/openui-smart',
    models: [
      _m('lively/openui-smart', 'Lively OpenUI Designer (Interactive UI)', 128000, 16384, vision: true, isLive: true),
      _m('lively/prototype-smart', 'Lively Prototype (Instant Reasoning)', 128000, 16384, vision: true, isLive: true),
      _m('lively/prototype-fast', 'Lively Prototype Fast', 64000, 8192, vision: true, isLive: true),
    ],
    supportsStreaming: true,
    supportsTools: true,
    supportsUsage: true,
    supportsStructuredOutput: true,
    contextLimit: 128000,
    envKey: '',
  ),
];

LlmProvider? getProvider(String id) {
  for (final p in providers) {
    if (p.id == id) return p;
  }
  return null;
}

List<LlmProvider> availableProviders() =>
    providers.where((p) => p.state == ProviderState.available).toList();

ModelOption getModel(LlmProvider provider, [String? modelId]) {
  for (final m in provider.models) {
    if (m.id == modelId) return m;
  }
  return provider.models.first;
}

bool modelSupportsVision(LlmProvider provider, [String? modelId]) =>
    getModel(provider, modelId).vision;

bool modelSupportsTools(LlmProvider provider, [String? modelId]) =>
    provider.supportsTools && getModel(provider, modelId).tools;

int modelContextLimit(LlmProvider provider, [String? modelId]) =>
    getModel(provider, modelId).contextLimit;
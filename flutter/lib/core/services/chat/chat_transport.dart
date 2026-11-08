/// Chat transport — port of `src/chat/transport.ts` for the Flutter desktop
/// runtime.
///
/// On the web the request went through the Vite dev proxy; on Tauri it went
/// through the native Rust proxy. Here the Dart app talks to the upstream
/// provider (or the local Lively backend, which proxies everything) directly
/// and injects the key from the app's key store. Both paths produce the same
/// token stream and the same error types, so the failover engine above stays
/// transport-agnostic.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;

import 'chat_failover.dart';
import 'chat_sse.dart';
import 'chat_tokens.dart';
import '../providers_registry.dart';

// ─── Wire types ──────────────────────────────────────────────────────────────

/// OpenAI-style content part: text or image_url.
class ChatContentPart {
  final String type; // 'text' | 'image_url'
  final String? text;
  final String? imageUrl;
  const ChatContentPart.text(String this.text)
      : type = 'text',
        imageUrl = null;
  const ChatContentPart.imageUrl(String this.imageUrl)
      : type = 'image_url',
        text = null;

  Map<String, dynamic> toJson() => type == 'text'
      ? {'type': 'text', 'text': text}
      : {'type': 'image_url', 'image_url': {'url': imageUrl}};
}

/// Either a plain string or a list of parts (OpenAI-compatible union).
class ChatContent {
  final String? text;
  final List<ChatContentPart>? parts;
  const ChatContent.string(String this.text) : parts = null;
  const ChatContent.parts(List<ChatContentPart> this.parts) : text = null;

  dynamic toWire() => parts != null ? parts!.map((p) => p.toJson()).toList() : text;
}

/// An OpenAI-compatible function tool call returned by the model.
class ChatToolCall {
  final String id;
  final String name;
  final String arguments;
  const ChatToolCall({required this.id, required this.name, required this.arguments});

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': arguments},
      };
}

/// A message on the wire.
class ChatMessage {
  final String role;
  final ChatContent content;
  final String? name;
  final String? toolCallId;
  final List<ChatToolCall>? toolCalls;
  const ChatMessage({
    required this.role,
    required this.content,
    this.name,
    this.toolCallId,
    this.toolCalls,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content.toWire(),
        if (name != null) 'name': name,
        if (toolCallId != null) 'tool_call_id': toolCallId,
        if (toolCalls != null)
          'tool_calls': toolCalls!.map((t) => t.toJson()).toList(),
      };
}

/// An OpenAI-compatible function definition offered to the model.
class ToolSpec {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  const ToolSpec({required this.name, required this.description, required this.parameters});

  Map<String, dynamic> toJson() => {
        'type': 'function',
        'function': {'name': name, 'description': description, 'parameters': parameters},
      };
}

/// Sampling parameters, in wire (snake_case) form.
class WireParams {
  final double? temperature;
  final double? topP;
  final int? maxTokens;
  const WireParams({this.temperature, this.topP, this.maxTokens});
}

class StreamOptions {
  final LlmProvider provider;
  final String model;
  final List<ChatMessage> messages;
  final CancellationToken signal;
  final void Function(String token) onToken;
  /// Sampling parameters for this model.
  final WireParams? params;
  /// Native tool definitions. Omitted when empty.
  final List<ToolSpec>? tools;
  /// Callback fired when the provider reports token usage.
  final void Function(StreamUsage usage)? onUsage;
  /// Fired when headers or chunks arrive, to reset the idle timeout.
  final void Function()? onProgress;
  const StreamOptions({
    required this.provider,
    required this.model,
    required this.messages,
    required this.signal,
    required this.onToken,
    this.params,
    this.tools,
    this.onUsage,
    this.onProgress,
  });
}

class StreamResult {
  final String text;
  final StreamUsage? usage;
  final List<NativeToolCall> toolCalls;
  final String? finishReason;
  const StreamResult({
    required this.text,
    required this.usage,
    required this.toolCalls,
    required this.finishReason,
  });
}

// ─── Provider keys ───────────────────────────────────────────────────────────

/// Where the app stores provider API keys. Wired up by `settings_controller`;
/// the default consults the process environment by env-var name.
String? Function(String envKey) providerKeyResolver = _envKey;

String? _envKey(String name) {
  try {
    return Platform.environment[name];
  } catch (_) {
    return null;
  }
}

/// Build the JSON body shared by both transports.
///
/// `stream_options.include_usage` is only sent to providers that support it;
/// sending it to a provider that validates the body strictly would turn a
/// valid request into a 400.
Map<String, dynamic> buildRequestBody({
  required String model,
  required List<ChatMessage> messages,
  WireParams? params,
  List<ToolSpec>? tools,
  required bool includeUsage,
}) {
  final body = <String, dynamic>{
    'model': model,
    'messages': messages.map((m) => m.toJson()).toList(),
    'stream': true,
  };

  if (includeUsage) {
    body['stream_options'] = {'include_usage': true};
  }
  final p = params;
  if (p?.temperature != null) body['temperature'] = p!.temperature;
  if (p?.topP != null) body['top_p'] = p!.topP;
  if (p?.maxTokens != null) body['max_tokens'] = p!.maxTokens;
  if (tools != null && tools.isNotEmpty) {
    body['tools'] = tools.map((t) => t.toJson()).toList();
    body['tool_choice'] = 'auto';
  }

  return body;
}

/// True for image-generation models. These cannot be served by an
/// OpenAI-style chat endpoint, so they are routed to the Lively backend's
/// image engine (which calls the provider's native image API). The rule
/// matches the backend's own `/image/i` test on the model id.
bool isImageModelId(String? model) =>
    model != null && RegExp('image', caseSensitive: false).hasMatch(model);

/// Resolve the endpoint for a provider: the upstream base URL, or the local
/// Lively backend route (`/api/llm/<id>/…`) when the provider is served by
/// the backend prototype engine.
Uri resolveEndpoint(LlmProvider provider, String path, {String? model}) {
  final normalised = path.startsWith('/') ? path : '/$path';
  if (provider.id == 'prototype' ||
      provider.baseUrl.contains('localhost:3001') ||
      isImageModelId(model)) {
    final trimmed = normalised.startsWith('/') ? normalised.substring(1) : normalised;
    return Uri.parse('http://localhost:3001/api/llm/${provider.id}/$trimmed');
  }
  var full = '${provider.baseUrl}$normalised';
  while (full.endsWith('/') && !full.endsWith('://')) {
    full = full.substring(0, full.length - 1);
  }
  return Uri.parse(full);
}

/// Stream an offline demonstration completion with real generative UI.
Future<StreamResult> _streamOfflineDemo(StreamOptions opts) async {
  opts.onProgress?.call();

  final lastUser = opts.messages.lastWhere(
    (m) => m.role == 'user',
    orElse: () => const ChatMessage(role: 'user', content: ChatContent.string('')),
  );
  final userText = (lastUser.content.text ?? '').trim();
  final lower = userText.toLowerCase();

  String fullResponse;
  if (lower.contains('compare') || lower.contains('provider') || lower.contains('form')) {
    fullResponse = '''Here is a detailed comparison of all supported AI providers in Lively OpenAll, along with an interactive form to configure your preferred engine:

```openui-lang
root = Stack([providersCard, formCard])
providersCard = Card("Supported AI Providers", [providerTable], "A breakdown of engines supported in Lively OpenAll.")
providerTable = Table(["Provider", "Default Model", "Context Limit", "Specialty"], [["OpenRouter", "Claude Sonnet 4 / GPT-4.1", "200k tokens", "Multi-model routing & reasoning"], ["Google AI", "Gemini 2.5 Pro", "1M tokens", "Massive context & multimodal"], ["Groq", "Llama 3.3 70B", "131k tokens", "Near-instant streaming inference"], ["Mistral", "Mistral Large", "128k tokens", "European sovereignty & coding"], ["Ollama", "Llama 3 (Local)", "Device RAM", "100% private on-device LLM"]])
formCard = Card("Engine Selector", [formText, pickForm])
formText = Text("Choose a provider configuration to test or connect:")
pickForm = Form([{"name": "provider", "label": "Selected Provider", "type": "select", "options": ["OpenRouter", "Google AI Studio", "Groq", "Mistral", "Ollama (Local)"]}, {"name": "offline", "label": "Keep Local Demo Enabled", "type": "checkbox"}], @ToAssistant("I have saved my provider preferences."), "Provider Setup", "Confirm Engine")
```

💡 **Tip**: To use live cloud providers (Claude, GPT-4, Gemini 2.5), open **Settings** (⚙) in the bottom-left sidebar to enter your API keys.''';
  } else if (lower.contains('san francisco') || lower.contains('plan') || lower.contains('trip') || lower.contains('travel') || lower.contains('day')) {
    fullResponse = '''Here is a curated 1-day itinerary for experiencing San Francisco from morning coffee to sunset:

```openui-lang
root = Stack([itineraryCard, budgetCard])
itineraryCard = Card("San Francisco 1-Day Itinerary", [sfSteps], "A curated tour through the iconic spots of San Francisco.")
sfSteps = Steps([{"title": "09:00 AM — Ferry Building & Embarcadero", "description": "Grab blue bottle coffee, artisan sourdough bread, and walk the waterfront."}, {"title": "11:30 AM — Historic Cable Car to Chinatown", "description": "Ride the Powell-Hyde cable car, stroll Grant Avenue, and enjoy fresh dim sum."}, {"title": "02:00 PM — Presidio & Golden Gate Vista", "description": "Visit Crissy Field for postcard-perfect views of the Golden Gate Bridge."}, {"title": "05:30 PM — Mission District & Sunset at Dolores", "description": "Pick up a famous Mission burrito and watch the city skyline illuminate at sunset."}])
budgetCard = Card("Trip Cost Estimate", [budgetTable, saveBtn])
budgetTable = Table(["Category", "Estimated Cost", "Recommendation"], [["Transit & Cable Car", "\$13.00", "Muni 1-Day Passport"], ["Food & Drinks", "\$45.00", "Local bakeries, dim sum & burritos"], ["Sightseeing", "Free", "Parks, bridge vista & viewpoints"]])
saveBtn = Button("Save Itinerary to Notes", @ToAssistant("Save the San Francisco day plan to my notes."), "primary")
```

Enjoy your day exploring the City by the Bay! Feel free to ask if you want custom restaurant or museum recommendations.''';
  } else if (lower.contains('canvas') || lower.contains('release') || lower.contains('draft')) {
    fullResponse = '''## Lively OpenAll — Canvas Pane Release Notes

### 🚀 What's New: The Interactive Canvas Surface
We are thrilled to introduce the **Canvas Pane** in Lively OpenAll — a dedicated workspace that docks right beside your conversation column.

#### ✨ Key Highlights
- **Side-by-Side Collaboration**: Generate, review, and edit documents, code, and UI mockups beside the chat.
- **Generative UI Rendering**: OpenUI Lang programs render live as interactive widgets.
- **Local-First & Fast**: Keeps your context intact with minimal latency and full offline capability.

```openui-lang
root = Stack([releaseCard, actionsCard])
releaseCard = Card("Canvas Workspace Released", [releaseText, featTable], "Introducing persistent side-by-side artifact editing.")
releaseText = Text("The Canvas Pane brings a 420px interactive document surface alongside your 720px conversation column, enabling document drafting, generative UI components, and code previews without losing chat flow.")
featTable = Table(["Capability", "Status", "Details"], [["Split-Pane View", "Active", "Docked side-by-side with chat"], ["Artifact Detection", "Active", "Automatically isolates documents & designs"], ["Generative UI", "Active", "Dynamic OpenUI Lang interactive cards & forms"]])
actionsCard = Card("Next Steps", [exploreBtn])
exploreBtn = Button("Explore Interactive Components", @ToAssistant("Show me all interactive UI components available in Lively OpenAll."), "secondary")
```''';
  } else if (lower.contains('chart') || lower.contains('graph') || lower.contains('stat') || lower.contains('metric')) {
    fullResponse = '''Here is an analysis and visualization of performance metrics:

```openui-lang
root = Stack([chartCard, statsCard])
chartCard = Card("Quarterly Growth Metrics", [growthChart], "Active user growth across Q1 to Q4.")
growthChart = Chart("line", ["Jan", "Feb", "Mar", "Apr", "May", "Jun"], [120, 190, 310, 520, 840, 1260], "Monthly Active Users (Thousands)")
statsCard = Card("Performance Summary", [metricsTable])
metricsTable = Table(["Metric", "Current Value", "Change"], [["Monthly Active Users", "1.26M", "+18.4%"], ["Average Latency", "32ms", "-14.2%"], ["User Retention", "91.2%", "+3.8%"]])
```''';
  } else {
    fullResponse = '''Hello! I am **Lively Assistant**, your local-first AI companion.

I can answer questions, analyze data, write clean code, and generate live interactive interfaces using OpenUI Lang.

```openui-lang
root = Stack([welcomeCard, quickCard])
welcomeCard = Card("Lively OpenAll AI Assistant", [infoText, capTable])
infoText = Text("Welcome to Lively OpenAll! I can write prose, analyze data, plan projects, run code, and build live interactive user interfaces.")
capTable = Table(["Capability", "Status", "Description"], [["Generative UI", "Active", "Interactive buttons, tables, and forms"], ["Local First", "Active", "Runs completely on-device without cloud dependency"], ["Cloud LLMs", "Ready", "Connect Claude, GPT-4, and Gemini with API keys in Settings"]])
quickCard = Card("Quick Actions", [exploreBtn])
exploreBtn = Button("Compare All LLM Providers", @ToAssistant("Compare the providers and give me a form to pick one."), "primary")
```

💡 **Pro Tip**: To connect real cloud models like Claude 3.5 Sonnet, GPT-4o, or Gemini 2.5 Pro, click the **Settings** (⚙) icon in the bottom-left sidebar to add your API keys.''';
  }

  // Stream in realistic chunks
  final words = fullResponse.split(' ');
  final buffer = StringBuffer();
  for (var i = 0; i < words.length; i++) {
    if (opts.signal.isCancelled) {
      throw RequestAborted();
    }
    final word = (i == 0 ? '' : ' ') + words[i];
    buffer.write(word);
    opts.onToken(word);
    opts.onProgress?.call();
    await Future.delayed(const Duration(milliseconds: 14));
  }

  final promptTokens = (userText.length ~/ 4) + 12;
  final completionTokens = (fullResponse.length ~/ 4) + 1;
  final usage = StreamUsage(
    promptTokens: promptTokens,
    completionTokens: completionTokens,
    totalTokens: promptTokens + completionTokens,
  );
  opts.onUsage?.call(usage);

  return StreamResult(
    text: fullResponse,
    usage: usage,
    toolCalls: const [],
    finishReason: 'stop',
  );
}

/// Stream a completion directly from the provider (or local backend).
Future<StreamResult> streamViaProvider(StreamOptions opts) async {
  final provider = opts.provider;

  if (provider.id == 'demo' || provider.baseUrl.startsWith('offline://')) {
    return _streamOfflineDemo(opts);
  }

  // Pre-check for required API keys. If missing, fail fast with a helpful message.
  final key = providerKeyResolver(provider.envKey);
  if (provider.envKey.isNotEmpty && (key == null || key.trim().isEmpty)) {
    throw HttpProviderError(
      401,
      'No API key configured for ${provider.name}. Add your API key in Settings (⚙) > Providers or switch to Lively Demo (Offline).',
      provider,
    );
  }

  final request = http.Request(
    'POST',
    resolveEndpoint(provider, '/chat/completions', model: opts.model),
  );
  request.headers['Content-Type'] = 'application/json';
  if (key != null && key.isNotEmpty) {
    request.headers['Authorization'] = 'Bearer $key';
  }
  request.body = jsonEncode(buildRequestBody(
    model: opts.model,
    messages: opts.messages,
    params: opts.params,
    tools: opts.tools,
    includeUsage: provider.supportsUsage,
  ));

  opts.onProgress?.call();
  final client = http.Client();
  http.StreamedResponse response;
  try {
    response = await client.send(request);
  } catch (e) {
    client.close();
    throw TransportError('Failed to connect to ${provider.name} (${provider.baseUrl}): $e');
  }

  if (response.statusCode < 200 || response.statusCode >= 300) {
    final body = await response.stream.bytesToString().catchError((_) => '');
    client.close();
    throw HttpProviderError(
      response.statusCode,
      response.reasonPhrase ?? 'HTTP ${response.statusCode}',
      provider,
      body,
    );
  }

  final chunks = response.stream
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .map((line) => '$line\n');
  try {
    return await consumeStream(chunks, opts);
  } finally {
    client.close();
  }
}

Future<StreamResult> consumeStream(Stream<String> chunks, StreamOptions opts) async {
  final parser = SseParser();
  final accumulated = StringBuffer();

  void handleEvents(List<StreamEvent> events) {
    for (final event in events) {
      switch (event.type) {
        case 'text':
          accumulated.write(event.text ?? '');
          opts.onToken(event.text ?? '');
          break;
        case 'usage':
          if (event.usage != null) opts.onUsage?.call(event.usage!);
          break;
        default:
          break;
      }
    }
  }

  await for (final text in chunks) {
    opts.onProgress?.call();
    handleEvents(parser.pushEvents(text));
  }

  handleEvents(parser.flushEvents());

  return StreamResult(
    text: accumulated.toString(),
    usage: parser.usage(),
    toolCalls: parser.toolCalls(),
    finishReason: parser.finishReason(),
  );
}

/// Stream a chat completion using whichever transport this runtime provides.
Future<StreamResult> streamChat(StreamOptions opts) => streamViaProvider(opts);
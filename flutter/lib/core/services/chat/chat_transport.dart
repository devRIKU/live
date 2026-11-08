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

/// Stream a completion directly from the provider (or local backend).
Future<StreamResult> streamViaProvider(StreamOptions opts) async {
  final provider = opts.provider;

  final request = http.Request(
    'POST',
    resolveEndpoint(provider, '/chat/completions', model: opts.model),
  );
  request.headers['Content-Type'] = 'application/json';
  final key = providerKeyResolver(provider.envKey);
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
  final response = await client.send(request);

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
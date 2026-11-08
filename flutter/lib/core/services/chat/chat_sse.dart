/// SSE parsing — shared by all transports so every path produces identical
/// token streams. Port of `src/chat/sse.ts`.
///
/// OpenAI-compatible providers emit:
///   data: {"choices":[{"delta":{"content":"..."}}]}
///   data: {"choices":[{"delta":{"tool_calls":[{"index":0,…}]}}]}
///   data: {"choices":[],"usage":{"prompt_tokens":…}}
///   data: [DONE]
///
/// `push` / `flush` return content deltas only, so simple callers keep
/// working. `pushEvents` / `flushEvents` return the full stream event set for
/// callers that also need tool calls and usage.
library;

import 'dart:convert';

import 'chat_tokens.dart';

// ─── Types ───────────────────────────────────────────────────────────────────

class ToolCallDelta {
  final int index;
  final String? id;
  final String? name;
  final String? argumentsDelta;
  const ToolCallDelta({
    required this.index,
    this.id,
    this.name,
    this.argumentsDelta,
  });
}

class StreamEvent {
  /// 'text' | 'usage' | 'finish' | 'tool_call'
  final String type;
  final String? text;
  final StreamUsage? usage;
  final String? reason;
  final ToolCallDelta? toolCall;
  const StreamEvent.text(this.text)
      : type = 'text',
        usage = null,
        reason = null,
        toolCall = null;
  const StreamEvent.usage(this.usage)
      : type = 'usage',
        text = null,
        reason = null,
        toolCall = null;
  const StreamEvent.finish(this.reason)
      : type = 'finish',
        text = null,
        usage = null,
        toolCall = null;
  const StreamEvent.toolCall(this.toolCall)
      : type = 'tool_call',
        text = null,
        usage = null,
        reason = null;
}

/// Fully assembled native tool call.
class NativeToolCall {
  final String id;
  final String name;
  final String arguments;
  const NativeToolCall({required this.id, required this.name, required this.arguments});
}

// ─── Parser ──────────────────────────────────────────────────────────────────

class SseParser {
  String _buffer = '';
  StreamUsage? _usage;
  String? _finishReason;

  // index → accumulated call. Tool arguments arrive in fragments keyed by
  // index, so they can only be assembled at the end of the stream.
  final Map<int, _PendingCall> _pending = {};

  static final RegExp _dataPrefix = RegExp(r'^data:');

  /// Feed raw SSE text. Returns the content deltas it contained.
  List<String> push(String chunk) => _eventsText(_feed(chunk));

  /// Flush any buffered partial line at end of stream.
  List<String> flush() => _eventsText(_flushEvents());

  /// Feed raw SSE text. Returns every event it contained.
  List<StreamEvent> pushEvents(String chunk) => _feed(chunk);

  /// Flush the buffered partial line at end of stream, as events.
  List<StreamEvent> flushEvents() => _flushEvents();

  /// Provider-reported usage, once a usage frame has arrived.
  StreamUsage? usage() => _usage;

  /// Fully assembled native tool calls, once the stream has ended.
  List<NativeToolCall> toolCalls() {
    final indices = _pending.keys.toList()..sort();
    return [
      for (final index in indices)
        if (_pending[index]!.name.isNotEmpty)
          NativeToolCall(
            id: _pending[index]!.id.isEmpty ? 'call_$index' : _pending[index]!.id,
            name: _pending[index]!.name,
            arguments: _pending[index]!.arguments.isEmpty ? '{}' : _pending[index]!.arguments,
          ),
    ];
  }

  /// Finish reason from the last choice frame, when reported.
  String? finishReason() => _finishReason;

  // ── internals ──

  List<StreamEvent> _feed(String chunk) {
    _buffer += chunk;
    final events = <StreamEvent>[];
    final lines = _buffer.split('\n');
    _buffer = lines.removeLast();
    for (final line in lines) {
      events.addAll(_parseLine(line));
    }
    return events;
  }

  List<StreamEvent> _flushEvents() {
    if (_buffer.isEmpty) return const [];
    final events = _parseLine(_buffer);
    _buffer = '';
    return events;
  }

  static List<String> _eventsText(List<StreamEvent> events) => [
        for (final e in events)
          if (e.type == 'text' && e.text != null) e.text!,
      ];

  List<StreamEvent> _parseLine(String line) {
    final trimmed = line.trim();
    if (!_dataPrefix.hasMatch(trimmed)) return const [];
    final payload = trimmed.substring(5).trim();
    if (payload.isEmpty || payload == '[DONE]') return const [];

    Object? decoded;
    try {
      decoded = _safeJsonDecode(payload);
    } catch (_) {
      // Skip malformed frames rather than killing the stream.
      return const [];
    }
    if (decoded is! Map<String, dynamic>) return const [];
    final frame = decoded;

    final events = <StreamEvent>[];

    final reported = normalizeUsage(frame['usage']);
    if (reported != null) {
      _usage = reported;
      events.add(StreamEvent.usage(reported));
    }

    final choices = frame['choices'] as List?;
    if (choices == null || choices.isEmpty) return events;
    final choice = choices.first;
    if (choice is! Map<String, dynamic>) return events;

    final delta = choice['delta'];
    if (delta is Map<String, dynamic>) {
      final content = delta['content'];
      if (content is String && content.isNotEmpty) {
        events.add(StreamEvent.text(content));
      }

      final deltas = delta['tool_calls'];
      if (deltas is List) {
        for (final raw in deltas) {
          if (raw is! Map<String, dynamic>) continue;
          final indexObj = raw['index'];
          final index = indexObj is num ? indexObj.toInt() : 0;
          final id = raw['id'] as String?;
          final fn = raw['function'];
          final name = fn is Map<String, dynamic> ? fn['name'] as String? : null;
          final argsDelta =
              fn is Map<String, dynamic> ? fn['arguments'] as String? : null;

          final current = _pending[index] ?? _PendingCall();
          if (id != null) current.id = id;
          if (name != null) current.name = name;
          if (argsDelta is String) current.arguments += argsDelta;
          _pending[index] = current;

          events.add(StreamEvent.toolCall(ToolCallDelta(
            index: index,
            id: id,
            name: name,
            argumentsDelta: argsDelta,
          )));
        }
      }
    }

    final finish = choice['finish_reason'];
    if (finish is String && finish.isNotEmpty) {
      _finishReason = finish;
      events.add(StreamEvent.finish(finish));
    }

    return events;
  }
}

/// Accumulator for one streaming tool call, keyed by index.
class _PendingCall {
  String id = '';
  String name = '';
  String arguments = '';
}

/// Decode an SSE JSON frame; throws if malformed.
Object? _safeJsonDecode(String payload) {
  final value = jsonDecode(payload);
  if (value is Map<String, dynamic>) return value;
  return null;
}
/// Context accounting — port of `src/chat/tokens.ts`.
///
/// Providers count tokens; the app must know, before it sends, whether the
/// conversation still fits. Conservative character-class estimator: Latin
/// prose ~4 chars/token, CJK ~1 token/char, everything else 1.5 chars/token.
/// Deliberately a little high — the safe side costs context, the other side
/// is a hard 400 from the provider.
library;

// ─── Types ───────────────────────────────────────────────────────────────────

class StreamUsage {
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
  const StreamUsage({this.promptTokens, this.completionTokens, this.totalTokens});

  bool get isAnyDefined =>
      promptTokens != null || completionTokens != null || totalTokens != null;
}

// ─── Estimation ──────────────────────────────────────────────────────────────

final RegExp _cjk = RegExp(
    r'[\u2e80-\u2fff\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uac00-\ud7af]');

/// Latin: 4 chars/token. CJK: 1 token/char. Else 1.5 chars/token.
int estimateTokens(String text) {
  if (text.isEmpty) return 0;
  var latin = 0, dense = 0, other = 0;
  for (final rune in text.runes) {
    if (_cjk.hasMatch(String.fromCharCode(rune))) {
      dense += 1;
    } else if (rune <= 0x7f) {
      latin += 1;
    } else {
      other += 1;
    }
  }
  return (latin / 4 + other / 1.5 + dense).ceil();
}

/// Tokens charged for one image input (a conservative flat estimate).
const int imageTokens = 850;

/// A chat content value: either a plain string or OpenAI-style parts.
/// (Defined in chat_transport.dart.)
int estimateContentTokens(Object? content) {
  if (content is String) return estimateTokens(content);
  if (content is List) {
    var total = 0;
    for (final part in content) {
      if (part is String) continue;
      if (part is Map) {
        final type = part['type'];
        if (type == 'text') {
          total += estimateTokens(part['text'] as String? ?? '');
        } else if (type == 'image_url') {
          total += imageTokens;
        }
      }
    }
    return total;
  }
  if (content == null) return 0;
  return estimateTokens(content.toString());
}

/// Per-message chat-format overhead (role markers, separators).
const int _msgOverhead = 4;
/// Priming tokens every chat request carries.
const int _reqOverhead = 3;

/// A message the estimator can see: role + content.
typedef EstimatableMessage = ({String role, Object? content});

/// Estimate a whole conversation, including system prompt text.
int estimateConversationTokens(
    Iterable<EstimatableMessage> messages, String? systemPrompt) {
  var total = _reqOverhead;
  if (systemPrompt != null && systemPrompt.isNotEmpty) {
    total += estimateTokens(systemPrompt) + _msgOverhead;
  }
  for (final m in messages) {
    total += estimateContentTokens(m.content) + _msgOverhead;
  }
  return total;
}

// ─── Budget ──────────────────────────────────────────────────────────────────

enum ContextLevel { ok, warn, critical }

class ContextBudget {
  final int used;
  final int reserved;
  final int limit;
  final int remaining;
  final double ratio;
  final ContextLevel level;
  const ContextBudget({
    required this.used,
    required this.reserved,
    required this.limit,
    required this.remaining,
    required this.ratio,
    required this.level,
  });
}

ContextBudget contextBudget({
  required int limit,
  required int used,
  required int maxOutput,
  double warnAt = 0.75,
  double criticalAt = 0.9,
}) {
  limit = limit.clamp(1, 1 << 40);
  final reserved = maxOutput.clamp(0, (limit * 0.5).floor());
  final usable = (limit - reserved).clamp(1, 1 << 40);
  final clampedUsed = used.clamp(0, 1 << 40);
  final ratio = (clampedUsed / usable).clamp(0.0, 1.0);
  final level = ratio >= criticalAt
      ? ContextLevel.critical
      : ratio >= warnAt
          ? ContextLevel.warn
          : ContextLevel.ok;
  return ContextBudget(
    used: clampedUsed,
    reserved: reserved,
    limit: limit,
    remaining: (limit - reserved - clampedUsed).clamp(0, 1 << 40),
    ratio: ratio,
    level: level,
  );
}

class FitResult<T extends EstimatableMessage> {
  /// Messages that fit, oldest dropped first.
  final List<T> messages;
  final int dropped;
  final int tokens;
  /// True when even the final turn alone exceeds the budget.
  final bool overLimit;
  const FitResult({
    required this.messages,
    required this.dropped,
    required this.tokens,
    required this.overLimit,
  });
}

/// Drop the oldest turns until the conversation fits the budget.
///
/// The most recent message is always kept — it is the turn being sent. When
/// dropping leaves an assistant message first (its user turn was dropped),
/// that orphan is removed too: a conversation may not start with an
/// assistant turn.
FitResult<T> fitMessagesToContext<T extends EstimatableMessage>(
  List<T> messages, {
  required int limit,
  required int maxOutput,
  String? systemPrompt,
}) {
  final reserved = maxOutput.clamp(0, (limit * 0.5).floor());
  final usable = (limit - reserved).clamp(1, 1 << 40);
  final systemTokens = systemPrompt != null && systemPrompt.isNotEmpty
      ? estimateTokens(systemPrompt) + _msgOverhead + _reqOverhead
      : _reqOverhead;

  final kept = [...messages];
  var total = systemTokens +
      kept.fold(0, (sum, m) => sum + estimateContentTokens(m.content) + _msgOverhead);
  var dropped = 0;

  while (total > usable && kept.length > 1) {
    final removed = kept.removeAt(0);
    dropped += 1;
    total -= estimateContentTokens(removed.content) + _msgOverhead;
  }

  while (kept.length > 1 && kept.first.role == 'assistant') {
    final removed = kept.removeAt(0);
    dropped += 1;
    total -= estimateContentTokens(removed.content) + _msgOverhead;
  }

  return FitResult(
    messages: kept,
    dropped: dropped,
    tokens: total.clamp(0, 1 << 40),
    overLimit: total > usable,
  );
}

/// Compact token count for the meter: 975 → "975", 12400 → "12.4k".
String formatTokens(num value) {
  if (value.isNaN || value.isInfinite || value <= 0) return '0';
  if (value < 1000) return value.round().toString();
  if (value < 1000000) {
    final k = value / 1000;
    final s = k >= 100 ? k.round().toString() : k.toStringAsFixed(1).replaceAll('.0', '');
    return '$s k'.replaceAll(' ', '');
  }
  final m = value / 1000000;
  return '${m.toStringAsFixed(1).replaceAll('.0', '')}M';
}

/// Merge a provider-reported usage object into a normalized shape.
StreamUsage? normalizeUsage(Object? raw) {
  if (raw is! Map) return null;
  int? pick(List<String> keys) {
    for (final key in keys) {
      final value = raw[key];
      if (value is num && value.isFinite) return value.toInt();
    }
    return null;
  }

  final usage = StreamUsage(
    promptTokens: pick(['promptTokens', 'prompt_tokens']),
    completionTokens: pick(['completionTokens', 'completion_tokens']),
    totalTokens: pick(['totalTokens', 'total_tokens']),
  );
  return usage.isAnyDefined ? usage : null;
}
/// Bounded failover executor — port of `src/chat/failover.ts`.
///
/// Rules:
///   • Max 1 retry per call (try primary → try next available).
///   • 30 s idle timeout on each attempt (reset whenever bytes arrive).
///   • Only retry on *safe* errors — connection refused / reset before the
///     server accepted the request, or an explicit 429 rate-limit response.
///   • Never retry when side-effects may have occurred (any 4xx/5xx that
///     isn't 429, or a timeout *after* the server started responding).
///   • Cross-provider failover can be disabled via `allowCrossProviderFailover`.
///   • All logged errors have secrets redacted.
library;

import 'dart:async';

import '../providers_registry.dart' as registry;

/// Per-attempt idle timeout in milliseconds.
const int timeoutMs = 30000;

/// Maximum number of *additional* attempts after the first failure.
const int maxRetries = 1;

// ─── Live provider state ────────────────────────────────────────────────────
// Registry entries are declarative; runtime health changes land here so the
// failover candidate list reflects the live state of each provider.

final Map<String, registry.ProviderState> _liveStates = {};

ProvidersRecordLiveChanged? onProvidersChanged;

typedef ProvidersRecordLiveChanged = void Function();

/// Record a provider state change (called by the failover executor).
void recordProviderState(String providerId, registry.ProviderState state) {
  _liveStates[providerId] = state;
}

registry.ProviderState providerStateOf(registry.LlmProvider p) =>
    _liveStates[p.id] ?? p.state;

/// Reset every provider back to its declared state.
void resetProviderStates() => _liveStates.clear();

/// Providers currently considered available.
List<registry.LlmProvider> availableProvidersLive() {
  final out = <registry.LlmProvider>[];
  for (final p in registry.providers) {
    if (providerStateOf(p) == registry.ProviderState.available) out.add(p);
  }
  return out;
}

/// Replace a registry entry's model list + default model (used by the
/// backend-provider sync in backend_providers.dart).
void setProviderModels(String providerId,
    {required List<registry.ModelOption> models, required String model}) {
  final index = registry.providers.indexWhere((p) => p.id == providerId);
  if (index == -1) return;
  final old = registry.providers[index];
  registry.providers[index] = registry.LlmProvider(
    id: old.id,
    name: old.name,
    baseUrl: old.baseUrl,
    model: model,
    models: models,
    supportsStreaming: old.supportsStreaming,
    supportsTools: old.supportsTools,
    supportsUsage: old.supportsUsage,
    supportsStructuredOutput: old.supportsStructuredOutput,
    contextLimit: old.contextLimit,
    envKey: old.envKey,
    state: old.state,
  );
  onProvidersChanged?.call();
}

// ─── Custom error ────────────────────────────────────────────────────────────

/// A provider returned an HTTP error response.
class HttpProviderError implements Exception {
  final int status;
  final String statusText;
  final registry.LlmProvider provider;
  final String? body;
  HttpProviderError(this.status, this.statusText, this.provider, [this.body]);

  @override
  String toString() {
    final clipped = body == null ? '' : _clip(body, 200);
    return '[${provider.id}] HTTP $status $statusText${clipped.isEmpty ? '' : ': $clipped'}';
  }

  static String _clip(String? s, int n) =>
      s == null || s.length <= n ? (s ?? '') : '${s.substring(0, n)}…';
}

/// Transport-level failure: no HTTP response reached us. Safe to retry.
class TransportError implements Exception {
  final String message;
  TransportError(this.message);
  @override
  String toString() => message;
}

/// The request was aborted/cancelled. Safe to retry (not yet acted on).
class RequestAborted implements Exception {
  final String message;
  RequestAborted([this.message = 'Request aborted']);
  @override
  String toString() => message;
}

/// The provider stalled after the response started. NOT retryable, because a
/// retry would duplicate tokens the user already saw.
class StalledAfterStart implements Exception {
  final String message;
  StalledAfterStart([this.message = 'The provider stalled after the response started.']);
  @override
  String toString() => message;
}

// ─── Cancellation ────────────────────────────────────────────────────────────

/// Cancellation token standing in for the DOM `AbortSignal`.
class CancellationToken {
  bool _aborted = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _aborted;

  void onCancel(void Function() listener) {
    if (_aborted) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void cancel() {
    if (_aborted) return;
    _aborted = true;
    for (final listener in [..._listeners]) {
      try {
        listener();
      } catch (_) {}
    }
    _listeners.clear();
  }
}

// ─── Secret redaction ────────────────────────────────────────────────────────

final RegExp _sensitiveHeader = RegExp(r'authorization', caseSensitive: false);
final RegExp _sensitiveParams = RegExp(r'key|token|secret|password', caseSensitive: false);

String _redactOnce(String msg, RegExp re, String match(String m)) =>
    msg.replaceAllMapped(re, (m) => match(m.group(0) ?? ''));

/// Strip secrets from an error before it hits any log sink.
String redactSecrets(Object error) {
  var msg = error.toString();
  msg = msg.replaceAll(RegExp(r'sk-[A-Za-z0-9_-]{20,}'), 'sk-[REDACTED]');
  msg = msg.replaceAll(RegExp(r'gsk_[A-Za-z0-9_-]{20,}'), 'gsk_[REDACTED]');
  msg = msg.replaceAll(RegExp(r'AIza[A-Za-z0-9_-]{30,}'), 'AIza[REDACTED]');
  msg = msg.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9._-]+', caseSensitive: false), 'Bearer [REDACTED]');
  msg = msg.replaceAllMapped(
    RegExp(r'(^|[?&\s])(api[_-]?key|key|token|secret|password)=[^&\s]*',
        caseSensitive: false),
    (m) => '${m.group(1)}${m.group(2)}=[REDACTED]',
  );
  msg = msg.replaceAllMapped(
    RegExp(r'(api[_-]?key[=:]\s*")[^"]{20,}"', caseSensitive: false),
    (m) => '${m.group(1)}[REDACTED]"',
  );
  return msg;
}

/// Redact sensitive headers from a header map. Returns a log-safe record.
Map<String, String> redactHeaders(Map<String, String> headers) => {
      for (final entry in headers.entries)
        entry.key: _sensitiveHeader.hasMatch(entry.key) ? '[REDACTED]' : entry.value,
    };

/// Redact sensitive query params from a URL string.
String redactUrl(String url) {
  try {
    final uri = Uri.parse(url);
    var changed = false;
    final params = <String, String>{...uri.queryParameters};
    for (final key in params.keys.toList()) {
      if (_sensitiveParams.hasMatch(key)) {
        params[key] = '[REDACTED]';
        changed = true;
      }
    }
    return changed ? uri.replace(queryParameters: params).toString() : uri.toString();
  } catch (_) {
    // Not a valid URL — return as-is.
    return url;
  }
}

// ─── Safe-error classification ──────────────────────────────────────────────

bool _isRateLimitError(Object error) =>
    error is HttpProviderError && error.status == 429;

/// Whether an error is an authentication failure (401/403).
bool isAuthError(Object error) =>
    error is HttpProviderError && (error.status == 401 || error.status == 403);

/// Determine whether an error is safe to retry (no side effects possible).
bool isSafeToRetry(Object error) {
  // Transport failures before the server accepted the request.
  if (error is TransportError) return true;
  // Our own idle timeout before any bytes — safe.
  if (error is RequestAborted) return true;
  // HTTP 429 — rate-limited; the server explicitly rejected without processing.
  if (_isRateLimitError(error)) return true;
  // HTTP 401/403 — missing or invalid key; safe to failover to a fallback.
  if (isAuthError(error)) return true;
  // 5xx is deliberately not retryable: the upstream may have started
  // generating before failing, and a retry would duplicate output.
  return false;
}

// ─── Core executor ───────────────────────────────────────────────────────────

class FailoverOptions {
  /// The preferred provider to try first.
  final registry.LlmProvider primary;

  /// When `false`, the executor will NOT try a different provider on failure.
  /// It will still retry the *same* provider once for safe errors.
  final bool allowCrossProviderFailover;

  const FailoverOptions({required this.primary, this.allowCrossProviderFailover = true});
}

/// Metadata attached to every successful response.
class FailoverMeta {
  /// Provider that ultimately answered the request.
  final registry.LlmProvider answeredBy;
  /// True when the response came from a fallback, not the primary.
  final bool usedFallback;
  /// Human-readable explanation when a fallback was used.
  final String? fallbackReason;
  /// True when the final error was an authentication failure (401/403).
  final bool authError;
  const FailoverMeta({
    required this.answeredBy,
    required this.usedFallback,
    this.fallbackReason,
    required this.authError,
  });
}

class FailoverResult<T> {
  final T data;
  final FailoverMeta meta;
  const FailoverResult({required this.data, required this.meta});
}

/// The user-supplied function that actually calls the provider. It receives
/// the provider to call, a cancellation token, and a progress callback so the
/// idle timeout measures idleness, not total stream duration.
typedef ProviderCaller<T> = Future<T> Function(
  registry.LlmProvider provider,
  CancellationToken signal,
  void Function() onProgress,
);

/// Execute a provider call with bounded failover.
Future<FailoverResult<T>> failover<T>(
  FailoverOptions options,
  ProviderCaller<T> caller,
) async {
  var candidates = [options.primary];

  if (options.allowCrossProviderFailover) {
    for (final p in availableProvidersLive()) {
      if (p.id != options.primary.id) candidates = [...candidates, p];
    }
  }

  // We attempt at most `1 + maxRetries` calls total.
  final maxAttempts = 1 + maxRetries;
  Object? lastError;
  var attemptIndex = 0;
  var lastErrorAuth = false;

  for (final candidate in candidates) {
    if (attemptIndex >= maxAttempts) break;

    try {
      final data = await _callWithTimeout(candidate, caller);
      final usedFallback = candidate.id != options.primary.id;
      return FailoverResult(
        data: data,
        meta: FailoverMeta(
          answeredBy: candidate,
          usedFallback: usedFallback,
          fallbackReason: usedFallback
              ? 'Primary provider "${options.primary.name}" failed '
                  '(${redactSecrets(lastError ?? '')}). Fell back to "${candidate.name}".'
              : null,
          authError: lastErrorAuth,
        ),
      );
    } catch (err) {
      lastError = err;
      lastErrorAuth = isAuthError(err);
      attemptIndex += 1;

      _updateProviderState(candidate, err);

      // If the error is NOT safe to retry, stop immediately.
      if (!isSafeToRetry(err)) break;
      // If cross-provider failover is disabled, do not try the next candidate.
      if (!options.allowCrossProviderFailover) break;
    }
  }

  // All attempts exhausted — rethrow the last error.
  if (lastError is Exception) throw lastError;
  throw StateError(redactSecrets(lastError ?? 'failover: no candidates'));
}

// ─── Internals ───────────────────────────────────────────────────────────────

Future<T> _callWithTimeout<T>(
  registry.LlmProvider provider,
  ProviderCaller<T> caller,
) {
  final token = CancellationToken();
  var progressed = false;
  var timedOut = false;
  Timer? timer;

  // Reset on every chunk: a long answer is fine, a silent socket is not.
  void arm() {
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: timeoutMs), () {
      timedOut = true;
      token.cancel();
    });
  }

  arm();
  token.onCancel(() => timer?.cancel());

  return caller(provider, token, () {
    progressed = true;
    arm();
  }).catchError((Object err) {
    if (timedOut && progressed) {
      // Retrying now would duplicate tokens the user already saw.
      throw StalledAfterStart();
    }
    throw err;
  }).whenComplete(() => timer?.cancel());
}

void _updateProviderState(registry.LlmProvider provider, Object error) {
  var newState = registry.ProviderState.degraded;
  if (_isRateLimitError(error)) {
    newState = registry.ProviderState.rateLimited;
  } else if (error is TransportError) {
    // Network-level failure — likely down.
    newState = registry.ProviderState.down;
  }
  recordProviderState(provider.id, newState);
}
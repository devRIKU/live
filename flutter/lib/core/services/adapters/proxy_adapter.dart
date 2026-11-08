import 'dart:io';

import '../providers_registry.dart';

/// Proxy URL helpers — port of `src/adapters/proxy.ts`.
///
/// All LLM API calls used to go through the Vite dev-server proxy (or the
/// production reverse-proxy) at `/api/llm/<providerId>/…`.
///
/// This module builds those proxied URLs so the rest of the app never
/// handles raw upstream URLs or API keys directly.
///
/// Tauri/desktop deviation: on the desktop path the native proxy lives
/// inside the app process, so the same prefix is resolved against the
/// configured proxy base URL ([proxyBaseUrl], default `http://localhost:3001`
/// — the prototype service) instead of the browser origin. Set it from the
/// app bootstrap or `--dart-define=PROXY_BASE_URL=…`.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Local proxy prefix — must match the dev-server proxy config.
const String proxyPrefix = '/api/llm';

/// Base URL the proxy prefix is resolved against on the desktop runtime.
const String proxyBaseUrl = String.fromEnvironment(
  'PROXY_BASE_URL',
  defaultValue: 'http://localhost:3001',
);

// ---------------------------------------------------------------------------
// URL builder
// ---------------------------------------------------------------------------

/// Build the proxied chat-completions URL for the given provider.
///
/// Example:
/// ```dart
/// proxyUrl(groqProvider, '/chat/completions');
/// // → '/api/llm/groq/chat/completions'
/// ```
///
/// [provider] is the provider to build the URL for; [path] is the path
/// relative to the provider's base URL (a leading `/` is added when
/// missing).
String proxyUrl(LlmProvider provider, String path) {
  final normalised = path.startsWith('/') ? path : '/$path';
  return '$proxyPrefix/${provider.id}$normalised';
}

/// Resolve a proxied URL against the desktop proxy base URL.
///
/// The browser build could rely on same-origin relative URLs; the desktop
/// runtime needs an absolute URL, so this joins [proxyBaseUrl] with the
/// result of [proxyUrl].
String absoluteProxyUrl(LlmProvider provider, String path) {
  final base = proxyBaseUrl.endsWith('/')
      ? proxyBaseUrl.substring(0, proxyBaseUrl.length - 1)
      : proxyBaseUrl;
  return '$base${proxyUrl(provider, path)}';
}

/// Build a full upstream URL for server-side use.
///
/// Appends [path] to the provider's `baseUrl`. This is used inside the
/// proxy rewrite logic (server only) and should **never** be called from
/// frontend code.
String upstreamUrl(LlmProvider provider, String path) {
  final normalised = path.startsWith('/') ? path : '/$path';
  return '${provider.baseUrl}$normalised';
}

// ---------------------------------------------------------------------------
// Header helpers (server-side only)
// ---------------------------------------------------------------------------

/// Return an `Authorization` header value for the given provider, reading
/// the key from the process environment.
///
/// Returns `null` when the env var is not set so callers can decide how to
/// handle the missing key.
String? authHeader(LlmProvider provider) {
  final key = Platform.environment[provider.envKey];
  if (key == null || key.isEmpty) return null;

  // Google AI Studio uses a query-param key, not a Bearer token, but the
  // OpenAI-compatible endpoint still accepts Authorization.
  return 'Bearer $key';
}

/// Map of provider id → env-var name. Useful for diagnostics / startup checks.
const Map<String, String> providerEnvKeys = {
  'openrouter': 'OPENROUTER_API_KEY',
  'groq': 'GROQ_API_KEY',
  'google': 'GOOGLE_AI_KEY',
  'mistral': 'MISTRAL_API_KEY',
  'ollama': 'OLLAMA_HOST',
  'prototype': '',
};

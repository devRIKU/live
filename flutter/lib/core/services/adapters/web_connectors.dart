import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Web Connectors adapter (M11 Extension) — port of
/// `src/adapters/webConnectors.ts`.
///
/// Connects the app to external web capabilities:
/// - Live web search (DuckDuckGo / Tavily fallback)
/// - Safe web page content reader with SSRF protection
/// - Remote StreamableHTTP MCP servers
/// - External REST web APIs
///
/// Persisted in local storage and synced with the backend connector
/// registry.
///
/// Tauri/browser deviations:
/// - `localStorage` is replaced by an injectable [ConnectorStore]
///   (default: `shared_preferences`), which makes load/save async.
/// - Same-origin relative URLs (`/api/connectors/…`) are resolved against
///   [connectorApiBase] (default `http://localhost:3001`, the prototype
///   service) because the desktop app has no browser origin.
/// - The `lively:connectors-updated` window event is replaced by the
///   [connectorsUpdated] broadcast stream.

// ─── Types ──────────────────────────────────────────────────────────────────

/// Kind of external capability a connector provides.
enum ConnectorType { search, fetch, mcp, rest }

/// Lifecycle state of a connector.
enum ConnectorState { connected, ready, needsKey, error, testing }

/// One parameter property of a connector tool schema.
class ConnectorPropertySpec {
  final String type;
  final String? description;
  final List<String>? enumValues;
  const ConnectorPropertySpec({
    required this.type,
    this.description,
    this.enumValues,
  });

  factory ConnectorPropertySpec.fromJson(Map<String, dynamic> j) =>
      ConnectorPropertySpec(
        type: j['type'] as String? ?? 'string',
        description: j['description'] as String?,
        enumValues: (j['enum'] as List?)?.map((e) => '$e').toList(),
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        if (description != null) 'description': description,
        if (enumValues != null) 'enum': enumValues,
      };
}

/// OpenAI-style parameter schema of a connector tool.
class ConnectorToolParameters {
  final String type; // always 'object'
  final Map<String, ConnectorPropertySpec> properties;
  final List<String>? required;
  final bool? additionalProperties;
  const ConnectorToolParameters({
    this.type = 'object',
    this.properties = const {},
    this.required,
    this.additionalProperties,
  });

  factory ConnectorToolParameters.fromJson(Map<String, dynamic> j) =>
      ConnectorToolParameters(
        type: j['type'] as String? ?? 'object',
        properties: (j['properties'] as Map? ?? const {}).map(
          (k, v) => MapEntry(
            '$k',
            v is Map
                ? ConnectorPropertySpec.fromJson(Map<String, dynamic>.from(v))
                : const ConnectorPropertySpec(type: 'string'),
          ),
        ),
        required: (j['required'] as List?)?.map((e) => '$e').toList(),
        additionalProperties: j['additionalProperties'] as bool?,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'properties': properties.map((k, v) => MapEntry(k, v.toJson())),
        if (required != null) 'required': required,
        if (additionalProperties != null)
          'additionalProperties': additionalProperties,
      };
}

/// A tool a connector exposes to the model.
class ConnectorTool {
  final String name;
  final String description;
  final ConnectorToolParameters parameters;
  const ConnectorTool({
    required this.name,
    required this.description,
    required this.parameters,
  });

  factory ConnectorTool.fromJson(Map<String, dynamic> j) => ConnectorTool(
        name: j['name'] as String? ?? '',
        description: j['description'] as String? ?? '',
        parameters: j['parameters'] is Map
            ? ConnectorToolParameters.fromJson(
                Map<String, dynamic>.from(j['parameters'] as Map))
            : const ConnectorToolParameters(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'parameters': parameters.toJson(),
      };
}

/// One configured web connector.
class WebConnector {
  final String id;
  final String name;
  final ConnectorType type;
  final String url;
  final String? apiKey;
  final bool enabled;
  final ConnectorState state;
  final String description;
  final List<ConnectorTool> tools;
  final bool? isBuiltin;
  final int? lastTested;
  final int? latencyMs;
  final String? error;
  const WebConnector({
    required this.id,
    required this.name,
    required this.type,
    required this.url,
    this.apiKey,
    required this.enabled,
    required this.state,
    required this.description,
    this.tools = const [],
    this.isBuiltin,
    this.lastTested,
    this.latencyMs,
    this.error,
  });

  factory WebConnector.fromJson(Map<String, dynamic> j) => WebConnector(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        type: _connectorTypeFromWire(j['type'] as String?),
        url: j['url'] as String? ?? '',
        apiKey: j['apiKey'] as String?,
        enabled: j['enabled'] as bool? ?? false,
        state: _connectorStateFromWire(j['state'] as String?),
        description: j['description'] as String? ?? '',
        tools: (j['tools'] as List? ?? const [])
            .whereType<Map>()
            .map((t) => ConnectorTool.fromJson(Map<String, dynamic>.from(t)))
            .toList(),
        isBuiltin: j['isBuiltin'] as bool?,
        lastTested: (j['lastTested'] as num?)?.toInt(),
        latencyMs: (j['latencyMs'] as num?)?.toInt(),
        error: j['error'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'url': url,
        if (apiKey != null) 'apiKey': apiKey,
        'enabled': enabled,
        'state': state.name,
        'description': description,
        'tools': tools.map((t) => t.toJson()).toList(),
        if (isBuiltin != null) 'isBuiltin': isBuiltin,
        if (lastTested != null) 'lastTested': lastTested,
        if (latencyMs != null) 'latencyMs': latencyMs,
        if (error != null) 'error': error,
      };

  /// Copy with changes. [clearError] drops a previous error (a plain `null`
  /// argument cannot tell "unchanged" from "cleared").
  WebConnector copyWith({
    bool? enabled,
    ConnectorState? state,
    int? lastTested,
    int? latencyMs,
    String? error,
    bool clearError = false,
  }) =>
      WebConnector(
        id: id,
        name: name,
        type: type,
        url: url,
        apiKey: apiKey,
        enabled: enabled ?? this.enabled,
        state: state ?? this.state,
        description: description,
        tools: tools,
        isBuiltin: isBuiltin,
        lastTested: lastTested ?? this.lastTested,
        latencyMs: latencyMs ?? this.latencyMs,
        error: clearError ? null : (error ?? this.error),
      );

  /// Shallow overlay merge — the Dart analogue of `{...existing, ...item}`:
  /// only the keys present in [overlay] override this connector.
  WebConnector merge(Map<String, dynamic> overlay) {
    final merged = <String, dynamic>{...toJson(), ...overlay};
    return WebConnector.fromJson(merged);
  }

  static ConnectorType _connectorTypeFromWire(String? value) =>
      ConnectorType.values.firstWhere(
        (t) => t.name == value,
        orElse: () => ConnectorType.rest,
      );

  static ConnectorState _connectorStateFromWire(String? value) =>
      ConnectorState.values.firstWhere(
        (s) => s.name == value,
        orElse: () => ConnectorState.ready,
      );
}

ConnectorTool _tool(
  String name,
  String description,
  Map<String, ConnectorPropertySpec> properties, [
  List<String>? required,
]) =>
    ConnectorTool(
      name: name,
      description: description,
      parameters: ConnectorToolParameters(
        properties: properties,
        required: required,
        additionalProperties: false,
      ),
    );

/// Built-in connector set, ported verbatim from the TS constants.
final List<WebConnector> defaultWebConnectors = [
  WebConnector(
    id: 'web-search',
    name: 'Live Web Search',
    type: ConnectorType.search,
    url: '/api/connectors/search',
    enabled: true,
    state: ConnectorState.connected,
    description:
        'Query current real-time information, news, documentation, and live facts from the web.',
    isBuiltin: true,
    tools: [
      _tool(
        'web_search',
        'Search the live web for up-to-date information, news, facts, or technical documentation.',
        {
          'query': const ConnectorPropertySpec(
            type: 'string',
            description: 'The search keywords or question.',
          ),
          'count': const ConnectorPropertySpec(
            type: 'number',
            description: 'Maximum number of results to retrieve (1-5).',
          ),
        },
        ['query'],
      ),
    ],
  ),
  WebConnector(
    id: 'web-reader',
    name: 'Web Content Reader',
    type: ConnectorType.fetch,
    url: '/api/connectors/fetch',
    enabled: true,
    state: ConnectorState.connected,
    description:
        'Fetch and extract clean readable text and documentation from any public web page or article.',
    isBuiltin: true,
    tools: [
      _tool(
        'web_fetch',
        'Read the text content of a web page URL. Use when a link is provided or needed for citations.',
        {
          'url': const ConnectorPropertySpec(
            type: 'string',
            description: 'The full HTTP or HTTPS URL to read.',
          ),
        },
        ['url'],
      ),
    ],
  ),
  const WebConnector(
    id: 'remote-mcp',
    name: 'Remote MCP Server',
    type: ConnectorType.mcp,
    url: 'http://localhost:3001/mcp',
    enabled: false,
    state: ConnectorState.ready,
    description:
        'Connect to external tools via the standard Model Context Protocol (StreamableHTTP).',
    isBuiltin: true,
    tools: [],
  ),
  WebConnector(
    id: 'github-web',
    name: 'GitHub Web Connector',
    type: ConnectorType.rest,
    url: 'https://api.github.com',
    enabled: false,
    state: ConnectorState.ready,
    description:
        'Search public GitHub repositories, code files, and inspect issues or release notes.',
    isBuiltin: true,
    tools: [
      _tool(
        'github_search_repos',
        'Search public GitHub repositories by name, topic, or keyword.',
        {
          'query': const ConnectorPropertySpec(
            type: 'string',
            description: 'The repository search query (e.g. "tauri react template").',
          ),
        },
        ['query'],
      ),
    ],
  ),
];

// ─── Persistence ────────────────────────────────────────────────────────────

const String _storageKey = 'lively.web_connectors';

/// Async key-value persistence used by [loadWebConnectors] /
/// [saveWebConnectors] (the TS build used the synchronous `localStorage`).
abstract class ConnectorStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// Default store backed by `shared_preferences`.
class SharedPrefsConnectorStore implements ConnectorStore {
  const SharedPrefsConnectorStore();

  @override
  Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  @override
  Future<void> write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }
}

final StreamController<List<WebConnector>> _connectorsUpdatedController =
    StreamController<List<WebConnector>>.broadcast();

/// Broadcast of the connector list after every save — replacement for the
/// `lively:connectors-updated` window event.
Stream<List<WebConnector>> get connectorsUpdated =>
    _connectorsUpdatedController.stream;

/// Load connectors from local storage, merging with defaults.
Future<List<WebConnector>> loadWebConnectors(
    {ConnectorStore? store}) async {
  try {
    final connectorStore = store ?? const SharedPrefsConnectorStore();
    final raw = await connectorStore.read(_storageKey);
    if (raw == null || raw.isEmpty) return defaultWebConnectors;
    final parsed = jsonDecode(raw);
    if (parsed is! List || parsed.isEmpty) return defaultWebConnectors;

    // Merge saved custom connectors with defaults
    final map = <String, WebConnector>{};
    for (final def in defaultWebConnectors) {
      map[def.id] = def;
    }
    for (final item in parsed) {
      if (item is Map && item['id'] != null) {
        final id = '${item['id']}';
        final overlay = Map<String, dynamic>.from(item);
        final existing = map[id];
        map[id] = existing != null ? existing.merge(overlay) : WebConnector.fromJson(overlay);
      }
    }
    return map.values.toList();
  } catch (_) {
    return defaultWebConnectors;
  }
}

/// Save connectors to local storage and notify listeners.
Future<void> saveWebConnectors(
  List<WebConnector> connectors, {
  ConnectorStore? store,
}) async {
  try {
    final connectorStore = store ?? const SharedPrefsConnectorStore();
    await connectorStore.write(
        _storageKey, jsonEncode(connectors.map((c) => c.toJson()).toList()));
    if (!_connectorsUpdatedController.isClosed) {
      _connectorsUpdatedController.add(connectors);
    }
  } catch (_) {
    // Ignore storage errors
  }
}

// ─── Endpoint helpers ───────────────────────────────────────────────────────

/// Base URL the connector endpoints are resolved against on the desktop
/// runtime (no browser origin available). Override with
/// `--dart-define=CONNECTOR_API_BASE=…`.
const String connectorApiBase = String.fromEnvironment(
  'CONNECTOR_API_BASE',
  defaultValue: 'http://localhost:3001',
);

String _endpoint(String path, {String? apiBase}) {
  final base = apiBase ?? connectorApiBase;
  final normalisedBase =
      base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  final normalisedPath = path.startsWith('/') ? path : '/$path';
  return '$normalisedBase$normalisedPath';
}

// ─── Test connectivity ──────────────────────────────────────────────────────

/// Result of a connector connectivity test.
class ConnectorTestResult {
  final bool ok;
  final int latencyMs;
  final String message;
  final int? toolsCount;
  const ConnectorTestResult({
    required this.ok,
    required this.latencyMs,
    required this.message,
    this.toolsCount,
  });
}

/// Test connectivity to a connector.
Future<ConnectorTestResult> testWebConnector(
  WebConnector connector, {
  String? apiBase,
}) async {
  final stopwatch = Stopwatch()..start();
  try {
    final client = http.Client();
    try {
      if (connector.type == ConnectorType.search) {
        final res = await client.post(
          Uri.parse(_endpoint('/api/connectors/search', apiBase: apiBase)),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'query': 'test ping', 'count': 1}),
        );
        final latency = stopwatch.elapsedMilliseconds.round();
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw Exception('HTTP ${res.statusCode}: ${res.reasonPhrase}');
        }
        final data = _asJsonMap(res.body);
        final results = data['results'];
        final count = results is List ? results.length : 0;
        return ConnectorTestResult(
          ok: true,
          latencyMs: latency,
          message: 'Search online ($count results returned)',
          toolsCount: connector.tools.length,
        );
      }

      if (connector.type == ConnectorType.fetch) {
        final res = await client.post(
          Uri.parse(_endpoint('/api/connectors/fetch', apiBase: apiBase)),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'url': 'https://example.com'}),
        );
        final latency = stopwatch.elapsedMilliseconds.round();
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw Exception('HTTP ${res.statusCode}: ${res.reasonPhrase}');
        }
        return ConnectorTestResult(
          ok: true,
          latencyMs: latency,
          message: 'Web page reader active and responsive',
          toolsCount: connector.tools.length,
        );
      }

      if (connector.type == ConnectorType.mcp) {
        // Test remote MCP handshake
        final target = connector.url.startsWith('/')
            ? _endpoint(connector.url, apiBase: apiBase)
            : _endpoint(
                '/api/connectors/test?url=${Uri.encodeComponent(connector.url)}',
                apiBase: apiBase,
              );
        final headers = <String, String>{
          'Content-Type': 'application/json',
          if (connector.apiKey != null && connector.apiKey!.isNotEmpty)
            'Authorization': 'Bearer ${connector.apiKey}',
        };
        final res = await client.post(
          Uri.parse(target),
          headers: headers,
          body: jsonEncode({'method': 'ping'}),
        );
        final latency = stopwatch.elapsedMilliseconds.round();
        if (res.statusCode >= 200 && res.statusCode < 300) {
          return ConnectorTestResult(
            ok: true,
            latencyMs: latency,
            message: 'Connected to remote MCP server',
            toolsCount: connector.tools.length,
          );
        }
        return ConnectorTestResult(
          ok: false,
          latencyMs: latency,
          message: 'Server returned ${res.statusCode}',
        );
      }

      // Generic REST API check
      final res = await client.get(
        Uri.parse(connector.url),
        headers: connector.apiKey != null && connector.apiKey!.isNotEmpty
            ? {'Authorization': 'Bearer ${connector.apiKey}'}
            : const {},
      );
      final latency = stopwatch.elapsedMilliseconds.round();
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      return ConnectorTestResult(
        ok: ok,
        latencyMs: latency,
        message: ok
            ? 'Endpoint responsive (${res.statusCode})'
            : 'HTTP ${res.statusCode}',
        toolsCount: connector.tools.length,
      );
    } finally {
      client.close();
    }
  } catch (err) {
    final latency = stopwatch.elapsedMilliseconds.round();
    return ConnectorTestResult(
      ok: false,
      latencyMs: latency,
      message: err is Exception ? '$err' : err.toString(),
    );
  }
}

Map<String, dynamic> _asJsonMap(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {
    // Fall through to an empty map.
  }
  return <String, dynamic>{};
}

// ─── Live search / fetch ────────────────────────────────────────────────────

/// One live web search result.
class WebSearchResultItem {
  final String title;
  final String url;
  final String snippet;
  const WebSearchResultItem({
    required this.title,
    required this.url,
    required this.snippet,
  });

  factory WebSearchResultItem.fromJson(Map<String, dynamic> j) =>
      WebSearchResultItem(
        title: j['title'] as String? ?? '',
        url: j['url'] as String? ?? '',
        snippet: j['snippet'] as String? ?? '',
      );
}

/// Outcome of [executeWebSearch].
class WebSearchOutcome {
  final bool ok;
  final List<WebSearchResultItem>? results;
  final String? error;
  const WebSearchOutcome({required this.ok, this.results, this.error});
}

/// Outcome of [executeWebFetch].
class WebFetchOutcome {
  final bool ok;
  final String? title;
  final String? content;
  final String? error;
  const WebFetchOutcome({required this.ok, this.title, this.content, this.error});
}

/// Execute a live web search query.
Future<WebSearchOutcome> executeWebSearch(
  String query, {
  int count = 3,
  String? apiBase,
}) async {
  try {
    final res = await http.post(
      Uri.parse(_endpoint('/api/connectors/search', apiBase: apiBase)),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'query': query, 'count': count}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return WebSearchOutcome(
        ok: false,
        error: 'Search failed with HTTP ${res.statusCode}',
      );
    }
    final data = _asJsonMap(res.body);
    final rawResults = data['results'];
    final results = rawResults is List
        ? rawResults
            .whereType<Map>()
            .map((r) =>
                WebSearchResultItem.fromJson(Map<String, dynamic>.from(r)))
            .toList()
        : <WebSearchResultItem>[];
    return WebSearchOutcome(ok: true, results: results);
  } catch (err) {
    return WebSearchOutcome(
      ok: false,
      error: err is Exception ? '$err' : err.toString(),
    );
  }
}

/// Safely fetch and extract clean text from a URL.
Future<WebFetchOutcome> executeWebFetch(
  String url, {
  String? apiBase,
}) async {
  try {
    final res = await http.post(
      Uri.parse(_endpoint('/api/connectors/fetch', apiBase: apiBase)),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'url': url}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String? error;
      try {
        error = _asJsonMap(res.body)['error'] as String?;
      } catch (_) {
        // Ignore malformed error bodies
      }
      return WebFetchOutcome(
        ok: false,
        error: error ?? 'Failed to fetch URL (${res.statusCode})',
      );
    }
    final data = _asJsonMap(res.body);
    return WebFetchOutcome(
      ok: true,
      title: data['title'] as String?,
      content: data['content'] as String?,
    );
  } catch (err) {
    return WebFetchOutcome(
      ok: false,
      error: err is Exception ? '$err' : err.toString(),
    );
  }
}

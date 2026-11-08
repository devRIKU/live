import 'dart:convert';

import '../../models/models.dart';
import '../chat/chat_transport.dart' show ToolSpec;
import '../adapters/mcp_adapter.dart';
import '../adapters/web_connectors.dart';

/// Native tool definitions (port of `src/tools/nativeTools.ts`).
///
/// Modern models call functions directly instead of emitting a text
/// protocol. The app exposes a small, explicit set:
///
///   • `save_memory`     — write a durable fact the user asked to remember.
///   • `deep_research`   — open the research surface for a question.
///   • `web_search`      — live web search.
///   • `web_fetch`       — read a public web page.
///   • Web-connector tools — one function per tool on every enabled
///     connector.
///   • MCP tools         — one function per tool on every connected server.
///
/// Wire names are sanitized to `[A-Za-z0-9_-]` (the only characters every
/// provider accepts) and mapped back to the app's own names. Nothing is
/// executed until the user approves the call.
///
/// [ToolSpec] reuses `chat_transport.dart`'s OpenAI-compatible function
/// definition — the wire type `streamChat` and the chat controller accept.
///
/// One wire-shape: `chat_transport.ToolSpec` carries `name`, `description`
/// and `parameters` directly; its `toJson` adds the `type: 'function'`
/// envelope each provider expects.

// ─── Definition ─────────────────────────────────────────────────────────────

/// Converts raw JSON arguments into an approval-card call.
typedef ToolCallConverter = ToolCall Function(
  Map<String, dynamic> args,
  String id,
);

class NativeToolDefinition {
  /// Name sent on the wire.
  final String wireName;

  /// The OpenAI-compatible function definition.
  final ToolSpec spec;

  /// Convert raw JSON arguments into an approval-card call.
  final ToolCallConverter toToolCall;
  const NativeToolDefinition({
    required this.wireName,
    required this.spec,
    required this.toToolCall,
  });
}

/// Connected MCP servers and the tools they advertise.
class McpServerTools {
  final String serverId;
  final String serverName;
  final List<McpTool> tools;
  const McpServerTools({
    required this.serverId,
    required this.serverName,
    required this.tools,
  });
}

/// Built-in tools selectable via [BuildNativeToolsOptions.builtins].
enum NativeBuiltinTool {
  saveMemory('save_memory'),
  deepResearch('deep_research'),
  webSearch('web_search'),
  webFetch('web_fetch');

  final String wireName;
  const NativeBuiltinTool(this.wireName);
}

const int _maxWireName = 64;

/// Replace anything a provider might reject, and bound the length.
String sanitizeToolName(String name) => name
    .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')
    .substring(0, name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_').length.clamp(0, _maxWireName));

/// Deterministic wire name for an MCP tool.
String mcpWireName(String serverId, String toolName) =>
    sanitizeToolName('mcp__${serverId}__$toolName');

/// Read a string argument, tolerating models that send numbers.
String _stringArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  return '';
}

/// `String.prototype.slice(0, n)` equivalent (UTF-16 code units, like JS).
String _slice(String s, int n) => s.length <= n ? s : s.substring(0, n);

// ─── Built-in definitions ───────────────────────────────────────────────────

ToolCall _saveMemoryToCall(Map<String, dynamic> args, String id) {
  final fact = _stringArg(args, 'fact').trim();
  final rawCategory = _stringArg(args, 'category').trim();
  final category = rawCategory.isEmpty ? 'general' : rawCategory;
  return ToolCall(
    id: id,
    name: 'memory:save',
    description: 'Remember: ${_slice(fact, 160)}',
    args: {'fact': fact, 'category': category},
  );
}

const NativeToolDefinition _saveMemory = NativeToolDefinition(
  wireName: 'save_memory',
  spec: ToolSpec(
    name: 'save_memory',
    description:
        'Save a durable fact about the user to long-term memory. Use only when the user explicitly asks you to remember something, or states a lasting preference that will matter in future conversations.',
    parameters: {
      'type': 'object',
      'properties': {
        'fact': {
          'type': 'string',
          'description':
              'The fact to remember, written as one self-contained sentence.',
        },
        'category': {
          'type': 'string',
          'description':
              'A short category, e.g. preference, project, workflow, personal.',
        },
      },
      'required': ['fact'],
      'additionalProperties': false,
    },
  ),
  toToolCall: _saveMemoryToCall,
);

ToolCall _deepResearchToCall(Map<String, dynamic> args, String id) {
  final query = _stringArg(args, 'query').trim();
  return ToolCall(
    id: id,
    name: 'research:start',
    description: 'Research: ${_slice(query, 160)}',
    args: {'query': query},
  );
}

const NativeToolDefinition _deepResearch = NativeToolDefinition(
  wireName: 'deep_research',
  spec: ToolSpec(
    name: 'deep_research',
    description:
        'Run a multi-step research job and open the research surface with cited sources. Use for questions that need current information from several sources.',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description':
              'The research question, phrased so a search engine can answer it.',
        },
      },
      'required': ['query'],
      'additionalProperties': false,
    },
  ),
  toToolCall: _deepResearchToCall,
);

ToolCall _webSearchToCall(Map<String, dynamic> args, String id) {
  final query = _stringArg(args, 'query').trim();
  final countArg = args['count'];
  final count = countArg is num ? countArg : 3;
  return ToolCall(
    id: id,
    name: 'web:search',
    description: 'Web Search: "${_slice(query, 140)}"',
    args: {'query': query, 'count': count},
  );
}

const NativeToolDefinition _webSearch = NativeToolDefinition(
  wireName: 'web_search',
  spec: ToolSpec(
    name: 'web_search',
    description:
        'Search the live web for up-to-date information, news, current events, documentation, or facts that require live web sources.',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description': 'The search query or keywords to look up on the web.',
        },
        'count': {
          'type': 'number',
          'description': 'Number of results to retrieve (1-5). Defaults to 3.',
        },
      },
      'required': ['query'],
      'additionalProperties': false,
    },
  ),
  toToolCall: _webSearchToCall,
);

ToolCall _webFetchToCall(Map<String, dynamic> args, String id) {
  final url = _stringArg(args, 'url').trim();
  return ToolCall(
    id: id,
    name: 'web:fetch',
    description: 'Read Web Page: ${_slice(url, 120)}',
    args: {'url': url},
  );
}

const NativeToolDefinition _webFetch = NativeToolDefinition(
  wireName: 'web_fetch',
  spec: ToolSpec(
    name: 'web_fetch',
    description:
        'Fetch and extract the readable text and markdown from a public web URL. Use when a specific URL or web page article needs to be read.',
    parameters: {
      'type': 'object',
      'properties': {
        'url': {
          'type': 'string',
          'description': 'The full HTTP or HTTPS URL to fetch and read.',
        },
      },
      'required': ['url'],
      'additionalProperties': false,
    },
  ),
  toToolCall: _webFetchToCall,
);

const Map<NativeBuiltinTool, NativeToolDefinition> _builtins = {
  NativeBuiltinTool.saveMemory: _saveMemory,
  NativeBuiltinTool.deepResearch: _deepResearch,
  NativeBuiltinTool.webSearch: _webSearch,
  NativeBuiltinTool.webFetch: _webFetch,
};

// ─── Builder ────────────────────────────────────────────────────────────────

class BuildNativeToolsOptions {
  /// Connected MCP servers and the tools they advertise.
  final List<McpServerTools> mcpServers;

  /// Active Web Connectors.
  final List<WebConnector> connectors;

  /// Which built-ins to expose. Defaults to all 4.
  final List<NativeBuiltinTool> builtins;

  /// Hard cap across all providers.
  final int maxTools;
  const BuildNativeToolsOptions({
    this.mcpServers = const [],
    this.connectors = const [],
    this.builtins = const [
      NativeBuiltinTool.saveMemory,
      NativeBuiltinTool.deepResearch,
      NativeBuiltinTool.webSearch,
      NativeBuiltinTool.webFetch,
    ],
    this.maxTools = 32,
  });
}

/// Build the function list for one request.
///
/// The order is stable (built-ins first, then connectors, then MCP in
/// server order) so prompt caching is not invalidated by an unstable tool
/// array.
List<NativeToolDefinition> buildNativeTools(
    [BuildNativeToolsOptions opts = const BuildNativeToolsOptions()]) {
  final defs = <NativeToolDefinition>[];

  for (final id in opts.builtins) {
    final def = _builtins[id];
    if (def != null) defs.add(def);
  }

  // Register tools from active Web Connectors
  for (final conn in opts.connectors) {
    if (!conn.enabled) continue;
    for (final tool in conn.tools) {
      final wireName = sanitizeToolName('conn__${conn.id}__${tool.name}');
      if (defs.any((d) => d.wireName == wireName)) continue;
      final fallbackName = '${tool.name} via ${conn.name}';
      final description = tool.description.isEmpty
          ? fallbackName
          : tool.description;
      defs.add(NativeToolDefinition(
        wireName: wireName,
        spec: ToolSpec(
          name: wireName,
          description: _slice(description, 500),
          parameters: tool.parameters.toJson(),
        ),
        toToolCall: (args, id) => ToolCall(
          id: id,
          name: 'connector:${conn.id}:${tool.name}',
          description: '${conn.name}: ${description}',
          args: args,
        ),
      ));
    }
  }

  for (final server in opts.mcpServers) {
    for (final tool in server.tools) {
      final wireName = mcpWireName(server.serverId, tool.name);
      if (defs.any((d) => d.wireName == wireName)) continue;
      final fallbackName = '${tool.name} on ${server.serverName}';
      final description = tool.description ?? fallbackName;
      final parameters = tool.inputSchema is Map
          ? tool.inputSchema!
          : <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{},
            };
      defs.add(NativeToolDefinition(
        wireName: wireName,
        spec: ToolSpec(
          name: wireName,
          description: _slice(description, 500),
          parameters: parameters,
        ),
        toToolCall: (args, id) => ToolCall(
          id: id,
          name: 'mcp:${server.serverId}:${tool.name}',
          description:
              '${server.serverName}: ${tool.description ?? tool.name}',
          args: args,
        ),
      ));
    }
  }

  return defs.length > opts.maxTools
      ? defs.sublist(0, opts.maxTools)
      : defs;
}

/// The wire specs for a definition list.
List<ToolSpec> toolSpecs(List<NativeToolDefinition> defs) =>
    defs.map((d) => d.spec).toList();

/// Resolve a native call name back to its definition.
NativeToolDefinition? findNativeTool(
  List<NativeToolDefinition> defs,
  String wireName,
) {
  for (final d in defs) {
    if (d.wireName == wireName) return d;
  }
  return null;
}

/// One provider-native tool call, as reported by the chat transport.
class ProviderToolCall {
  final String id;
  final String name;

  /// Raw JSON arguments string from the provider.
  final String arguments;
  const ProviderToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });
}

/// Convert provider-native tool calls into approval-card calls.
///
/// Unknown names are surfaced as a call that the executor will reject,
/// rather than dropped silently — the user should see what the model tried
/// to do.
List<ToolCall> toApprovalCalls(
  List<NativeToolDefinition> defs,
  List<ProviderToolCall> calls,
) {
  return calls.map((call) {
    var args = <String, dynamic>{};
    try {
      final source = call.arguments.isEmpty ? '{}' : call.arguments;
      final parsed = jsonDecode(source);
      if (parsed is Map) {
        args = Map<String, dynamic>.from(parsed);
      }
      // Valid JSON that is not an object (array/string/number) keeps the
      // empty args, exactly like the TS implementation.
    } catch (_) {
      args = {'__raw': call.arguments};
    }

    final def = findNativeTool(defs, call.name);
    if (def != null) return def.toToolCall(args, call.id);
    return ToolCall(
      id: call.id,
      name: call.name,
      description: 'Unknown tool "${call.name}"',
      args: args,
    );
  }).toList();
}

import 'dart:convert';

import 'mcp_adapter.dart';

/// Local MCP adapter — port of `src/adapters/localMcp.ts`.
///
/// Calls local stdio MCP servers (e.g. `npx @some/mcp-server`) by spawning
/// the configured command with `dart:io` `Process` and speaking JSON-RPC
/// over its stdio pipes. The TS build delegated this to the Tauri native
/// side (`call_local_mcp_tool` in agent.rs); in the Flutter port Dart *is*
/// the native side, so the process is spawned directly.
///
/// Every call is gated behind user approval. Servers are registered with
/// [LocalMcpClient.addServer]; calls use `mcp:<serverId>:<toolName>`
/// wire names produced by `native_tools.dart`.
///
/// Framing: one JSON-RPC message per line by default (the MCP stdio spec);
/// set [LocalMcpServer.framing] to [McpFraming.contentLength] for servers
/// that use LSP-style `Content-Length` headers.

/// A registered local MCP server.
class LocalMcpServer {
  final String id;
  final String name;

  /// The command to spawn (e.g. "npx").
  final String command;

  /// Arguments to the command.
  final List<String> args;

  /// Working directory for the spawned process.
  final String workingDir;

  /// JSON-RPC framing spoken by this server.
  final McpFraming framing;

  const LocalMcpServer({
    required this.id,
    required this.name,
    required this.command,
    this.args = const [],
    required this.workingDir,
    this.framing = McpFraming.newline,
  });
}

/// Result of a local MCP tool call.
class LocalMcpResult {
  final bool ok;
  final String? output;
  final String? error;
  const LocalMcpResult({required this.ok, this.output, this.error});
}

const Duration _localMcpTimeout = Duration(seconds: 60);

/// Client for local stdio MCP servers.
///
/// Register servers with [addServer], then call tools via
/// [callLocalTool]. Each call spawns the configured command, performs the
/// MCP `initialize` handshake, sends a `tools/call` JSON-RPC message, reads
/// the response from stdout, and returns the parsed output.
class LocalMcpClient {
  final Map<String, LocalMcpServer> _servers = <String, LocalMcpServer>{};

  /// Register a local MCP server. Called from app init or Settings.
  void addServer(LocalMcpServer server) {
    _servers[server.id] = server;
  }

  /// Look up a registered server by id. Returns null when not found.
  LocalMcpServer? getServer(String serverId) => _servers[serverId];

  /// List all registered server ids.
  List<String> listServers() => _servers.keys.toList();

  /// Call a tool on a registered local MCP server.
  ///
  /// Spawns the command, sends `tools/call`, returns parsed stdout.
  /// [targetPath] is accepted for API parity with the TS signature and is
  /// unused by the stdio transport.
  Future<LocalMcpResult> callLocalTool(
    String serverId,
    String toolName,
    Map<String, dynamic> args, [
    String? targetPath,
  ]) async {
    final server = _servers[serverId];
    if (server == null) {
      return LocalMcpResult(
        ok: false,
        error: 'Local MCP server "$serverId" not configured',
      );
    }

    McpStdioConnection? connection;
    try {
      connection = await McpStdioConnection.spawn(
        command: server.command,
        args: server.args,
        workingDirectory: server.workingDir,
        framing: server.framing,
        killOnClose: true,
        requestTimeout: _localMcpTimeout,
      );

      await connection.initialize();
      final frame = await connection.request('tools/call', {
        'name': toolName,
        'arguments': args,
      });

      var output = frame.raw.trim();
      try {
        final parsed = jsonDecode(output);
        if (parsed is Map) {
          if (parsed['result'] != null) {
            output = const JsonEncoder.withIndent('  ').convert(parsed['result']);
          } else if (parsed['error'] != null) {
            return LocalMcpResult(
              ok: false,
              error: _jsonRpcErrorMessage(parsed['error']),
            );
          }
        }
      } catch (_) {
        // Not JSON — return raw text as-is.
      }

      return LocalMcpResult(ok: true, output: output);
    } catch (err) {
      return LocalMcpResult(ok: false, error: err.toString());
    } finally {
      // Always tear down the spawned process.
      try {
        await connection?.close();
      } catch (_) {
        // Ignore cleanup error.
      }
    }
  }

  /// Mirrors the TS `String(parsed.error.message ?? parsed.error)`.
  static String _jsonRpcErrorMessage(Object? error) {
    if (error is String) return error;
    if (error is Map) {
      final message = error['message'];
      if (message != null && '$message'.isNotEmpty) return '$message';
      // The TS build rendered non-message error objects as
      // "[object Object]"; JSON is strictly more useful here.
      return jsonEncode(error);
    }
    return '$error';
  }
}

/// Shared client instance.
final LocalMcpClient localMcpClient = LocalMcpClient();

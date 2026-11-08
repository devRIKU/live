import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/models.dart';

/// MCP adapter — port of `src/adapters/mcp.ts`.
///
/// The TS build used `@modelcontextprotocol/sdk` (`Client` +
/// `StreamableHTTPClientTransport`). The Dart port implements the JSON-RPC
/// framing itself:
///
///   • HTTP transport — StreamableHTTP: `POST` a JSON-RPC message with
///     `Content-Type: application/json` and `Accept: application/json,
///     text/event-stream`, honour the `Mcp-Session-Id` response header, and
///     parse either a single JSON body or an `text/event-stream` (SSE) body.
///   • stdio transport — newline-delimited JSON per the MCP stdio spec, with
///     an optional LSP-style `Content-Length` framing for servers that need
///     it (see [McpFraming]).
///
/// Every tool call is gated behind user approval (see the approval layer).
/// The client never executes a tool on its own — it only provides listTools
/// + callTool, and the caller must obtain approval before calling callTool.
///
/// Tauri deviation: none required — the MCP SDK is replaced by plain
/// `package:http` + `dart:io` (Process/Socket), both fully portable.

// ─── Constants ──────────────────────────────────────────────────────────────

/// Latest MCP protocol version spoken by this client.
const String mcpProtocolVersion = '2025-06-18';

/// Client identification sent in `initialize`.
const String mcpClientName = 'openall';
const String mcpClientVersion = '0.1.0';

/// Default per-request timeout.
const Duration mcpRequestTimeout = Duration(seconds: 30);

// ─── Wire types ─────────────────────────────────────────────────────────────

/// A remote (or local) MCP server entry.
class McpServer {
  final String id;
  final String name;
  final String url;

  /// `http` (default) speaks StreamableHTTP; `stdio` spawns [command].
  final McpTransport transport;

  /// Command to spawn for [McpTransport.stdio] (e.g. `npx`).
  final String? command;
  final List<String> args;
  final String? workingDir;

  /// Framing used by the stdio transport.
  final McpFraming framing;

  /// Extra HTTP headers (Authorization etc.) for the HTTP transport.
  final Map<String, String> headers;

  const McpServer({
    required this.id,
    required this.name,
    required this.url,
    this.transport = McpTransport.http,
    this.command,
    this.args = const [],
    this.workingDir,
    this.framing = McpFraming.newline,
    this.headers = const {},
  });
}

/// Transport selection for [McpServer].
enum McpTransport { http, stdio }

/// Wire framing for message-oriented byte streams.
///
/// - [newline] — one JSON object per line (the MCP stdio spec).
/// - [contentLength] — LSP-style `Content-Length: <n>\r\n\r\n<body>` headers,
///   used by a few servers that reuse the LSP transport.
enum McpFraming { newline, contentLength }

/// Minimal tool descriptor returned by `tools/list`.
class McpTool {
  final String name;
  final String? description;
  final Map<String, dynamic>? inputSchema;
  const McpTool({
    required this.name,
    this.description,
    this.inputSchema,
  });

  factory McpTool.fromJson(Map<String, dynamic> j) => McpTool(
        name: j['name'] as String? ?? '',
        description: j['description'] as String?,
        inputSchema: j['inputSchema'] is Map
            ? Map<String, dynamic>.from(j['inputSchema'] as Map)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (description != null) 'description': description,
        if (inputSchema != null) 'inputSchema': inputSchema,
      };
}

/// A decoded JSON-RPC frame: the raw text plus (when it parsed) the message.
class McpRpcFrame {
  final String raw;
  final Map<String, dynamic>? message;
  const McpRpcFrame({required this.raw, this.message});

  bool get hasError => message?['error'] != null;

  /// The `error` object of a JSON-RPC error response.
  Map<String, dynamic>? get error {
    final e = message?['error'];
    return e is Map ? Map<String, dynamic>.from(e) : null;
  }

  /// The `result` object of a JSON-RPC response.
  Map<String, dynamic>? get result {
    final r = message?['result'];
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }
}

/// JSON-RPC error raised while talking to an MCP server.
class McpRpcException implements Exception {
  final int? code;
  final String message;
  const McpRpcException({this.code, required this.message});

  @override
  String toString() =>
      'McpRpcException(${code ?? '-'}): $message';
}

// ─── JSON-RPC framing ───────────────────────────────────────────────────────

/// Encodes one JSON-RPC payload according to [framing].
List<int> encodeMcpFrame(String payload, McpFraming framing) {
  final body = utf8.encode(payload);
  switch (framing) {
    case McpFraming.newline:
      return [...body, 0x0a];
    case McpFraming.contentLength:
      final header = 'Content-Length: ${body.length}\r\n\r\n';
      return [...utf8.encode(header), ...body];
  }
}

/// Incremental frame decoder for MCP byte streams (stdio / sockets).
class McpFrameDecoder {
  McpFrameDecoder({this.framing = McpFraming.newline});

  final McpFraming framing;
  final List<int> _buffer = <int>[];

  /// Feed raw bytes into the decoder.
  void add(List<int> chunk) => _buffer.addAll(chunk);

  /// Pop the next complete frame, or `null` when more bytes are needed.
  String? next() {
    switch (framing) {
      case McpFraming.newline:
        final idx = _buffer.indexOf(0x0a); // '\n'
        if (idx < 0) return null;
        var end = idx;
        if (end > 0 && _buffer[end - 1] == 0x0d) end--; // strip '\r'
        final line = utf8.decode(_buffer.sublist(0, end));
        _buffer.removeRange(0, idx + 1);
        return line;
      case McpFraming.contentLength:
        const separator = [0x0d, 0x0a, 0x0d, 0x0a]; // \r\n\r\n
        final sepIdx = _indexOf(_buffer, separator);
        if (sepIdx < 0) return null;
        final headerText =
            utf8.decode(_buffer.sublist(0, sepIdx), allowMalformed: true);
        int? contentLength;
        for (final line in headerText.split('\r\n')) {
          final colon = line.indexOf(':');
          if (colon > 0 &&
              line.substring(0, colon).trim().toLowerCase() ==
                  'content-length') {
            contentLength = int.tryParse(line.substring(colon + 1).trim());
          }
        }
        if (contentLength == null) {
          // Malformed header — drop it so the stream can resynchronise.
          _buffer.removeRange(0, sepIdx + separator.length);
          return null;
        }
        final bodyStart = sepIdx + separator.length;
        if (_buffer.length < bodyStart + contentLength) return null;
        final body =
            utf8.decode(_buffer.sublist(bodyStart, bodyStart + contentLength));
        _buffer.removeRange(0, bodyStart + contentLength);
        return body;
    }
  }

  static int _indexOf(List<int> haystack, List<int> needle) {
    outer:
    for (var i = 0; i <= haystack.length - needle.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}

// ─── Connections ────────────────────────────────────────────────────────────

/// A live connection to one MCP server.
abstract class McpConnection {
  /// Perform the `initialize` handshake + `notifications/initialized`.
  Future<void> initialize();

  /// Send a JSON-RPC request and await its frame (error responses are
  /// returned as frames — callers decide whether to throw).
  Future<McpRpcFrame> request(String method, [Map<String, dynamic>? params]);

  /// Close the transport (kill the process / socket / HTTP session).
  Future<void> close();
}

/// StreamableHTTP MCP client (port of the SDK's
/// `StreamableHTTPClientTransport`).
class McpHttpConnection implements McpConnection {
  McpHttpConnection(
    this.url, {
    this.headers = const {},
    http.Client? client,
    this.requestTimeout = mcpRequestTimeout,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String url;
  final Map<String, String> headers;
  final http.Client _client;
  final bool _ownsClient;
  final Duration requestTimeout;

  String? _sessionId;
  int _nextId = 1;

  Future<http.Response> _post(Map<String, dynamic> body) async {
    final request = http.Request('POST', Uri.parse(url));
    request.headers['Content-Type'] = 'application/json';
    request.headers['Accept'] = 'application/json, text/event-stream';
    if (_sessionId != null) request.headers['mcp-session-id'] = _sessionId!;
    headers.forEach((k, v) => request.headers[k] = v);
    request.body = jsonEncode(body);
    final response = await http.Response.fromStream(await _client.send(request))
        .timeout(requestTimeout);
    // The server assigns a session on `initialize` and echoes it back.
    final sessionId = response.headers['mcp-session-id'];
    if (sessionId != null && sessionId.isNotEmpty) _sessionId = sessionId;
    if (response.statusCode >= 400) {
      throw McpRpcException(
        code: response.statusCode,
        message: 'MCP HTTP ${response.statusCode}: ${response.body}',
      );
    }
    return response;
  }

  /// Parses a StreamableHTTP response body: SSE stream or plain JSON.
  List<Map<String, dynamic>> _parseBody(http.Response response) {
    final contentType =
        (response.headers['content-type'] ?? '').toLowerCase();
    if (response.body.isEmpty) return const [];
    if (contentType.contains('text/event-stream')) {
      final messages = <Map<String, dynamic>>[];
      for (final block in response.body.split('\n\n')) {
        for (final line in block.split('\n')) {
          if (line.startsWith('data:')) {
            final data = line.substring(5).trim();
            if (data.isEmpty || data == '[DONE]') continue;
            try {
              final decoded = jsonDecode(data);
              if (decoded is Map) {
                messages.add(Map<String, dynamic>.from(decoded));
              }
            } catch (_) {
              // Ignore malformed SSE data frames.
            }
          }
        }
      }
      return messages;
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) return [Map<String, dynamic>.from(decoded)];
    } catch (_) {
      // Empty / non-JSON body (e.g. 202 Accepted).
    }
    return const [];
  }

  Future<McpRpcFrame> _exchange(Map<String, dynamic> body) async {
    final response = await _post(body);
    final messages = _parseBody(response);
    final id = body['id'];
    for (final message in messages) {
      if (message['id'] == id) {
        return McpRpcFrame(raw: response.body, message: message);
      }
    }
    if (messages.isEmpty) {
      return McpRpcFrame(raw: response.body);
    }
    // Response did not echo the id (should not happen) — return the first.
    return McpRpcFrame(raw: response.body, message: messages.first);
  }

  @override
  Future<void> initialize() async {
    final frame = await _exchange({
      'jsonrpc': '2.0',
      'id': _nextId++,
      'method': 'initialize',
      'params': {
        'protocolVersion': mcpProtocolVersion,
        'capabilities': <String, dynamic>{},
        'clientInfo': {'name': mcpClientName, 'version': mcpClientVersion},
      },
    });
    // The session id is returned in the `Mcp-Session-Id` header by _post;
    // it was captured there on the initialize exchange.
    if (frame.hasError) {
      final error = frame.error!;
      throw McpRpcException(
        code: error['code'] is int ? error['code'] as int : null,
        message: '${error['message'] ?? 'initialize failed'}',
      );
    }
    // Accept the negotiated protocol version if the server downgraded it.
    final serverVersion =
        frame.result?['protocolVersion'];
    if (serverVersion is String && serverVersion.isNotEmpty) {
      // Recorded for diagnostics only — this client speaks 2025-06-18.
    }
    await _post({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
  }

  @override
  Future<McpRpcFrame> request(String method,
      [Map<String, dynamic>? params]) async {
    final body = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': _nextId++,
      'method': method,
      if (params != null) 'params': params,
    };
    final frame = await _exchange(body);
    if (frame.hasError) {
      final error = frame.error!;
      throw McpRpcException(
        code: error['code'] is int ? error['code'] as int : null,
        message: '${error['message'] ?? 'request failed'}',
      );
    }
    if (frame.message == null) {
      throw const McpRpcException(message: 'Empty MCP response body');
    }
    return frame;
  }

  @override
  Future<void> close() async {
    // Best-effort session termination (StreamableHTTP DELETE).
    final sessionId = _sessionId;
    if (sessionId != null) {
      try {
        final request = http.Request('DELETE', Uri.parse(url));
        request.headers['mcp-session-id'] = sessionId;
        headers.forEach((k, v) => request.headers[k] = v);
        await _client.send(request).timeout(const Duration(seconds: 5));
      } catch (_) {
        // Session may already be gone.
      }
    }
    if (_ownsClient) _client.close();
  }
}

/// stdio / socket MCP connection (JSON-RPC over a byte stream).
class McpStdioConnection implements McpConnection {
  McpStdioConnection._({
    required IOSink sink,
    required Stream<List<int>> stream,
    required this.framing,
    this.requestTimeout = mcpRequestTimeout,
    Process? process,
    Socket? socket,
    bool killOnClose = false,
  })  : _sink = sink,
        _process = process,
        _socket = socket,
        _killOnClose = killOnClose {
    _decoder = McpFrameDecoder(framing: framing);
    _sub = stream.listen(
      _onBytes,
      onDone: _onClosed,
      onError: (Object _) => _onClosed(),
    );
  }

  /// Wrap an already-spawned MCP server process.
  factory McpStdioConnection.fromProcess(
    Process process, {
    McpFraming framing = McpFraming.newline,
    bool killOnClose = false,
    Duration requestTimeout = mcpRequestTimeout,
  }) {
    return McpStdioConnection._(
      sink: process.stdin,
      stream: process.stdout,
      framing: framing,
      process: process,
      killOnClose: killOnClose,
      requestTimeout: requestTimeout,
    );
  }

  /// Connect to an MCP server over a TCP socket (dart:io [Socket]).
  factory McpStdioConnection.fromSocket(
    Socket socket, {
    McpFraming framing = McpFraming.newline,
    Duration requestTimeout = mcpRequestTimeout,
  }) {
    return McpStdioConnection._(
      sink: socket,
      stream: socket,
      framing: framing,
      socket: socket,
      requestTimeout: requestTimeout,
    );
  }

  /// Spawn a local MCP server command and connect over its stdio pipes.
  ///
  /// [runInShell] defaults to `true` on Windows so commands like `npx`
  /// (which are `.cmd` shims) resolve, matching how the TS/Rust side
  /// spawned them.
  static Future<McpStdioConnection> spawn({
    required String command,
    List<String> args = const [],
    String? workingDirectory,
    Map<String, String>? environment,
    McpFraming framing = McpFraming.newline,
    bool? runInShell,
    bool killOnClose = true,
    Duration requestTimeout = mcpRequestTimeout,
  }) async {
    final process = await Process.start(
      command,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: runInShell ?? Platform.isWindows,
    );
    // Drain stderr so the pipe never blocks; retained for diagnostics.
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_stderrLog.write);
    return McpStdioConnection.fromProcess(
      process,
      framing: framing,
      killOnClose: killOnClose,
      requestTimeout: requestTimeout,
    );
  }

  static final StringBuffer _stderrLog = StringBuffer();

  /// Diagnostic text captured from the child process stderr.
  static String get stderrText => _stderrLog.toString();

  final IOSink _sink;
  final Process? _process;
  final Socket? _socket;
  final bool _killOnClose;
  final McpFraming framing;
  final Duration requestTimeout;

  late final McpFrameDecoder _decoder;
  late final StreamSubscription<List<int>> _sub;

  int _nextId = 1;
  bool _closed = false;
  final Map<int, Completer<McpRpcFrame>> _pendingById = {};
  final List<Completer<McpRpcFrame>> _pendingOrder = [];

  void _onBytes(List<int> chunk) {
    _decoder.add(chunk);
    String? frame;
    while ((frame = _decoder.next()) != null) {
      _onFrame(frame!);
    }
  }

  void _onFrame(String raw) {
    Map<String, dynamic>? message;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) message = Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Not JSON — handled below as an unmatched raw frame.
    }

    if (message != null) {
      final id = message['id'];
      if (id is int) {
        final completer = _pendingById.remove(id);
        if (completer != null) {
          _pendingOrder.remove(completer);
          completer.complete(McpRpcFrame(raw: raw, message: message));
          return;
        }
      }
      // Server-initiated notification / request — not ours, ignore.
      return;
    }

    // Unparseable frame: hand it to the oldest waiter (stdio is
    // request/response sequential for this client).
    if (_pendingOrder.isNotEmpty) {
      final completer = _pendingOrder.removeAt(0);
      completer.complete(McpRpcFrame(raw: raw));
    }
  }

  void _onClosed() {
    _closed = true;
    final detail = stderrText.trim().isEmpty
        ? ''
        : ' — stderr: ${stderrText.trim().split('\n').take(5).join(' | ')}';
    while (_pendingOrder.isNotEmpty) {
      final completer = _pendingOrder.removeAt(0);
      if (!completer.isCompleted) {
        completer.completeError(
          McpRpcException(message: 'MCP connection closed$detail'),
        );
      }
    }
    _pendingById.clear();
  }

  @override
  Future<void> initialize() async {
    final frame = await request('initialize', {
      'protocolVersion': mcpProtocolVersion,
      'capabilities': <String, dynamic>{},
      'clientInfo': {'name': mcpClientName, 'version': mcpClientVersion},
    });
    if (frame.hasError) {
      final error = frame.error!;
      throw McpRpcException(
        code: error['code'] is int ? error['code'] as int : null,
        message: '${error['message'] ?? 'initialize failed'}',
      );
    }
    // Notification — no response expected.
    _write({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
  }

  void _write(Map<String, dynamic> message) {
    if (_closed) {
      throw const McpRpcException(message: 'MCP connection is closed');
    }
    _sink.add(encodeMcpFrame(jsonEncode(message), framing));
    _sink.flush().catchError((_) {});
  }

  @override
  Future<McpRpcFrame> request(String method,
      [Map<String, dynamic>? params]) async {
    final id = _nextId++;
    final completer = Completer<McpRpcFrame>();
    _pendingById[id] = completer;
    _pendingOrder.add(completer);
    _write({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    });
    try {
      final frame = await completer.future.timeout(requestTimeout);
      if (frame.hasError) {
        final error = frame.error!;
        throw McpRpcException(
          code: error['code'] is int ? error['code'] as int : null,
          message: '${error['message'] ?? 'request failed'}',
        );
      }
      return frame;
    } on TimeoutException {
      _pendingById.remove(id);
      _pendingOrder.remove(completer);
      throw McpRpcException(message: 'MCP request "$method" timed out');
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub.cancel();
    try {
      await _sink.close();
    } catch (_) {
      // Already closed.
    }
    if (_killOnClose && _process != null) {
      _process!.kill();
      try {
        await _process!.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {
        _process!.kill(ProcessSignal.sigkill);
      }
    }
    _socket?.destroy();
    _onClosed();
  }
}

// ─── Client ─────────────────────────────────────────────────────────────────

/// MCP client for remote (StreamableHTTP) and local (stdio) MCP servers.
///
/// Connects to remote MCP servers over StreamableHTTP. Every tool call is
/// gated behind user approval. The client never executes a tool on its own —
/// it only provides listTools + callTool, and the caller must obtain
/// approval before calling callTool.
class RemoteMcpClient {
  final Map<String, McpConnection> _connections = <String, McpConnection>{};

  /// Ids of the servers that are currently connected.
  List<String> get connectedServerIds => _connections.keys.toList();

  /// Connect to a remote MCP server (HTTP, or stdio when configured).
  Future<void> connect(McpServer server) async {
    final McpConnection connection;
    if (server.transport == McpTransport.stdio) {
      connection = await McpStdioConnection.spawn(
        command: server.command ?? server.url,
        args: server.args,
        workingDirectory: server.workingDir,
        framing: server.framing,
      );
    } else {
      connection = McpHttpConnection(server.url, headers: server.headers);
    }
    try {
      await connection.initialize();
    } catch (_) {
      await connection.close();
      rethrow;
    }
    _connections[server.id] = connection;
  }

  /// List available tools from a connected server.
  Future<List<McpTool>> listTools(String serverId) async {
    final connection = _connections[serverId];
    if (connection == null) {
      throw Exception('MCP server "$serverId" is not connected');
    }
    final frame = await connection.request('tools/list');
    final tools = frame.result?['tools'];
    if (tools is! List) return const [];
    return tools
        .whereType<Map>()
        .map((t) => McpTool.fromJson(Map<String, dynamic>.from(t)))
        .toList();
  }

  /// Call a tool on a connected server. Caller must have obtained approval.
  Future<ToolResult> callTool(
    String serverId,
    String name,
    Map<String, dynamic> args,
  ) async {
    final connection = _connections[serverId];
    if (connection == null) {
      return ToolResult(
        ok: false,
        error: 'MCP server "$serverId" is not connected',
      );
    }
    try {
      final frame = await connection
          .request('tools/call', {'name': name, 'arguments': args});
      final content = frame.result?['content'];
      if (content is! List) return const ToolResult(ok: true);
      final parts = content.map((c) {
        if (c is Map && c['type'] == 'text') {
          return '${c['text'] ?? ''}';
        }
        return jsonEncode(c);
      }).join('\n');
      return ToolResult(ok: true, output: parts);
    } catch (err) {
      return ToolResult(ok: false, error: _errorText(err));
    }
  }

  static String _errorText(Object err) {
    if (err is McpRpcException) return err.message;
    if (err is Exception) return err.toString().replaceFirst('Exception: ', '');
    return err.toString();
  }

  /// Disconnect a server.
  Future<void> disconnect(String serverId) async {
    final connection = _connections.remove(serverId);
    if (connection != null) {
      try {
        await connection.close();
      } catch (_) {
        // Best effort.
      }
    }
  }
}

/// Shared client instance.
final RemoteMcpClient mcpClient = RemoteMcpClient();

/// Riverpod provider for Web Connectors (M11 Extension).
///
/// Wraps the web_connectors adapter's load/save/stream into a Riverpod
/// StateNotifier so the shell and the connectors panel read one list. It also
/// owns the live MCP connections: an enabled `mcp` connector is connected
/// through [mcpClient]; disabling or removing it disconnects.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/adapters/mcp_adapter.dart';
import '../services/adapters/web_connectors.dart';

final webConnectorsProvider =
    StateNotifierProvider<WebConnectorsController, List<WebConnector>>((ref) {
  return WebConnectorsController();
});

class WebConnectorsController extends StateNotifier<List<WebConnector>> {
  WebConnectorsController() : super(defaultWebConnectors) {
    _init();
    _sub = connectorsUpdated.listen((connectors) {
      if (mounted) state = connectors;
    });
  }

  StreamSubscription<List<WebConnector>>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final connectors = await loadWebConnectors();
      if (!mounted) return;
      state = connectors;
    } catch (_) {
      // Keep the built-in defaults when persistence is unavailable.
    }
    // Reconnect every MCP connector that was left enabled last session.
    for (final c in List.of(state)) {
      if (c.type == ConnectorType.mcp && c.enabled) await _syncMcp(c);
    }
  }

  Future<void> _commit(List<WebConnector> next) async {
    state = next;
    await saveWebConnectors(next);
  }

  /// Replace one connector in the list (and persist it).
  Future<void> _update(String id, WebConnector Function(WebConnector) change) =>
      _commit([for (final c in state) c.id == id ? change(c) : c]);

  /// Bring the live MCP connection in line with the connector: connected when
  /// enabled, closed when not. A failure is recorded on the connector so the
  /// panel shows why, rather than the toggle silently doing nothing.
  Future<void> _syncMcp(WebConnector c) async {
    if (c.type != ConnectorType.mcp) return;
    // Always drop a stale connection first; `connect` would orphan it.
    await mcpClient.disconnect(c.id);
    if (!c.enabled) return;

    final key = c.apiKey;
    try {
      await mcpClient.connect(McpServer(
        id: c.id,
        name: c.name,
        url: c.url,
        headers: key != null && key.isNotEmpty
            ? {'Authorization': 'Bearer $key'}
            : const {},
      ));
      if (!mounted) return;
      await _update(
        c.id,
        (x) => x.copyWith(state: ConnectorState.connected, clearError: true),
      );
    } catch (e) {
      if (!mounted) return;
      await _update(
        c.id,
        (x) => x.copyWith(
          state: ConnectorState.error,
          error: '$e'.replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  Future<void> toggle(String id) async {
    await _update(id, (c) => c.copyWith(enabled: !c.enabled));
    final c = state.firstWhere((x) => x.id == id);
    await _syncMcp(c);
  }

  /// Probe one connector and record the outcome on it.
  Future<ConnectorTestResult> test(WebConnector connector) async {
    final res = connector.type == ConnectorType.mcp
        ? await _testMcp(connector)
        : await testWebConnector(connector);
    await _update(
      connector.id,
      (c) => c.copyWith(
        state: res.ok ? ConnectorState.connected : ConnectorState.error,
        latencyMs: res.latencyMs,
        lastTested: DateTime.now().millisecondsSinceEpoch,
        error: res.ok ? null : res.message,
        clearError: res.ok,
      ),
    );
    return res;
  }

  /// Test an MCP connector by really connecting and listing its tools — the
  /// same path chat uses — instead of the backend proxy probe, which can
  /// fail while the direct connection works.
  Future<ConnectorTestResult> _testMcp(WebConnector connector) async {
    final sw = Stopwatch()..start();
    final key = connector.apiKey;
    final probeId = connector.id;
    try {
      await mcpClient.disconnect(probeId);
      await mcpClient.connect(McpServer(
        id: probeId,
        name: connector.name,
        url: connector.url,
        headers: key != null && key.isNotEmpty
            ? {'Authorization': 'Bearer $key'}
            : const {},
      ));
      final tools = await mcpClient.listTools(probeId);
      // A disabled connector must not be left connected by a test.
      if (!connector.enabled) await mcpClient.disconnect(probeId);
      return ConnectorTestResult(
        ok: true,
        latencyMs: sw.elapsedMilliseconds,
        message: 'Connected — ${tools.length} tool${tools.length == 1 ? '' : 's'} available',
        toolsCount: tools.length,
      );
    } catch (e) {
      await mcpClient.disconnect(probeId);
      return ConnectorTestResult(
        ok: false,
        latencyMs: sw.elapsedMilliseconds,
        message: '$e'.replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> remove(String id) async {
    await mcpClient.disconnect(id);
    await _commit([for (final c in state) if (c.id != id) c]);
  }

  Future<void> add(WebConnector connector) async {
    await _commit([...state, connector]);
    if (connector.type == ConnectorType.mcp) {
      await _syncMcp(connector);
    } else {
      await test(connector);
    }
  }
}

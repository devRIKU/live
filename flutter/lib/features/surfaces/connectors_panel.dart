/// Web Connectors manager (M11 extension).
///
/// View, test, enable, add and remove web connectors: live web search, the
/// safe page reader, remote MCP servers and custom REST APIs.
/// Port of `src/surfaces/ConnectorsPanel.tsx`.
library;

import 'package:fluent_ui/fluent_ui.dart' as f;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/adapters/web_connectors.dart';
import '../../core/state/connectors_provider.dart';
import '../../core/theme/lively_tokens.dart';
import 'overlay_surface.dart';

class ConnectorsOverlay extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  final void Function(String message)? onToast;

  const ConnectorsOverlay({super.key, required this.onClose, this.onToast});

  @override
  ConsumerState<ConnectorsOverlay> createState() => _ConnectorsOverlayState();
}

class _ConnectorsOverlayState extends ConsumerState<ConnectorsOverlay> {
  bool _adding = false;
  String? _testingId;
  final Map<String, ConnectorTestResult> _results = {};

  final _name = TextEditingController();
  final _url = TextEditingController();
  final _key = TextEditingController();
  final _desc = TextEditingController();
  ConnectorType _type = ConnectorType.mcp;
  String? _formError;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _key.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _toast(String m) => widget.onToast?.call(m);

  Future<void> _test(WebConnector c) async {
    setState(() => _testingId = c.id);
    try {
      final res = await ref.read(webConnectorsProvider.notifier).test(c);
      if (!mounted) return;
      setState(() => _results[c.id] = res);
      _toast(res.ok ? '${c.name}: ${res.message}' : 'Test failed: ${res.message}');
    } finally {
      if (mounted) setState(() => _testingId = null);
    }
  }

  Future<void> _testAll() async {
    for (final c in ref.read(webConnectorsProvider).where((c) => c.enabled)) {
      await _test(c);
    }
  }

  void _submit() {
    final name = _name.text.trim();
    final url = _url.text.trim();
    if (name.isEmpty) {
      setState(() => _formError = 'Please enter a connector name.');
      return;
    }
    if (url.isEmpty) {
      setState(() => _formError = 'Please enter an endpoint URL.');
      return;
    }
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final connector = WebConnector(
      id: 'conn_$stamp',
      name: name,
      type: _type,
      url: url,
      apiKey: _key.text.trim().isEmpty ? null : _key.text.trim(),
      description:
          _desc.text.trim().isEmpty ? 'Custom ${_type.name} web connector.' : _desc.text.trim(),
      enabled: true,
      state: ConnectorState.ready,
    );
    ref.read(webConnectorsProvider.notifier).add(connector);
    _toast('Added connector "$name".');
    _name.clear();
    _url.clear();
    _key.clear();
    _desc.clear();
    setState(() {
      _type = ConnectorType.mcp;
      _formError = null;
      _adding = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = f.FluentTheme.of(context).brightness;
    final connectors = ref.watch(webConnectorsProvider);
    final active = connectors.where((c) => c.enabled).length;

    return OverlaySurface(
      title: 'Web Connectors',
      onClose: widget.onClose,
      maxHeight: 540,
      badge: OverlayBadge(
        label: '$active active / ${connectors.length} total',
        color: active > 0 ? Lively.appleGreen : Lively.textSecondary(b),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connect Lively to real-time search, URL readers, remote MCP servers, and web APIs.',
            style: TextStyle(color: Lively.textSecondary(b), fontSize: Lively.tFootnote),
          ),
          const SizedBox(height: Lively.s3),
          Row(
            children: [
              f.Button(onPressed: _testAll, child: const Text('Test all')),
              const SizedBox(width: Lively.s2),
              f.FilledButton(
                onPressed: () => setState(() => _adding = !_adding),
                child: Text(_adding ? 'Cancel' : 'Add connector'),
              ),
            ],
          ),
          const SizedBox(height: Lively.s3),
          if (_adding) _form(b),
          for (final c in connectors) _card(b, c),
        ],
      ),
    );
  }

  Widget _form(Brightness b) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add Web Connector',
              style: TextStyle(
                  color: Lively.textPrimary(b),
                  fontSize: Lively.tBody,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: Lively.s2),
          if (_formError != null)
            SurfaceCallout(
              tone: 'bad',
              icon: f.FluentIcons.warning,
              children: [
                Text(_formError!,
                    style: TextStyle(color: Lively.textPrimary(b), fontSize: Lively.tFootnote)),
              ],
            ),
          _label(b, 'Connector Name *'),
          f.TextBox(controller: _name, placeholder: 'e.g. GitHub Tools or Docs MCP'),
          const SizedBox(height: Lively.s2),
          _label(b, 'Connector Type'),
          f.ComboBox<ConnectorType>(
            value: _type,
            isExpanded: true,
            items: const [
              f.ComboBoxItem(
                  value: ConnectorType.mcp,
                  child: Text('Remote MCP Server (StreamableHTTP / SSE)')),
              f.ComboBoxItem(value: ConnectorType.search, child: Text('Web Search API')),
              f.ComboBoxItem(
                  value: ConnectorType.fetch, child: Text('Web Page Reader / Scraper')),
              f.ComboBoxItem(value: ConnectorType.rest, child: Text('Custom REST API')),
            ],
            onChanged: (v) => setState(() => _type = v ?? ConnectorType.mcp),
          ),
          const SizedBox(height: Lively.s2),
          _label(b, 'Endpoint URL *'),
          f.TextBox(
            controller: _url,
            placeholder: _type == ConnectorType.mcp
                ? 'http://localhost:8000/sse'
                : 'https://api.example.com/v1',
          ),
          const SizedBox(height: Lively.s2),
          _label(b, 'API Key / Auth Header (Optional)'),
          f.PasswordBox(controller: _key, placeholder: 'Bearer token or API key'),
          const SizedBox(height: Lively.s2),
          _label(b, 'Description'),
          f.TextBox(
              controller: _desc,
              placeholder: 'Brief description of what this connector provides'),
          const SizedBox(height: Lively.s3),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              f.Button(onPressed: () => setState(() => _adding = false), child: const Text('Cancel')),
              const SizedBox(width: Lively.s2),
              f.FilledButton(onPressed: _submit, child: const Text('Save Connector')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _label(Brightness b, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: TextStyle(
                color: Lively.textSecondary(b),
                fontSize: Lively.tMicro,
                fontWeight: FontWeight.w600)),
      );

  Widget _card(Brightness b, WebConnector c) {
    final testing = _testingId == c.id;
    final result = _results[c.id];
    final tone = switch (c.state) {
      ConnectorState.connected => Lively.appleGreen,
      ConnectorState.error => Lively.appleRed,
      _ => Lively.orange500,
    };
    final stateLabel = switch (c.state) {
      ConnectorState.connected => 'connected',
      ConnectorState.ready => 'ready',
      ConnectorState.needsKey => 'needs key',
      ConnectorState.error => 'error',
      ConnectorState.testing => 'testing',
    };
    final icon = switch (c.type) {
      ConnectorType.mcp => f.FluentIcons.plug_connected,
      ConnectorType.rest => f.FluentIcons.command_prompt,
      _ => f.FluentIcons.globe,
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: Lively.s3),
      padding: const EdgeInsets.all(Lively.s3),
      decoration: BoxDecoration(
        color: Lively.fill(b, 1),
        borderRadius: BorderRadius.circular(Lively.rLg),
        border: Border(
          left: BorderSide(
              color: c.enabled ? Lively.accent(b) : Colors.transparent, width: 3),
          top: BorderSide(color: Lively.separator(b), width: Lively.bHairline),
          right: BorderSide(color: Lively.separator(b), width: Lively.bHairline),
          bottom: BorderSide(color: Lively.separator(b), width: Lively.bHairline),
        ),
      ),
      child: Opacity(
        opacity: c.enabled ? 1 : 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: Lively.accent(b)),
                const SizedBox(width: Lively.s2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: Lively.s2,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(c.name,
                              style: TextStyle(
                                  color: Lively.textPrimary(b),
                                  fontSize: Lively.tFootnote,
                                  fontWeight: FontWeight.w600)),
                          OverlayBadge(
                              label: c.type.name.toUpperCase(),
                              color: Lively.textSecondary(b)),
                          OverlayBadge(label: testing ? 'Testing…' : stateLabel, color: tone),
                          if (c.latencyMs != null)
                            Text('${c.latencyMs}ms',
                                style: TextStyle(
                                    color: Lively.textTertiary(b), fontSize: Lively.tMicro)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(c.url,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Lively.textTertiary(b),
                              fontSize: Lively.tMicro,
                              fontFamily: 'Consolas')),
                    ],
                  ),
                ),
                f.Button(
                  onPressed: testing ? null : () => _test(c),
                  child: Text(testing ? 'Testing…' : 'Test'),
                ),
                const SizedBox(width: Lively.s2),
                f.ToggleSwitch(
                  checked: c.enabled,
                  onChanged: (_) {
                    ref.read(webConnectorsProvider.notifier).toggle(c.id);
                    _toast('${c.name} ${c.enabled ? 'disabled' : 'enabled'}.');
                  },
                ),
                if (c.isBuiltin != true) ...[
                  const SizedBox(width: Lively.s2),
                  IconButton(
                    tooltip: 'Delete ${c.name}',
                    icon: Icon(f.FluentIcons.chrome_close,
                        size: 14, color: Lively.textSecondary(b)),
                    onPressed: () {
                      ref.read(webConnectorsProvider.notifier).remove(c.id);
                      _toast('Connector removed.');
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: Lively.s2),
            Text(c.description,
                style: TextStyle(color: Lively.textSecondary(b), fontSize: Lively.tFootnote)),
            if (c.tools.isNotEmpty) ...[
              const SizedBox(height: Lively.s2),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in c.tools)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Lively.fill(b, 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(t.name,
                          style: TextStyle(
                              color: Lively.textPrimary(b),
                              fontSize: 11,
                              fontFamily: 'Consolas')),
                    ),
                ],
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: Lively.s2),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (result.ok ? Lively.appleGreen : Lively.appleRed)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(Lively.rMd),
                ),
                child: Text(
                  '${result.message} (${result.latencyMs}ms)',
                  style: TextStyle(
                    color: result.ok ? Lively.appleGreen : Lively.appleRed,
                    fontSize: Lively.tMicro,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

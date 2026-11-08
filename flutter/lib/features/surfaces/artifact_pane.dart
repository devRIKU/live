/// Artifact pane (M3) — the artifact opens beside the conversation.
///
/// The React app renders HTML/SVG artifacts in a sandboxed iframe
/// (`sandbox="allow-scripts"`, no same-origin, no network). On Windows
/// we use WebView2 (via `webview_windows`) to render HTML/SVG artifacts
/// with the same security posture: no network access, no same-origin,
/// scripts allowed only for self-contained demos. Markdown renders via
/// the native markdown viewer. React artifacts show source with a note.
/// Port of `src/surfaces/ArtifactPane.tsx` (preview + code tabs, copy, download, close).
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:fluent_ui/fluent_ui.dart' as f;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:webview_windows/webview_windows.dart';

import '../../core/services/canvas/artifact_detector.dart';
import '../../core/theme/lively_tokens.dart';
import '../../shared/markdown_view.dart';

class ArtifactPane extends StatelessWidget {
  final Artifact artifact;
  final VoidCallback onClose;
  final void Function(String message)? onToast;

  const ArtifactPane({
    super.key,
    required this.artifact,
    required this.onClose,
    this.onToast,
  });

  @override
  Widget build(BuildContext context) {
    final b = f.FluentTheme.of(context).brightness;

    return Container(
      decoration: BoxDecoration(
        color: Lively.surfaceRaised(b),
        border: Border(
          left: BorderSide(color: Lively.separator(b), width: Lively.bHairline),
        ),
      ),
      child: _PaneBody(artifact: artifact, onClose: onClose, onToast: onToast),
    );
  }
}

class _PaneBody extends StatefulWidget {
  final Artifact artifact;
  final VoidCallback onClose;
  final void Function(String message)? onToast;

  const _PaneBody({
    required this.artifact,
    required this.onClose,
    this.onToast,
  });

  @override
  State<_PaneBody> createState() => _PaneBodyState();
}

enum _PaneTab { preview, code }

class _PaneBodyState extends State<_PaneBody> {
  _PaneTab tab = _PaneTab.preview;

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.artifact.code));
      widget.onToast?.call('Artifact copied');
    } catch (_) {}
  }

  Future<void> _download() async {
    final safeTitle =
        widget.artifact.title.replaceAll(RegExp(r'[^\w.-]+'), '-');
    final suggested =
        '${safeTitle.isEmpty ? 'artifact' : safeTitle}.${widget.artifact.type.name}';
    final path = await fs.getSaveLocation(suggestedName: suggested);
    if (path == null) return;
    try {
      await File(path.path).writeAsString(widget.artifact.code, flush: true);
      widget.onToast?.call('Artifact saved');
    } catch (e) {
      widget.onToast?.call('Could not save the artifact');
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = f.FluentTheme.of(context).brightness;

    return Column(
      children: [
        // Head
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Lively.s3, Lively.s2, Lively.s2, Lively.s2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.artifact.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Lively.textPrimary(b),
                        fontSize: Lively.tFootnote,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: Lively.s2),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Lively.accentMuted(b),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      widget.artifact.type.name,
                      style: TextStyle(
                        color: Lively.accentText(b),
                        fontSize: Lively.tMicro,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Lively.s2),
              Row(
                children: [
                  _Tab(
                    icon: f.FluentIcons.view,
                    label: 'Preview',
                    active: tab == _PaneTab.preview,
                    onTap: () => setState(() => tab = _PaneTab.preview),
                  ),
                  const SizedBox(width: Lively.s2),
                  _Tab(
                    icon: f.FluentIcons.code,
                    label: 'Code',
                    active: tab == _PaneTab.code,
                    onTap: () => setState(() => tab = _PaneTab.code),
                  ),
                  const Spacer(),
                  _Action(
                    icon: f.FluentIcons.copy,
                    tooltip: 'Copy',
                    onTap: _copy,
                  ),
                  const SizedBox(width: Lively.s2),
                  _Action(
                    icon: f.FluentIcons.download,
                    tooltip: 'Download',
                    onTap: _download,
                  ),
                  const SizedBox(width: Lively.s2),
                  _Action(
                    icon: f.FluentIcons.chrome_close,
                    tooltip: 'Close artifact',
                    onTap: widget.onClose,
                  ),
                ],
              ),
            ],
          ),
        ),
        Divider(height: 1, thickness: Lively.bHairline, color: Lively.separator(b)),
        // Body
        Expanded(
          child: tab == _PaneTab.preview
              ? _preview(b)
              : _CodeView(code: widget.artifact.code, b: b),
        ),
        Divider(height: 1, thickness: Lively.bHairline, color: Lively.separator(b)),
        // Foot — the security note, restated for WebView2 renderer.
        Padding(
          padding: const EdgeInsets.all(Lively.s2),
          child: Row(
            children: [
              Icon(f.FluentIcons.shield, size: 14, color: Lively.textTertiary(b)),
              const SizedBox(width: Lively.s2),
              Expanded(
                child: Text(
                  widget.artifact.type == ArtifactType.markdown
                      ? 'Rendered as inert text · nothing is executed · no network'
                      : widget.artifact.type == ArtifactType.html ||
                              widget.artifact.type == ArtifactType.svg
                          ? 'WebView2 sandbox: scripts allowed, no network, no same-origin'
                          : 'No code execution · no network access — source is display-only',
                  style: TextStyle(
                    color: Lively.textTertiary(b),
                    fontSize: Lively.tMicro,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _preview(Brightness b) {
    final type = widget.artifact.type;
    final code = widget.artifact.code;

    if (type == ArtifactType.markdown) {
      return MarkdownView(content: code);
    }

    // HTML and SVG: render in WebView2 with strict CSP
    if (type == ArtifactType.html || type == ArtifactType.svg) {
      return _WebViewPreview(
        code: code,
        type: type,
        brightness: b,
      );
    }

    // React and others: show source with note
    return _CodeView(code: code, b: b);
  }
}

/// A tab switcher pill used for Preview / Code.
class _Tab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Tab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final b = f.FluentTheme.of(context).brightness;
    return InkWell(
      borderRadius: BorderRadius.circular(Lively.rMd),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? Lively.fill(b, 2) : Colors.transparent,
          borderRadius: BorderRadius.circular(Lively.rMd),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: Lively.textSecondary(b)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color:
                    active ? Lively.textPrimary(b) : Lively.textSecondary(b),
                fontSize: Lively.tFootnote,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small square icon action.
class _Action extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _Action({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final b = f.FluentTheme.of(context).brightness;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(Lively.rMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 15, color: Lively.textSecondary(b)),
        ),
      ),
    );
  }
}

/// WebView2-based preview for HTML/SVG artifacts.
/// Uses a data: URI with strict CSP to prevent network access.
class _WebViewPreview extends StatefulWidget {
  final String code;
  final ArtifactType type;
  final Brightness brightness;

  const _WebViewPreview({
    required this.code,
    required this.type,
    required this.brightness,
  });

  @override
  State<_WebViewPreview> createState() => _WebViewPreviewState();
}

class _WebViewPreviewState extends State<_WebViewPreview> {
  final WebviewController _controller = WebviewController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      // Throws when the WebView2 runtime is not installed.
      await _controller.initialize();
      await _controller.setBackgroundColor(Colors.transparent);
      // A generated page may not open windows of its own.
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await _controller.loadStringContent(_buildHtml(widget.code, widget.type));
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'The preview needs the Microsoft WebView2 runtime. '
            'Use the Code tab to read the source. ($e)');
      }
    }
  }

  @override
  void didUpdateWidget(_WebViewPreview old) {
    super.didUpdateWidget(old);
    if (_controller.value.isInitialized &&
        (old.code != widget.code || old.type != widget.type)) {
      _controller.loadStringContent(_buildHtml(widget.code, widget.type));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// No network, no embedding, scripts only inline. It is always injected,
  /// even when the artifact brings its own policy: several policies combine
  /// as an intersection, so the stricter one wins and a permissive
  /// model-written policy can never loosen this sandbox.
  static const String _csp = "default-src 'none'; script-src 'unsafe-inline'; "
      "style-src 'unsafe-inline'; img-src data: blob:; font-src data:; "
      "connect-src 'none'; frame-src 'none'; form-action 'none';";
  static const String _cspMeta =
      '<meta http-equiv="Content-Security-Policy" content="$_csp">';

  static String _buildHtml(String code, ArtifactType type) {
    if (type == ArtifactType.svg) {
      return '<!DOCTYPE html><html><head><meta charset="utf-8">$_cspMeta</head>'
          '<body style="margin:0;display:flex;align-items:center;'
          'justify-content:center;height:100vh">$code</body></html>';
    }

    final trimmed = code.trim();
    final head = RegExp(r'<head(\s[^>]*)?>', caseSensitive: false);
    final htmlTag = RegExp(r'<html(\s[^>]*)?>', caseSensitive: false);

    if (head.hasMatch(trimmed)) {
      return trimmed.replaceFirstMapped(head, (m) => '${m[0]}$_cspMeta');
    }
    if (htmlTag.hasMatch(trimmed)) {
      return trimmed.replaceFirstMapped(
          htmlTag, (m) => '${m[0]}<head>$_cspMeta</head>');
    }
    return '<!DOCTYPE html><html><head><meta charset="utf-8">$_cspMeta</head>'
        '<body>$code</body></html>';
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      final b = widget.brightness;
      return Padding(
        padding: const EdgeInsets.all(Lively.s3),
        child: Text(_error!,
            style: TextStyle(color: Lively.textSecondary(b), fontSize: Lively.tFootnote)),
      );
    }
    if (!_controller.value.isInitialized) {
      return const Center(child: SizedBox(width: 20, height: 20, child: f.ProgressRing()));
    }
    return Webview(_controller);
  }
}

/// Read-only monospace source with soft wrapping.
class _CodeView extends StatelessWidget {
  final String code;
  final Brightness b;
  const _CodeView({required this.code, required this.b});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Lively.s3),
      primary: true,
      child: SelectableText(
        code,
        style: TextStyle(
          color: Lively.textPrimary(b),
          fontSize: Lively.tFootnote,
          fontFamily: 'Consolas, "Cascadia Mono", monospace',
          height: 1.45,
        ),
      ),
    );
  }
}

/// A message turn — port of `src/shell/MessageTurn.tsx`.
///
/// The hierarchy is the shell's: the assistant's reply is the page — plain
/// text, no bubble wrapper — and the user's message is a right-aligned
/// bubble. A `[Tool result: <name>]` user turn is rendered as a quiet card
/// on the left instead of a user bubble.
library;

import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart' as f;
import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/theme/lively_tokens.dart';
import '../genui/actions.dart' show OpenUIActionEvent;
import '../genui/open_ui_message.dart';

Brightness _bOf(BuildContext context) => f.FluentTheme.of(context).brightness;

String _timeOf(int timestamp) {
  final t = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class MessageTurn extends StatelessWidget {
  final Message message;

  /// Rendered content for the assistant turn while it streams.
  final String? streamingContent;
  final bool isStreaming;
  final void Function(String text)? onCopy;
  final void Function(OpenUIActionEvent event)? onAction;

  const MessageTurn({
    super.key,
    required this.message,
    this.streamingContent,
    this.isStreaming = false,
    this.onCopy,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final b = _bOf(context);

    if (message.role == 'user') {
      final toolResult = _toolResultPattern.firstMatch(message.content);
      if (toolResult != null) {
        return _TurnColumn(
          brightness: b,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ToolResultCard(
              brightness: b,
              name: toolResult.group(1) ?? '',
              body: toolResult.group(2) ?? '',
            ),
            _MetaLine(time: _timeOf(message.createdAt), brightness: b),
          ],
        );
      }

      final attachments = message.attachments ?? const [];
      return _TurnColumn(
        brightness: b,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (attachments.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: Lively.s2,
                runSpacing: Lively.s2,
                children: [
                  for (final attachment in attachments)
                    if (attachment.kind == 'image' && attachment.dataUrl != null)
                      _AttachmentThumb(dataUrl: attachment.dataUrl!)
                    else
                      _AttachmentFileChip(
                        brightness: b,
                        name: attachment.name,
                      ),
                ],
              ),
            ),
          // Empty user turns still show the meta line (pure attachment turn).
          if (message.content.trim().isNotEmpty)
            _UserBubble(brightness: b, text: message.content),
          _MetaLine(time: _timeOf(message.createdAt), brightness: b),
        ],
      );
    }

    // Assistant turn.
    final info = message.providerInfo;
    final providerState =
        (info?.fallbackUsed ?? false) ? 'fallback' : (info?.providerId != null ? 'available' : '');

    return _TurnColumn(
      brightness: b,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isStreaming)
          _AssistantBody(
            brightness: b,
            content: streamingContent ?? '',
            streaming: true,
            onAction: onAction,
          )
        else
          _AssistantBody(
            brightness: b,
            content: streamingContent ?? message.content,
            streaming: false,
            onAction: onAction,
          ),
        if (info != null && !isStreaming)
          Row(children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: providerState == 'fallback'
                    ? Lively.appleOrange
                    : (providerState == 'available'
                        ? Lively.appleGreen
                        : Lively.appleGray),
              ),
            ),
            const SizedBox(width: Lively.s1),
            Text(
              '${info.providerId} / ${info.model}',
              style: TextStyle(
                color: Lively.textTertiary(b),
                fontSize: Lively.tMicro,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (info.fallbackUsed) ...[
              const SizedBox(width: Lively.s1),
              Text(
                '(fallback)',
                style: TextStyle(color: Lively.appleOrange, fontSize: Lively.tMicro),
              ),
            ],
          ]),
        if (!isStreaming && message.content.isNotEmpty)
          Row(mainAxisSize: MainAxisSize.min, children: [
            _ActionGlyph(
              icon: f.FluentIcons.copy,
              brightness: b,
              tooltip: 'Copy',
              onTap: () => onCopy?.call(message.content),
            ),
            _ActionGlyph(
              icon: f.FluentIcons.like,
              brightness: b,
              tooltip: 'Good response',
            ),
            _ActionGlyph(
              icon: f.FluentIcons.dislike,
              brightness: b,
              tooltip: 'Bad response',
            ),
          ]),
      ],
    );
  }

  /// `\[Tool result: <name>]\n?<body>\$` — same shape as the TS regex.
  /// Dart is not multiline-by-default, so `^`/`\$` anchors behave like the
  /// JS `m`-less semantics here (single match at the very start).
  static final RegExp _toolResultPattern = RegExp(r'^\[Tool result: ([^\]]+)\]\n?([\s\S]*)$');
}

// ── Building blocks ──────────────────────────────────────────────────────────

class _TurnColumn extends StatelessWidget {
  final Brightness brightness;
  final CrossAxisAlignment crossAxisAlignment;
  final List<Widget> children;

  const _TurnColumn({
    required this.brightness,
    required this.crossAxisAlignment,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Lively.threadGap),
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        children: children,
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final String time;
  final Brightness brightness;
  const _MetaLine({required this.time, required this.brightness});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Lively.s1),
      child: Text(
        time,
        style: TextStyle(
          color: Lively.textTertiary(brightness),
          fontSize: Lively.tMicro,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// User turn bubble.
class _UserBubble extends StatelessWidget {
  final Brightness brightness;
  final String text;
  const _UserBubble({required this.brightness, required this.text});

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    return Container(
      constraints: const BoxConstraints(maxWidth: Lively.columnWidth * 0.72),
      padding: const EdgeInsets.symmetric(horizontal: Lively.s3, vertical: Lively.s2),
      decoration: BoxDecoration(
        color: Lively.fill(b, 1),
        borderRadius: BorderRadius.circular(Lively.bubbleRadius),
        border: Border.all(color: Lively.separator(b), width: Lively.bHairline),
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          color: Lively.textPrimary(b),
          fontSize: Lively.tBody,
          height: Lively.lhBody,
        ),
      ),
    );
  }
}

/// Assistant turn: markdown, no bubble chrome.
class _AssistantBody extends StatelessWidget {
  final Brightness brightness;
  final String content;
  final bool streaming;
  final void Function(OpenUIActionEvent event)? onAction;
  const _AssistantBody({
    required this.brightness,
    required this.content,
    required this.streaming,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    if (streaming) {
      // A bare caret while nothing has arrived, then caret-after-text.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (content.isNotEmpty)
            Expanded(
              child: OpenUIMessage(
                content: content,
                isStreaming: true,
                onAction: onAction,
              ),
            ),
          const _Caret(),
        ],
      );
    }
    if (content.isEmpty) return const SizedBox.shrink();
    return OpenUIMessage(content: content, onAction: onAction);
  }
}

class _Caret extends StatelessWidget {
  const _Caret();

  @override
  Widget build(BuildContext context) {
    final b = _bOf(context);
    return Container(
      width: 8,
      height: 16,
      margin: const EdgeInsets.only(left: 2, top: 2),
      decoration: BoxDecoration(
        color: LovyHelper.caret(b),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Token helpers kept off the Lively class to avoid token-file churn.
class LovyHelper {
  static Color caret(Brightness b) =>
      b == Brightness.dark ? const Color(0xFFEBEBF5) : Lively.neutral900;
}

/// `[Tool result: …]` card on the left.
class _ToolResultCard extends StatelessWidget {
  final Brightness brightness;
  final String name;
  final String body;
  const _ToolResultCard({
    required this.brightness,
    required this.name,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    return Container(
      constraints: const BoxConstraints(maxWidth: Lively.columnWidth * 0.82),
      decoration: BoxDecoration(
        color: Lively.surfaceSunken(b),
        borderRadius: BorderRadius.circular(Lively.rLg),
        border: Border.all(color: Lively.separator(b), width: Lively.bHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Lively.s3, Lively.s2, Lively.s3, Lively.s1),
            child: Row(children: [
              Text(
                'Tool result',
                style: TextStyle(
                  color: Lively.textTertiary(b),
                  fontSize: Lively.tMicro,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  textBaseline: TextBaseline.alphabetic,
                ),
              ),
              const SizedBox(width: Lively.s2),
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Lively.textSecondary(b),
                    fontSize: Lively.tMicro,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Lively.s3, 0, Lively.s3, Lively.s2),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                body,
                style: TextStyle(
                  color: Lively.textSecondary(b),
                  fontSize: Lively.tFootnote,
                  fontFamily: 'Consolas, "Cascadia Mono", monospace',
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Image attachment thumbnail.
class _AttachmentThumb extends StatelessWidget {
  final String dataUrl;
  const _AttachmentThumb({required this.dataUrl});

  @override
  Widget build(BuildContext context) {
    Widget child;
    Uri? uri;
    // data: URLs are decoded inline; http caches are never fetched here.
    final header = RegExp(r'^data:image/[a-zA-Z+]+;base64,');
    final match = header.firstMatch(dataUrl);
    if (match != null) {
      try {
        final bytes = base64Decode(dataUrl.substring(match.end));
        child = Image.memory(bytes, fit: BoxFit.cover);
      } catch (_) {
        child = const SizedBox(width: 48, height: 48);
      }
    } else {
      uri = Uri.tryParse(dataUrl);
      child = uri != null
          ? Image.network(dataUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink())
          : const SizedBox.shrink();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(Lively.rLg),
      child: SizedBox(
        width: 44,
        height: 44,
        child: FittedBox(fit: BoxFit.cover, child: child),
      ),
    );
  }
}

/// Text-attachment chip with the extension badge.
class _AttachmentFileChip extends StatelessWidget {
  final Brightness brightness;
  final String name;
  const _AttachmentFileChip({required this.brightness, required this.name});

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    final ext = (name.split('.').length > 1 ? name.split('.').last : 'file')
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final badge = ext.length > 4 ? ext.substring(0, 4) : ext.padRight(1, '·');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Lively.s2, vertical: Lively.s1),
      decoration: BoxDecoration(
        color: Lively.surfaceRaised(b),
        borderRadius: BorderRadius.circular(Lively.rMd),
        border: Border.all(color: Lively.separator(b), width: Lively.bHairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: Lively.accentMuted(b),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            badge,
            style: TextStyle(
              color: Lively.accentText(b),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
        const SizedBox(width: Lively.s1),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Lively.textSecondary(b), fontSize: Lively.tMicro),
          ),
        ),
      ]),
    );
  }
}

/// Copy / thumbs action glyph row for assistant turns.
class _ActionGlyph extends StatelessWidget {
  final IconData icon;
  final Brightness brightness;
  final String tooltip;
  final VoidCallback? onTap;

  const _ActionGlyph({
    required this.icon,
    required this.brightness,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Lively.s1),
          child: Icon(
            icon,
            size: 13,
            color: onTap == null
                ? Lively.textTertiary(b)
                : Lively.textSecondary(b),
          ),
        ),
      ),
    );
  }
}

/// Markdown — the assistant's body text. Port of `src/lib/Markdown.tsx`.
///
/// The shell styles a rich assistant turn, so the markdown renderer only has
/// to produce ordinary elements and let the theme do the typography.
///
/// Security: `flutter_markdown` never renders raw HTML tags as markup, and
/// tapping links goes through [launchExternal] — a `javascript:`/`data:`
/// href therefore can never execute script in the app. Links keep
/// `target="_blank"` semantics (opened in the OS shell).
library;

import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

/// Allow inline images: the prototype's no-key path returns a `data:image`
/// URI. Other `data:` URLs are dropped.
bool safeUrlTransform(Uri uri, String baseUrl) =>
    RegExp(r'^data:image/(?:png|jpe?g|gif|webp|svg\+xml)[;,]', caseSensitive: false)
        .hasMatch(uri.toString());

/// Open a link with the OS browser shell (analogous to target="_blank").
void launchExternal(String href) {
  final uri = Uri.tryParse(href);
  if (uri == null) return;
  final scheme = uri.scheme.toLowerCase();
  // Only http(s)/mailto pass; everything else is refused.
  if (scheme != 'http' && scheme != 'https' && scheme != 'mailto') return;
  launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// An inline `data:image/...` picture. The bytes are decoded in memory —
/// `Image.network` cannot load a data URI. SVG is not decodable by Flutter's
/// image codecs, so it (and any undecodable payload) shows the alt text
/// instead of silently vanishing.
class _DataImage extends StatelessWidget {
  final Uri uri;
  final String? alt;
  const _DataImage({required this.uri, this.alt});

  @override
  Widget build(BuildContext context) {
    final label = (alt == null || alt!.isEmpty) ? 'image' : alt!;
    final fallback = Text('[$label — preview not available]',
        style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13));

    final isSvg = uri.toString().toLowerCase().startsWith('data:image/svg');
    final data = uri.data;
    if (isSvg || data == null) return fallback;

    final Uint8List bytes;
    try {
      bytes = data.contentAsBytes();
    } catch (_) {
      return fallback;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            semanticLabel: label,
            errorBuilder: (_, __, ___) => fallback,
          ),
        ),
      ),
    );
  }
}

class MarkdownView extends StatelessWidget {
  final String content;
  const MarkdownView({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MarkdownBody(
      data: content,
      softLineBreak: true,
      onTapLink: (text, href, title) {
        if (href != null) launchExternal(href);
      },
      imageBuilder: (uri, title, alt) {
        // Inline data: images only; http images are refused (matches the
        // sanitize protocol allowlist for src).
        if (safeUrlTransform(uri, '')) {
          return _DataImage(uri: uri, alt: alt);
        }
        return const SizedBox.shrink();
      },
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        blockquoteDecoration: BoxDecoration(
          color: theme.dividerColor.withValues(alpha: 0.08),
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.secondary.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
        ),
        codeblockDecoration: BoxDecoration(
          color: theme.dividerColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
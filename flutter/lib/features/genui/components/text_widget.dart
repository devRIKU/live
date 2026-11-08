import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../core/theme/lively_tokens.dart';
import '../nodes.dart';
import '../schema.dart';

/// Text — a block of prose inside a generated interface.
class TextWidget extends StatelessWidget {
  const TextWidget({super.key, required this.node});

  final TextNode node;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final (fontSize, height) = switch (node.size) {
      // ms-text-small
      TextSize.small => (Lively.tFootnote, Lively.lhFootnote),
      // ms-text-large
      TextSize.large => (Lively.tHeadline, Lively.lhHeadline),
      TextSize.normal => (Lively.tBody, Lively.lhBody),
    };

    // Trim to the schema bound: an oversized block is never rendered whole.
    final text = node.text.length > Limits.maxTextLength
        ? node.text.substring(0, Limits.maxTextLength)
        : node.text;

    final base = TextStyle(
      fontSize: fontSize,
      height: height,
      color: Lively.textPrimary(brightness),
    );

    return MarkdownBody(
      data: text,
      styleSheet: MarkdownStyleSheet(
        p: base,
        strong: base.copyWith(fontWeight: FontWeight.w600),
        em: base.copyWith(fontStyle: FontStyle.italic),
        code: base.copyWith(
          fontFamily: 'Consolas',
          fontSize: fontSize - 1,
          color: Lively.textPrimary(brightness),
          background: Paint()..color = Lively.fill(brightness, 1),
        ),
        codeblockDecoration: BoxDecoration(
          color: Lively.fill(brightness, 1),
          borderRadius: BorderRadius.circular(Lively.rSm),
        ),
        blockquote: base.copyWith(color: Lively.textSecondary(brightness)),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Lively.separatorStrong(brightness),
              width: Lively.bThick,
            ),
          ),
        ),
        listBullet: base.copyWith(color: Lively.textSecondary(brightness)),
        h1: base.copyWith(fontSize: fontSize + 5, fontWeight: FontWeight.w600),
        h2: base.copyWith(fontSize: fontSize + 3, fontWeight: FontWeight.w600),
        h3: base.copyWith(fontSize: fontSize + 1, fontWeight: FontWeight.w600),
        a: base.copyWith(color: Lively.accentText(brightness)),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Lively.separator(brightness)),
          ),
        ),
      ),
    );
  }
}

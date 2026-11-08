import 'package:flutter/material.dart';

import '../../../core/theme/lively_tokens.dart';
import '../nodes.dart';
import '../schema.dart';

/// Card — a titled container for related content.
class CardWidget extends StatelessWidget {
  const CardWidget({
    super.key,
    required this.node,
    required this.renderNode,
  });

  final CardNode node;
  final Widget Function(UiNode child) renderNode;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    // Trim to the schema bounds: an oversized card is never rendered whole.
    final children = node.children.take(Limits.maxChildren).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: Lively.s3),
      padding: const EdgeInsets.all(Lively.s4),
      decoration: BoxDecoration(
        color: Lively.surfaceRaised(brightness),
        border: Border.all(color: Lively.separator(brightness)),
        borderRadius: BorderRadius.circular(Lively.rLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Head: title plus an item-count badge.
          Row(
            children: [
              Expanded(
                child: Text(
                  node.title,
                  style: TextStyle(
                    fontSize: Lively.tFootnote,
                    height: Lively.lhFootnote,
                    fontWeight: FontWeight.w600,
                    color: Lively.textPrimary(brightness),
                  ),
                ),
              ),
              const SizedBox(width: Lively.s2),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Lively.s2,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Lively.fill(brightness, 1),
                  borderRadius: BorderRadius.circular(Lively.rCapsule),
                ),
                child: Text(
                  '${children.length} ${children.length == 1 ? 'item' : 'items'}',
                  style: TextStyle(
                    fontSize: Lively.tMicro,
                    height: Lively.lhMicro,
                    color: Lively.textSecondary(brightness),
                  ),
                ),
              ),
            ],
          ),
          if (node.description != null) ...[
            const SizedBox(height: Lively.s2),
            Text(
              node.description!,
              style: TextStyle(
                fontSize: Lively.tFootnote,
                height: Lively.lhFootnote,
                color: Lively.textSecondary(brightness),
              ),
            ),
          ],
          if (children.isNotEmpty) ...[
            const SizedBox(height: Lively.s3),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: Lively.s3),
              renderNode(children[i]),
            ],
          ],
        ],
      ),
    );
  }
}

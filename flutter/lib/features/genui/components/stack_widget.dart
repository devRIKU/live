import 'package:flutter/material.dart';

import '../../../core/theme/lively_tokens.dart';
import '../nodes.dart';
import '../schema.dart';

/// Stack — the root layout container.
///
/// Rows place cards side by side; columns stack them. It is the entry point
/// of every generated program, so it accepts cards as well as leaf content.
class StackWidget extends StatelessWidget {
  const StackWidget({
    super.key,
    required this.node,
    required this.renderNode,
  });

  final StackNode node;

  /// Renders a child node; handed down by the Renderer.
  final Widget Function(UiNode child) renderNode;

  /// Gap between children, mapped from the `gap` prop onto the spacing
  /// scale (`none` → 0, `sm` → `--s-2`, `md` → `--s-3`, `lg` → `--s-5`).
  static double gapOf(Gap gap) => switch (gap) {
        Gap.none => Lively.s0,
        Gap.sm => Lively.s2,
        Gap.md => Lively.s3,
        Gap.lg => Lively.s5,
      };

  @override
  Widget build(BuildContext context) {
    // Trim to the schema bounds: an oversized stack is never rendered whole.
    final children = node.children.take(Limits.maxChildren).toList();
    final gap = gapOf(node.gap);

    if (node.direction == StackDirection.row) {
      // Rows wrap, align to the start, like the CSS flex row in the source.
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        crossAxisAlignment: WrapCrossAlignment.start,
        children: [for (final child in children) renderNode(child)],
      );
    }

    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) items.add(SizedBox(height: gap));
      items.add(renderNode(children[i]));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: items,
    );
  }
}

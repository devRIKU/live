import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;

import '../../../core/theme/lively_tokens.dart';
import '../nodes.dart';
import '../schema.dart';

/// Steps — an ordered guide.
class StepsWidget extends StatelessWidget {
  const StepsWidget({super.key, required this.node});

  final StepsNode node;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    // Trim to the schema bounds: an oversized list is never rendered whole.
    final items = node.items.take(Limits.maxSteps).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Lively.s1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: Lively.s3),
            _StepRow(
              index: i,
              item: items[i],
              brightness: brightness,
            ),
          ],
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.index,
    required this.item,
    required this.brightness,
  });

  final int index;
  final StepItemData item;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final status = item.status ?? StepStatus.pending;
    final done = status == StepStatus.done;
    final active = status == StepStatus.active;

    final Color badgeColor = done
        ? Lively.appleGreen
        : active
            ? Lively.accent(brightness)
            : Lively.textTertiary(brightness);
    final Color badgeBorder = done || active
        ? badgeColor
        : Lively.separatorStrong(brightness);
    final Color badgeFill = active
        ? Lively.accentMuted(brightness)
        : Lively.fill(brightness, 1);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: badgeFill,
            shape: BoxShape.circle,
            border: Border.all(color: badgeBorder),
          ),
          child: done
              ? const Icon(fluent.FluentIcons.check_mark, size: 12, color: Lively.appleGreen)
              : Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: Lively.tMicro,
                    height: Lively.lhMicro,
                    fontWeight: FontWeight.w600,
                    color: badgeColor,
                  ),
                ),
        ),
        const SizedBox(width: Lively.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: TextStyle(
                  fontSize: Lively.tFootnote,
                  height: Lively.lhFootnote,
                  fontWeight: FontWeight.w600,
                  color: Lively.textPrimary(brightness),
                ),
              ),
              if (item.description != null) ...[
                const SizedBox(height: 2),
                Text(
                  item.description!,
                  style: TextStyle(
                    fontSize: Lively.tCaption,
                    height: Lively.lhCaption,
                    color: Lively.textSecondary(brightness),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

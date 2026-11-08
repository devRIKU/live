import 'package:flutter/material.dart';

import '../../../core/theme/lively_tokens.dart';
import '../nodes.dart';
import '../schema.dart';

/// Table — structured rows for comparisons and lookups.
class TableWidget extends StatelessWidget {
  const TableWidget({super.key, required this.node});

  final TableNode node;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    // Trim to the schema bounds: an oversized table is never rendered whole.
    final columns = node.columns.take(Limits.maxTableColumns).toList();
    final rows = node.rows
        .take(Limits.maxTableRows)
        .map((row) => row.take(Limits.maxTableCells).toList())
        .toList();

    final cellStyle = TextStyle(
      fontSize: Lively.tFootnote,
      height: Lively.lhFootnote,
      color: Lively.textPrimary(brightness),
    );
    final headStyle = cellStyle.copyWith(
      fontWeight: FontWeight.w600,
      color: Lively.textSecondary(brightness),
    );

    Widget cell(String text, TextStyle style) => Padding(
          padding: const EdgeInsets.symmetric(
            vertical: Lively.s2,
            horizontal: Lively.s2,
          ),
          child: Text(text, style: style, overflow: TextOverflow.ellipsis),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: Lively.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (node.caption != null) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                node.caption!,
                style: TextStyle(
                  fontSize: Lively.tMicro,
                  height: Lively.lhMicro,
                  color: Lively.textTertiary(brightness),
                ),
              ),
            ),
          ],
          // A cell is plain text or a number — never markup, never a component.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: MediaQuery.sizeOf(context).width,
              ),
              child: Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Lively.separator(brightness)),
                      ),
                    ),
                    children: [
                      for (final col in columns) cell(col, headStyle),
                    ],
                  ),
                  for (final row in rows)
                    TableRow(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom:
                              BorderSide(color: Lively.gridLine(brightness)),
                        ),
                      ),
                      children: [
                        for (final value in row)
                          cell(_cellText(value), cellStyle),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _cellText(Object value) =>
      value is num ? formatNumber(value) : '$value';
}

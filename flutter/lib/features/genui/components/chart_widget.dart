import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/lively_tokens.dart';
import '../nodes.dart';
import '../schema.dart';

/// Chart — a small bar, line or area chart drawn with a [CustomPainter].
///
/// Deliberately minimal: no charting dependency, no animation, no axes
/// beyond labels. It exists so the model can show a shape of data without
/// pulling a chart library into the bundle. The geometry mirrors the inline
/// SVG of the React component (viewBox `0 0 600 150`, stretched to width).
class ChartWidget extends StatelessWidget {
  const ChartWidget({super.key, required this.node});

  final ChartNode node;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    // The parser cannot see a length mismatch, so clip to the shorter array
    // and to the schema bound.
    final count = math.min(
      math.min(node.labels.length, node.values.length),
      Limits.maxChartPoints,
    );
    final labels = node.labels.sublist(0, count);
    final values = node.values.sublist(0, count);

    if (count == 0) {
      return Text(
        'Chart has no data points.',
        style: TextStyle(
          fontSize: Lively.tFootnote,
          height: Lively.lhFootnote,
          color: Lively.textSecondary(brightness),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (node.title != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: Lively.s2),
            child: Text(
              node.title!,
              style: TextStyle(
                fontSize: Lively.tFootnote,
                height: Lively.lhFootnote,
                color: Lively.textSecondary(brightness),
              ),
            ),
          ),
        ],
        Semantics(
          image: true,
          label: node.title ?? '${node.chartType.name} chart',
          child: SizedBox(
            height: 150,
            width: double.infinity,
            child: CustomPaint(
              painter: _ChartPainter(
                chartType: node.chartType,
                labels: labels,
                values: values,
                accent: Lively.accent(brightness),
                baseline: Lively.separator(brightness),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        // One label per point, evenly distributed and clipped.
        Row(
          children: [
            for (final label in labels)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: Lively.textTertiary(brightness),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Draws the chart body. Port of the inline SVG geometry: baseline, bars,
/// polyline, and the translucent area polygon.
class _ChartPainter extends CustomPainter {
  const _ChartPainter({
    required this.chartType,
    required this.labels,
    required this.values,
    required this.accent,
    required this.baseline,
  });

  final ChartType chartType;
  final List<String> labels;
  final List<double> values;
  final Color accent;
  final Color baseline;

  @override
  void paint(Canvas canvas, Size size) {
    final count = values.length;
    if (count == 0) return;

    // Same min/max rules as the SVG version: the scale reaches zero when any
    // value is negative, and never collapses to a zero span.
    final min = values.fold<double>(0, math.min);
    final max = values.fold<double>(1, math.max);
    final span = (max - min) != 0 ? (max - min) : 1.0;
    final height = size.height;
    final width = size.width;
    final step = width / count;
    final barWidth = math.max(2.0, math.min(48.0, step * 0.6));
    double x(int i) => i * step + (step - barWidth) / 2;
    double y(double v) => height - ((v - min) / span) * height;

    final linePaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // Baseline.
    canvas.drawLine(
      Offset(0, height),
      Offset(width, height),
      Paint()
        ..color = baseline
        ..strokeWidth = 1,
    );

    switch (chartType) {
      case ChartType.bar:
        final fill = Paint()..color = accent;
        for (var i = 0; i < count; i++) {
          final top = y(values[i]);
          canvas.drawRect(
            Rect.fromLTWH(x(i), top, barWidth, math.max(1, height - top)),
            fill,
          );
        }
      case ChartType.line:
        canvas.drawPath(_polyline(count, barWidth, x, y), linePaint);
      case ChartType.area:
        final area = Path()
          ..moveTo(0, height)
          ..lineTo(x(0) + barWidth / 2, y(values[0]));
        for (var i = 1; i < count; i++) {
          area.lineTo(x(i) + barWidth / 2, y(values[i]));
        }
        area
          ..lineTo(width, height)
          ..close();
        canvas.drawPath(area, Paint()..color = accent.withOpacity(0.18));
        canvas.drawPath(_polyline(count, barWidth, x, y), linePaint);
    }
  }

  Path _polyline(
    int count,
    double barWidth,
    double Function(int) x,
    double Function(double) y,
  ) {
    final path = Path();
    for (var i = 0; i < count; i++) {
      final px = x(i) + barWidth / 2;
      final py = y(values[i]);
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(_ChartPainter oldDelegate) =>
      oldDelegate.chartType != chartType ||
      oldDelegate.labels != labels ||
      oldDelegate.values != values ||
      oldDelegate.accent != accent ||
      oldDelegate.baseline != baseline;
}

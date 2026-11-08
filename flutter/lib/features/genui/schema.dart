import 'package:flutter/material.dart' show Brightness, Color;

import '../../core/theme/lively_tokens.dart';

// ignore_for_file: comment_references

/// Schemas for the OpenUI component library.
///
/// These schemas are the security boundary for generative UI (SPEC §7.2):
/// every value a model emits is validated against them before it reaches the
/// widget tree, and each one carries its own resource bound, so an oversized
/// or ill-typed payload is rejected by the parser instead of being rendered.
///
/// In the React app these are Zod schemas built by `@openuidev/react-lang`
/// components. In Dart the same bounds live here as constants plus small
/// validator functions; the parser (`parser.dart`) enforces the types and the
/// Form widget enforces the runtime value rules, while `validate.dart`
/// enforces the size bounds and reports them as notices.
///
/// Argument order matters: OpenUI Lang maps positional arguments onto props
/// in schema key order, so required props come first and optional props last.
/// That order is recorded in `library.dart` (`ComponentSpec.props`).

/// Resource bounds enforced by the schemas in this file.
abstract final class Limits {
  const Limits._();

  /// Deepest component nesting the app renders (Stack > Card > leaf).
  static const int maxDepth = 3;

  /// Max rows in a Table.
  static const int maxTableRows = 50;

  /// Max columns in a Table.
  static const int maxTableColumns = 12;

  /// Max cells per row in a Table.
  static const int maxTableCells = 12;

  /// Max data points in a Chart.
  static const int maxChartPoints = 100;

  /// Max fields in a Form.
  static const int maxFormFields = 20;

  /// Max options on a select field.
  static const int maxFieldOptions = 50;

  /// Max items in a Steps list.
  static const int maxSteps = 20;

  /// Max children in a container.
  static const int maxChildren = 10;

  /// Max characters in a Text block.
  static const int maxTextLength = 4000;

  /// Max characters in a short label (title, caption, button label).
  static const int maxLabelLength = 200;

  /// Max characters in a table cell.
  static const int maxCellLength = 500;

  /// Largest program text we will hand to the parser.
  static const int maxProgramBytes = 64 * 1024;
}

/// Size of a Text block. The wire name of [normal] is `default` in OpenUI
/// Lang (`default` is a reserved word-ish identifier in Dart, so it is
/// spelled `normal` here and mapped by the parser).
enum TextSize { small, normal, large }

/// Chart shapes the library can draw.
enum ChartType { bar, line, area }

/// Field types accepted by a generative Form.
enum FieldType { text, textarea, number, select, checkbox }

/// Direction of a Stack.
enum StackDirection { column, row }

/// Gap between Stack children, mapped onto the spacing scale.
enum Gap { none, sm, md, lg }

/// Lifecycle marker of a Steps item.
enum StepStatus { pending, active, done }

/// Visual weight of a Button.
enum ButtonVariant { primary, secondary, ghost }

/// A table cell is plain text or a number — never markup, never a component.
typedef TableCell = Object; // String or num, enforced by the parser.

/// One field of a generative form.
class FormFieldData {
  const FormFieldData({
    required this.name,
    required this.label,
    required this.type,
    this.placeholder,
    this.required = false,
    this.options,
    this.min,
    this.max,
  });

  /// Wire-name bounds from `FormFieldSchema` (name 1..64, label 1..128).
  static const int maxNameLength = 64;
  static const int maxLabelLength = 128;
  static const int maxPlaceholderLength = 128;
  static const int maxOptionLength = 128;

  final String name;
  final String label;
  final FieldType type;
  final String? placeholder;
  final bool required;
  final List<String>? options;
  final double? min;
  final double? max;
}

/// One step of a step-by-step guide.
class StepItemData {
  const StepItemData({
    required this.title,
    this.description,
    this.status,
  });

  /// Wire-name bound from `StepItemSchema` (description max 1000).
  static const int maxDescriptionLength = 1000;

  final String title;
  final String? description;
  final StepStatus? status;
}

/// Validate a single field value, mirroring `validateField` from the React
/// `Form` component: values are checked *before* the action runs, so a
/// malformed value never reaches a tool call or the next chat turn
/// (SPEC §7.2.5).
///
/// Returns an error message, or `null` when the value is acceptable.
String? validateFieldValue(FormFieldData field, Object? value) {
  if (field.type == FieldType.checkbox) {
    return (field.required && value != true) ? 'Required' : null;
  }
  final text = value is String ? value.trim() : '';
  if (field.required && text.isEmpty) return 'Required';
  if (text.isEmpty) return null;
  if (field.type == FieldType.number) {
    final n = double.tryParse(text);
    if (n == null) return 'Must be a number';
    if (field.min != null && n < field.min!) {
      return 'Minimum is ${_trimNum(field.min!)}';
    }
    if (field.max != null && n > field.max!) {
      return 'Maximum is ${_trimNum(field.max!)}';
    }
  }
  return null;
}

/// Render a number the way JS `String(number)` would: drop a trailing `.0`.
String _trimNum(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

/// Render a number for display in cells and notices.
String formatNumber(num v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

/// Colors used by the generative-UI surfaces, kept next to the schema so
/// every component shares one mapping of Lively tokens.
abstract final class GenUiColors {
  const GenUiColors._();

  static Color warn(Brightness b) =>
      b == Brightness.dark ? Lively.appleOrange : Lively.orange600;

  static Color warnSurface(Brightness b) =>
      b == Brightness.dark ? Lively.fill(b, 1) : Lively.butter100;

  static Color success(Brightness b) => Lively.appleGreen;
}

/// Resource-bound validation for a generated program.
///
/// The OpenUI parser checks types, enums and required props, but it does not
/// enforce the size limits a schema can express (`maxItems`, `maxLength`).
/// Those limits are the app's own guard against resource exhaustion
/// (SPEC §7.2.4), so they are checked here, against the same constants the
/// component specs are built from.
///
/// A violation never throws: the offending collection is trimmed by the
/// component that renders it, and the violation is reported as a notice.
library;

import 'nodes.dart';
import 'parser.dart';
import 'schema.dart';

/// One oversized value in a generated program.
class Violation {
  const Violation({
    required this.component,
    required this.message,
    this.statementId,
  });

  /// Component the value belongs to, e.g. `Table`.
  final String component;

  /// Statement the component came from, when it had one.
  final String? statementId;

  /// Human-readable description of the problem.
  final String message;
}

class _CollectionBound {
  const _CollectionBound(this.prop, this.max, this.label);

  final String prop;
  final int max;
  final String label;
}

/// Collection limits per component.
const Map<String, List<_CollectionBound>> _collectionBounds = {
  'Table': [
    _CollectionBound('rows', Limits.maxTableRows, 'rows'),
    _CollectionBound('columns', Limits.maxTableColumns, 'columns'),
  ],
  'Chart': [
    _CollectionBound('labels', Limits.maxChartPoints, 'data points'),
    _CollectionBound('values', Limits.maxChartPoints, 'data points'),
  ],
  'Form': [_CollectionBound('fields', Limits.maxFormFields, 'fields')],
  'Steps': [_CollectionBound('items', Limits.maxSteps, 'steps')],
  'Card': [_CollectionBound('children', Limits.maxChildren, 'children')],
  'Stack': [_CollectionBound('children', Limits.maxChildren, 'children')],
};

/// Visit every element in a parsed program, parents before children.
void _walkElements(UiNode node, void Function(UiNode) visit) {
  visit(node);
  for (final value in node.props.values) {
    if (value is UiNode) {
      _walkElements(value, visit);
    } else if (value is List) {
      for (final item in value) {
        if (item is UiNode) _walkElements(item, visit);
      }
    }
  }
}

/// Find every value in the program that exceeds a resource bound.
///
/// Returns an empty list for a program that fits within the bounds. A program
/// that does not parse at all yields no violations — the parser's own errors
/// are reported separately.
List<Violation> findViolations(String program) {
  if (program.trim().isEmpty) return const [];

  ParseResult result;
  try {
    result = openallParser.parse(program);
  } catch (_) {
    return const [];
  }
  final root = result.root;
  if (root == null) return const [];

  final violations = <Violation>[];

  _walkElements(root, (element) {
    final props = element.props;

    for (final bound in _collectionBounds[element.typeName] ?? const []) {
      final value = props[bound.prop];
      if (value is List && value.length > bound.max) {
        violations.add(Violation(
          component: element.typeName,
          statementId: element.statementId,
          message:
              '${element.typeName} had ${value.length} ${bound.label}; only the first ${bound.max} are shown.',
        ));
      }
    }

    props.forEach((key, value) {
      if (value is String && value.length > Limits.maxTextLength) {
        violations.add(Violation(
          component: element.typeName,
          statementId: element.statementId,
          message:
              '${element.typeName}.$key was ${value.length} characters; only the first ${Limits.maxTextLength} are shown.',
        ));
      }
    });
  });

  return violations;
}

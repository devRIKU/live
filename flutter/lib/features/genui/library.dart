/// The OpenUI component library.
///
/// The library *is* the allowlist: a model can only emit the components
/// defined here, and each component's schema carries its own resource bound
/// (SPEC §7.2). Anything outside the library is dropped by the parser with an
/// `unknown-component` error instead of reaching the widget tree.
///
/// In the React app this file calls `createLibrary` from
/// `@openuidev/react-lang`. In Dart the same specification is described
/// declaratively here: [ComponentSpec] records each component's name,
/// description, and positional props (in Zod key order — required first,
/// optional last), and the parser maps positional arguments onto them.
library;

import 'schema.dart';

/// Identifier of this library.
const String openallLibraryId = 'openall';

/// The root component of every generated program.
const String openallRoot = 'Stack';

/// The kinds a prop can have. The parser uses these to coerce and type-check
/// each positional argument before it reaches a component widget.
enum PropKind {
  /// A plain string (labels, captions).
  string,

  /// A long string (Text content, descriptions).
  text,

  /// A number.
  number,

  /// A boolean flag.
  boolean,

  /// A list of strings (Table columns, Chart labels).
  stringList,

  /// A list of numbers (Chart values).
  numberList,

  /// A string constrained to [PropSpec.enumValues].
  enumValues,

  /// A list of rows of string-or-number cells (Table rows).
  cellTable,

  /// A list of form-field objects.
  formFields,

  /// A list of step-item objects.
  stepItems,

  /// An OpenUI action expression (`@ToAssistant(...)`, `@OpenUrl(...)`).
  action,

  /// Children restricted to leaf components (Card's children).
  leafChildren,

  /// Children allowed to be Cards or leaves (Stack's children).
  stackChildren,
}

/// One prop of a component, in positional order.
class PropSpec {
  const PropSpec(
    this.name, {
    required this.kind,
    this.required = false,
    this.enumValues,
    this.max,
  });

  final String name;
  final PropKind kind;
  final bool required;

  /// Allowed values for [PropKind.enumValues].
  final List<String>? enumValues;

  /// Resource bound for list and string props, when the schema has one.
  final int? max;

  /// Whether this prop is required (it comes before every optional prop).
  bool get isOptional => !required;

  /// Human-readable type for the generated system prompt.
  String get typeLabel => switch (kind) {
        PropKind.string || PropKind.text => 'string${max != null ? ' (max $max chars)' : ''}',
        PropKind.number => 'number',
        PropKind.boolean => 'boolean',
        PropKind.stringList =>
          'list of strings${max != null ? ' (max $max)' : ''}',
        PropKind.numberList =>
          'list of numbers${max != null ? ' (max $max)' : ''}',
        PropKind.enumValues =>
          '${(enumValues ?? const []).map((v) => '"$v"').join(' | ')}',
        PropKind.cellTable =>
          'list of rows of strings or numbers${max != null ? ' (max $max rows)' : ''}',
        PropKind.formFields => 'list of field objects',
        PropKind.stepItems => 'list of step objects',
        PropKind.action => 'action expression, e.g. @ToAssistant("...")',
        PropKind.leafChildren =>
          'list of ${leafUnionNames.join(' | ')}${max != null ? ' (max $max)' : ''}',
        PropKind.stackChildren =>
          'list of ${stackUnionNames.join(' | ')}${max != null ? ' (max $max)' : ''}',
      };
}

/// One component of the library: the allowlist entry plus the positional
/// argument order the parser maps onto props.
class ComponentSpec {
  const ComponentSpec({
    required this.name,
    required this.description,
    required this.props,
  });

  final String name;
  final String description;

  /// Positional props, required first, optional last — the Zod key order of
  /// the React schemas, which OpenUI Lang maps positional arguments onto.
  final List<PropSpec> props;

  /// Components allowed as this component's children (empty for leaves).
  List<String> get allowedChildren {
    for (final p in props) {
      if (p.kind == PropKind.stackChildren) return stackUnionNames;
      if (p.kind == PropKind.leafChildren) return leafUnionNames;
    }
    return const <String>[];
  }

  /// The signature shown in the system prompt, e.g. `Table(columns, rows, caption?)`.
  String get signature =>
      '(${props.map((p) => p.required ? p.name : '${p.name}?').join(', ')})';
}

/// The child union — the set of components allowed inside a Card. It
/// deliberately excludes the containers themselves (Card, Stack) so the
/// component tree stays acyclic and the maximum nesting depth stays bounded
/// at three levels: Stack > Card > leaf.
const List<String> leafUnionNames = [
  'Text',
  'Table',
  'Chart',
  'Steps',
  'Button',
  'Form',
];

/// The child union of the Stack — leaves plus Cards.
const List<String> stackUnionNames = [
  'Text',
  'Table',
  'Chart',
  'Steps',
  'Button',
  'Form',
  'Card',
];

/// Every component of the library, in allowlist order.
final List<ComponentSpec> openallComponents = [
  const ComponentSpec(
    name: 'Stack',
    description:
        'The root container. Lays out cards and content in a column (default) or a row.',
    props: [
      PropSpec('children',
          kind: PropKind.stackChildren,
          required: true,
          max: Limits.maxChildren),
      PropSpec('direction',
          kind: PropKind.enumValues,
          enumValues: ['column', 'row']),
      PropSpec('gap',
          kind: PropKind.enumValues, enumValues: ['none', 'sm', 'md', 'lg']),
    ],
  ),
  const ComponentSpec(
    name: 'Card',
    description:
        'A titled container. Use it to group a short explanation with a table, chart or form.',
    props: [
      PropSpec('title',
          kind: PropKind.string, required: true, max: Limits.maxLabelLength),
      PropSpec('children',
          kind: PropKind.leafChildren,
          required: true,
          max: Limits.maxChildren),
      PropSpec('description', kind: PropKind.string, max: 2000),
    ],
  ),
  const ComponentSpec(
    name: 'Text',
    description:
        'A block of text. Supports markdown. Use it for prose, explanations and short lists.',
    props: [
      PropSpec('text',
          kind: PropKind.text, required: true, max: Limits.maxTextLength),
      PropSpec('size',
          kind: PropKind.enumValues, enumValues: ['small', 'default', 'large']),
    ],
  ),
  const ComponentSpec(
    name: 'Table',
    description:
        'A data table. Use it to compare items, list results, or show structured rows with one value per column.',
    props: [
      PropSpec('columns',
          kind: PropKind.stringList,
          required: true,
          max: Limits.maxTableColumns),
      PropSpec('rows',
          kind: PropKind.cellTable,
          required: true,
          max: Limits.maxTableRows),
      PropSpec('caption',
          kind: PropKind.string, max: Limits.maxLabelLength),
    ],
  ),
  const ComponentSpec(
    name: 'Chart',
    description:
        'A bar, line or area chart. labels and values must have the same length; one value per label.',
    props: [
      PropSpec('chartType',
          kind: PropKind.enumValues,
          required: true,
          enumValues: ['bar', 'line', 'area']),
      PropSpec('labels',
          kind: PropKind.stringList, required: true, max: Limits.maxChartPoints),
      PropSpec('values',
          kind: PropKind.numberList, required: true, max: Limits.maxChartPoints),
      PropSpec('title', kind: PropKind.string, max: Limits.maxLabelLength),
    ],
  ),
  const ComponentSpec(
    name: 'Form',
    description:
        'A short form. Values are validated before the action runs; use it to collect a few details from the user.',
    props: [
      PropSpec('fields',
          kind: PropKind.formFields, required: true, max: Limits.maxFormFields),
      PropSpec('action', kind: PropKind.action),
      PropSpec('title', kind: PropKind.string, max: Limits.maxLabelLength),
      PropSpec('submitLabel', kind: PropKind.string, max: 64),
    ],
  ),
  const ComponentSpec(
    name: 'Steps',
    description:
        'A numbered, step-by-step guide. Use it for instructions and procedures.',
    props: [
      PropSpec('items',
          kind: PropKind.stepItems, required: true, max: Limits.maxSteps),
    ],
  ),
  const ComponentSpec(
    name: 'Button',
    description:
        'A button. Its action runs when the user clicks it — use @ToAssistant to ask a follow-up question.',
    props: [
      PropSpec('label',
          kind: PropKind.string, required: true, max: Limits.maxLabelLength),
      PropSpec('action', kind: PropKind.action),
      PropSpec('variant',
          kind: PropKind.enumValues,
          enumValues: ['primary', 'secondary', 'ghost']),
    ],
  ),
];

/// Component groups, as listed to the model in the system prompt.
final Map<String, List<String>> openallComponentGroups = {
  'Layout': ['Stack', 'Card'],
  'Content': ['Text'],
  'Data': ['Table', 'Chart'],
  'Interaction': ['Form', 'Button', 'Steps'],
};

/// Lookup by component name; `null` for anything outside the allowlist.
ComponentSpec? componentSpecByName(String name) {
  for (final spec in openallComponents) {
    if (spec.name == name) return spec;
  }
  return null;
}

import 'actions.dart';
import 'schema.dart';

/// The immutable node model for a parsed OpenUI Lang program.
///
/// The React app renders the raw element tree the official parser produces.
/// Here the parser (`parser.dart`) produces this sealed hierarchy instead,
/// and the `Renderer` in `open_ui_message.dart` dispatches on the concrete
/// subclass. Every node records the statement it came from (`statementId`),
/// which the Form widget uses as its form name and `validate.dart` uses to
/// attribute a violation.
sealed class UiNode {
  const UiNode({required this.typeName, this.statementId});

  /// The OpenUI component name, e.g. `Table`.
  final String typeName;

  /// The statement the component came from, when it had one.
  final String? statementId;

  /// Generic prop view used by `validate.dart` to walk the tree and check
  /// resource bounds — child nodes appear inside list values.
  Map<String, Object?> get props;
}

/// Stack — the root layout container.
final class StackNode extends UiNode {
  const StackNode({
    required this.children,
    this.direction = StackDirection.column,
    this.gap = Gap.md,
    super.statementId,
  }) : super(typeName: 'Stack');

  final List<UiNode> children;
  final StackDirection direction;
  final Gap gap;

  @override
  Map<String, Object?> get props => {
        'children': children,
        'direction': direction.name,
        'gap': gap.name,
      };
}

/// Card — a titled container for related content.
final class CardNode extends UiNode {
  const CardNode({
    required this.title,
    required this.children,
    this.description,
    super.statementId,
  }) : super(typeName: 'Card');

  final String title;
  final List<UiNode> children;
  final String? description;

  @override
  Map<String, Object?> get props => {
        'title': title,
        'children': children,
        if (description != null) 'description': description,
      };
}

/// Text — a block of prose inside a generated interface.
final class TextNode extends UiNode {
  const TextNode({
    required this.text,
    this.size = TextSize.normal,
    super.statementId,
  }) : super(typeName: 'Text');

  final String text;
  final TextSize size;

  @override
  Map<String, Object?> get props => {'text': text, 'size': size.name};
}

/// Table — structured rows for comparisons and lookups.
final class TableNode extends UiNode {
  const TableNode({
    required this.columns,
    required this.rows,
    this.caption,
    super.statementId,
  }) : super(typeName: 'Table');

  final List<String> columns;

  /// Each row is a list of cells; a cell is a [String] or a [num].
  final List<List<Object>> rows;
  final String? caption;

  @override
  Map<String, Object?> get props => {
        'columns': columns,
        'rows': rows,
        if (caption != null) 'caption': caption,
      };
}

/// Chart — a small bar, line or area chart.
final class ChartNode extends UiNode {
  const ChartNode({
    required this.chartType,
    required this.labels,
    required this.values,
    this.title,
    super.statementId,
  }) : super(typeName: 'Chart');

  final ChartType chartType;
  final List<String> labels;
  final List<double> values;
  final String? title;

  @override
  Map<String, Object?> get props => {
        'chartType': chartType.name,
        'labels': labels,
        'values': values,
        if (title != null) 'title': title,
      };
}

/// Form — a short, validated form.
final class FormNode extends UiNode {
  const FormNode({
    required this.fields,
    this.action,
    this.title,
    this.submitLabel,
    super.statementId,
  }) : super(typeName: 'Form');

  final List<FormFieldData> fields;
  final OpenUIAction? action;
  final String? title;
  final String? submitLabel;

  @override
  Map<String, Object?> get props => {
        'fields': fields,
        if (action != null) 'action': action,
        if (title != null) 'title': title,
        if (submitLabel != null) 'submitLabel': submitLabel,
      };
}

/// Steps — an ordered guide.
final class StepsNode extends UiNode {
  const StepsNode({required this.items, super.statementId})
      : super(typeName: 'Steps');

  final List<StepItemData> items;

  @override
  Map<String, Object?> get props => {'items': items};
}

/// Button — a clickable control that runs an action.
final class ButtonNode extends UiNode {
  const ButtonNode({
    required this.label,
    this.action,
    this.variant = ButtonVariant.primary,
    super.statementId,
  }) : super(typeName: 'Button');

  final String label;
  final OpenUIAction? action;
  final ButtonVariant variant;

  @override
  Map<String, Object?> get props => {
        'label': label,
        if (action != null) 'action': action,
        'variant': variant.name,
      };
}

/// The leaf components allowed inside a container — it deliberately excludes
/// the containers themselves (Card, Stack) so the component tree stays
/// acyclic and the maximum nesting depth stays bounded at three levels:
/// Stack > Card > leaf.
bool isLeafNode(UiNode node) =>
    node is TextNode ||
    node is TableNode ||
    node is ChartNode ||
    node is StepsNode ||
    node is ButtonNode ||
    node is FormNode;

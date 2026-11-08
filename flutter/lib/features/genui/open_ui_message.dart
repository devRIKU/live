/// OpenUIMessage — renders one assistant turn as genuine UI.
///
/// The turn may be prose, an OpenUI Lang program, or both. Prose renders as
/// markdown; a program is parsed, bounded and dispatched to the component
/// widgets that the library allowlists. Port of `src/genui/OpenUIMessage.tsx`.
library;

import 'package:flutter/material.dart';

import '../../shared/markdown_view.dart';
import '../../core/theme/lively_tokens.dart';
import 'components/button_widget.dart';
import 'components/card_widget.dart';
import 'components/chart_widget.dart';
import 'components/form_widget.dart';
import 'components/stack_widget.dart';
import 'components/steps_widget.dart';
import 'components/table_widget.dart';
import 'components/text_widget.dart';
import 'actions.dart';
import 'nodes.dart';
import 'parser.dart';
import 'runtime.dart';
import 'split.dart';
import 'validate.dart';

class OpenUIMessage extends StatelessWidget {
  final String content;
  final bool isStreaming;
  final void Function(OpenUIActionEvent event)? onAction;

  const OpenUIMessage({
    super.key,
    required this.content,
    this.isStreaming = false,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final parts = splitMessage(content);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final part in parts) _part(context, part),
      ],
    );
  }

  Widget _part(BuildContext context, MessagePart part) {
    if (part is ProsePart) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Lively.threadGap),
        child: MarkdownView(content: part.text),
      );
    }
    if (part is! ProgramPart) {
      return const SizedBox.shrink();
    }

    // A program part: parse, bound-check, then dispatch on the node type.
    final result = openallParser.parse(part.text);
    final violations = findViolations(part.text);
    if (result.root == null || result.errors.isNotEmpty) {
      return ErrorNotice(errors: [
        for (final e in result.errors) e.message,
        for (final v in violations) '${v.component}: ${v.message}',
      ]);
    }

    final formStore = OpenUIFormStore();
    final rendered = OpenUIRuntimeScope(
      runtime: OpenUIRuntime(
        isStreaming: isStreaming,
        formStore: formStore,
        triggerAction: (label, formName, action) {
          if (action == null) return;
          final event = buildActionEvent(action,
              formName: formName, formStore: formStore);
          onAction?.call(event);
        },
      ),
      child: renderNode(result.root!),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: Lively.threadGap),
      child: rendered,
    );
  }

  Widget renderNode(UiNode node) {
    // `UiNode` is sealed, so this switch is exhaustive without a default.
    // Each arm binds the node explicitly rather than relying on promotion.
    return switch (node) {
      StackNode n => StackWidget(node: n, renderNode: renderNode),
      CardNode n => CardWidget(node: n, renderNode: renderNode),
      TextNode n => TextWidget(node: n),
      TableNode n => TableWidget(node: n),
      ChartNode n => ChartWidget(node: n),
      FormNode n => FormWidget(node: n),
      StepsNode n => StepsWidget(node: n),
      ButtonNode n => ButtonWidget(node: n),
    };
  }

  Brightness _bOf(BuildContext context) => Theme.of(context).brightness;
}

/// A quiet error card — generation is never a hard failure.
class ErrorNotice extends StatelessWidget {
  final List<String> errors;
  const ErrorNotice({super.key, required this.errors});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final lines = [for (final e in errors) '• $e'];
    return Container(
      padding: const EdgeInsets.all(Lively.s3),
      decoration: BoxDecoration(
        color: Lively.surfaceSunken(b),
        borderRadius: BorderRadius.circular(Lively.rLg),
        border: Border.all(color: Lively.separator(b), width: Lively.bHairline),
      ),
      child: Text(
        'This interface could not be rendered:\n${lines.join('\n')}',
        style: TextStyle(
          color: Lively.textSecondary(b),
          fontSize: Lively.tFootnote,
          fontFamily: 'Consolas, "Cascadia Mono", monospace',
          height: 1.45,
        ),
      ),
    );
  }
}

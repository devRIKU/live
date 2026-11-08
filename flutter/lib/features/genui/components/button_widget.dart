import 'package:flutter/material.dart' hide Button;
import 'package:fluent_ui/fluent_ui.dart' as fluent;

import '../../../core/theme/lively_tokens.dart';
import '../actions.dart';
import '../nodes.dart';
import '../runtime.dart';
import '../schema.dart';

/// Button — a clickable control that runs an action.
///
/// The action is an OpenUI action expression (`@ToAssistant(...)`,
/// `@OpenUrl(...)`). Nothing here executes model-authored code: the runtime
/// turns the expression into a structured event that the host handles.
class ButtonWidget extends StatelessWidget {
  const ButtonWidget({super.key, required this.node});

  final ButtonNode node;

  @override
  Widget build(BuildContext context) {
    final runtime = OpenUIRuntimeScope.of(context);
    final brightness = Theme.of(context).brightness;

    // Disabled while the assistant is streaming, like the React component.
    final onPressed = runtime.isStreaming
        ? null
        : () => runtime.triggerAction(node.label, null, node.action);

    final label = node.label;
    final child = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Lively.s2,
        vertical: 2,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: Lively.tFootnote,
          height: Lively.lhFootnote,
          fontWeight: FontWeight.w600,
          color: node.variant == ButtonVariant.primary
              ? const Color(0xFFFFFFFF)
              : Lively.textPrimary(brightness),
        ),
      ),
    );

    return switch (node.variant) {
      // data-tone="primary"
      ButtonVariant.primary => fluent.Button(
          onPressed: onPressed,
          style: fluent.ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.disabled)
                    ? Lively.fill(brightness, 2)
                    : Lively.accent(brightness)),
            foregroundColor: WidgetStateProperty.all(const Color(0xFFFFFFFF)),
            padding: WidgetStateProperty.all(EdgeInsets.zero),
          ),
          child: child,
        ),
      ButtonVariant.secondary => fluent.Button(
          onPressed: onPressed,
          style: fluent.ButtonStyle(padding: WidgetStateProperty.all(EdgeInsets.zero)),
          child: child,
        ),
      // A ghost button renders as a quiet text action.
      ButtonVariant.ghost => TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: Lively.s2,
              vertical: Lively.s1,
            ),
            foregroundColor: Lively.textPrimary(brightness),
          ),
          child: child,
        ),
    };
  }
}

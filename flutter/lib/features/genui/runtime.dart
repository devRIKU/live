import 'package:flutter/widgets.dart';

import 'actions.dart';

/// The runtime context a generated component runs in.
///
/// The React app gets these from `useIsStreaming`, `useTriggerAction` and
/// `useSetFieldValue` hooks of `@openuidev/react-lang`. Here the renderer
/// installs one [OpenUIRuntimeScope] above the component tree, and the Form
/// and Button widgets read it from the context.
class OpenUIRuntime {
  const OpenUIRuntime({
    required this.isStreaming,
    required this.formStore,
    required this.triggerAction,
  });

  /// True while the assistant is still streaming — submits are disabled.
  final bool isStreaming;

  /// Form values are mirrored here as the user types; a snapshot is attached
  /// to the action event as `formState` on submit.
  final OpenUIFormStore formStore;

  /// Emit a structured action event to the host (the message widget forwards
  /// it to `onAction`).
  final void Function(
    String label,
    String? formName,
    OpenUIAction? action,
  ) triggerAction;
}

/// Provides the [OpenUIRuntime] to generated components.
class OpenUIRuntimeScope extends InheritedWidget {
  const OpenUIRuntimeScope({
    super.key,
    required this.runtime,
    required super.child,
  });

  final OpenUIRuntime runtime;

  static OpenUIRuntime of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<OpenUIRuntimeScope>();
    assert(scope != null, 'No OpenUIRuntimeScope above this widget.');
    return scope!.runtime;
  }

  @override
  bool updateShouldNotify(OpenUIRuntimeScope oldWidget) =>
      oldWidget.runtime != runtime;
}

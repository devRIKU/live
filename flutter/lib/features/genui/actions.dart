/// Turning OpenUI action events into things the host can do.
///
/// A generated component never acts on its own: it emits a structured event
/// and the host decides what happens. That is where the safety rules live —
/// a link is only opened when its scheme is http(s), and a form's values are
/// attached to the next turn as plain text.
///
/// The React app imports `ActionEvent` from `@openuidev/react-lang`; here the
/// same event shape is defined as plain Dart so the Flutter host can consume
/// it without any runtime dependency.
library;

import 'schema.dart' show formatNumber;

/// What an OpenUI action expression asked the host to do.
enum OpenUIActionKind {
  /// `@ToAssistant("...")` — continue the conversation.
  toAssistant,

  /// `@OpenUrl("...")` — open a link (http(s) only, see [isSafeUrl]).
  openUrl,
}

/// An action expression as authored in OpenUI Lang, e.g.
/// `@ToAssistant("Book a call")`.
class OpenUIAction {
  const OpenUIAction({required this.kind, required this.message, this.params});

  final OpenUIActionKind kind;

  /// The action's message — the literal first argument.
  final String message;

  /// Extra literal arguments (e.g. a `{context: ...}` object), already
  /// reduced to plain values.
  final Map<String, Object?>? params;

  @override
  String toString() =>
      '@${kind == OpenUIActionKind.toAssistant ? 'ToAssistant' : 'OpenUrl'}("$message")';
}

/// The structured event a triggered action delivers to the host.
///
/// Mirrors `ActionEvent` from `@openuidev/react-lang`: a `type`, an optional
/// human-friendly message, literal `params`, and the flattened `formState`
/// the runtime attached.
class OpenUIActionEvent {
  const OpenUIActionEvent({
    required this.type,
    this.humanFriendlyMessage,
    this.params = const {},
    this.formState,
  });

  /// `continue_conversation` | `open_url`
  final String type;
  final String? humanFriendlyMessage;
  final Map<String, Object?> params;

  /// `{ formName: { fieldName: { value } } }`
  final Map<String, Map<String, OpenUIFieldValue>>? formState;

  Map<String, Object?> toJson() => {
        'type': type,
        if (humanFriendlyMessage != null)
          'humanFriendlyMessage': humanFriendlyMessage,
        'params': params,
        if (formState != null)
          'formState': {
            for (final entry in (formState ?? {}).entries)
              entry.key: {
                for (final field in entry.value.entries)
                  field.key: {'value': field.value.value},
              },
          },
      };

  @override
  String toString() => 'OpenUIActionEvent($type, $humanFriendlyMessage)';
}

/// One field value mirrored into the OpenUI form store.
class OpenUIFieldValue {
  const OpenUIFieldValue(this.value);

  /// A `String` for text-ish fields, a `bool` for checkboxes.
  final Object? value;
}

/// The OpenUI form store: values are mirrored here as the user types, and a
/// snapshot is attached to the action event as `formState` on submit.
class OpenUIFormStore {
  final Map<String, Map<String, OpenUIFieldValue>> _forms = {};

  /// Mirror one field value, as `useSetFieldValue` does in the React runtime.
  void setFieldValue(String formName, String fieldName, Object? value) {
    (_forms[formName] ??= {})[fieldName] = OpenUIFieldValue(value);
  }

  /// A snapshot of one form, shaped `{ formName: { field: { value } } }`.
  Map<String, Map<String, OpenUIFieldValue>> snapshotFor(String formName) {
    final fields = _forms[formName];
    if (fields == null) return const {};
    return {
      formName: Map<String, OpenUIFieldValue>.of(fields),
    };
  }

  /// A snapshot of every form touched in this program.
  Map<String, Map<String, OpenUIFieldValue>> get snapshot => {
        for (final entry in _forms.entries)
          entry.key: Map<String, OpenUIFieldValue>.of(entry.value),
      };
}

/// Turn an authored [OpenUIAction] into the structured event the host
/// receives, attaching the form snapshot when the action came from a Form.
OpenUIActionEvent buildActionEvent(
  OpenUIAction action, {
  String? formName,
  OpenUIFormStore? formStore,
}) {
  final params = <String, Object?>{...?action.params};
  switch (action.kind) {
    case OpenUIActionKind.toAssistant:
      return OpenUIActionEvent(
        type: 'continue_conversation',
        humanFriendlyMessage: action.message,
        params: params,
        formState:
            formName != null ? formStore?.snapshotFor(formName) : null,
      );
    case OpenUIActionKind.openUrl:
      params['url'] = action.message;
      return OpenUIActionEvent(
        type: 'open_url',
        humanFriendlyMessage: action.message,
        params: params,
        formState:
            formName != null ? formStore?.snapshotFor(formName) : null,
      );
  }
}

/// Only http(s) links may be opened from generated UI.
bool isSafeUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return uri.scheme == 'http' || uri.scheme == 'https';
}

/// Flatten the OpenUI form state into readable lines.
///
/// The runtime stores a form as `{ formName: { fieldName: { value } } }`.
String formatFormState(Map<String, Map<String, OpenUIFieldValue>>? formState) {
  if (formState == null || formState.isEmpty) return '';
  final lines = <String>[];
  formState.forEach((formName, fields) {
    fields.forEach((field, cell) {
      final value = cell.value;
      if (value == null || value == '') return;
      lines.add('$formName.$field: ${_stringify(value)}');
    });
  });
  return lines.join('\n');
}

/// The follow-up user turn an action produces, or `null` when the action is
/// not something the chat can act on.
String? actionToUserMessage(OpenUIActionEvent event) {
  if (event.type != 'continue_conversation') return null;

  final message = event.humanFriendlyMessage?.trim();
  final parts = <String>[(message == null || message.isEmpty) ? 'Continue' : message];

  final context = event.params['context'];
  if (context != null && context != '') {
    parts.add('Context: ${context is String ? context : _jsonLike(context)}');
  }

  final form = formatFormState(event.formState);
  if (form.isNotEmpty) parts.add(form);

  return parts.join('\n');
}

String _stringify(Object value) {
  if (value is bool) return value ? 'true' : 'false';
  if (value is num) return formatNumber(value);
  return '$value';
}

/// A small JSON-ish encoder for the literal `context` payload (JS used
/// `JSON.stringify` here).
String _jsonLike(Object value) {
  if (value is String) return '"${value.replaceAll('"', r'\"')}"';
  if (value is num || value is bool) return _stringify(value);
  if (value is List) {
    final items = value.map((e) => e == null ? 'null' : _jsonLike(e));
    return '[${items.join(', ')}]';
  }
  if (value is Map) {
    final entries = value.entries
        .map((e) => '"${e.key}": ${e.value == null ? 'null' : _jsonLike(e.value!)}');
    return '{${entries.join(', ')}}';
  }
  return '$value';
}

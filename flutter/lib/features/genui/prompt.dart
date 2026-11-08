/// The OpenUI system prompt.
///
/// [buildOpenUIPrompt] turns the component library into a spec the model can
/// follow; the preamble and rules below add the two things the spec cannot
/// know — when to answer with an interface instead of prose, and how this app
/// wants the program wrapped.
///
/// The React app calls `generateSystemPrompt` from `@openuidev/react-lang`;
/// here the same spec is generated from the [ComponentSpec] declarations in
/// `library.dart`.
library;

import 'library.dart';

const String _preamble = r'''You are the assistant inside OpenAll, a local-first desktop chat app.

Answer ordinary questions in plain prose. When the answer is better shown as an
interface — a comparison, a table, a chart, a short form, or a procedure —
answer with an OpenUI Lang program instead.

An OpenUI Lang program is a list of statements, one per line:

    root = Stack([card])
    card = Card("Plans", [table])
    table = Table(["Plan", "Price"], [["Basic", "$5"], ["Pro", "$12"]])

Always begin with a "root = ..." statement naming a component from the library.
Component arguments are positional and follow the order of that component's
signature. Quote strings, use square brackets for lists, and refer to other
statements by name.''';

const List<String> _rules = [
  'Wrap the whole program in a ```openui-lang fenced block. Put any explanation before the fence, never inside it.',
  'Every program is a complete answer, not a patch: always include the `root = ...` statement and every statement it refers to, even when the answer continues an earlier one.',
  'Only use components from the library listed above. A component that is not in the library is dropped and the rest of the program still renders.',
  'Do not invent components, props, or functions. If the library has no component for what you need, answer in prose instead.',
  'Use Text for prose inside a program. Use Card to group a heading with content, Table for rows of values, Chart for a series of numbers, Form to ask the user for a few values, and Steps for an ordered procedure.',
  'Give a Form an action so the answer can continue: Form(fields, @ToAssistant("...")). Use a Button with @ToAssistant("...") when the user should be offered a choice of follow-up questions.',
  'Never emit HTML, JavaScript, or code fences other than ```openui-lang.',
];

String? _cached;

/// The system prompt that teaches the model the OpenUI Lang format.
String buildOpenUIPrompt() {
  return _cached ??= _build();
}

String _build() {
  final buffer = StringBuffer()
    ..writeln(_preamble)
    ..writeln()
    ..writeln('Component library: "${openallLibraryId}". '
        'Root component: ${openallRoot}.')
    ..writeln();

  openallComponentGroups.forEach((group, names) {
    buffer.writeln('## $group');
    for (final name in names) {
      final spec = componentSpecByName(name);
      if (spec == null) continue;
      buffer
        ..writeln('${spec.name}${spec.signature}')
        ..writeln('  ${spec.description}');
      for (final prop in spec.props) {
        buffer.writeln(
            '  - ${prop.name}${prop.isOptional ? ' (optional)' : ''}: ${prop.typeLabel}');
      }
      buffer.writeln();
    }
  });

  buffer.writeln('Rules:');
  for (var i = 0; i < _rules.length; i++) {
    buffer.writeln('${i + 1}. ${_rules[i]}');
  }
  return buffer.toString();
}

/// The shared OpenUI parser.
///
/// One parser instance for the whole app: it is built from the library's
/// component specs, so it validates against exactly the components the app
/// renders. Anything outside the allowlist is dropped with an
/// `unknown-component` error instead of reaching the widget tree.
///
/// This is the Dart counterpart of `createParser(openallLibrary.toJSONSchema())`
/// from `@openuidev/react-lang`, which is not available here, so the small
/// OpenUI Lang grammar is implemented directly: statements
/// (`identifier = expression`), positional component calls, string / number /
/// boolean literals, lists, JSON-ish objects, and action expressions
/// (`@ToAssistant("...")`).
library;

import 'actions.dart';
import 'library.dart';
import 'nodes.dart';
import 'schema.dart';

/// Severity of a parser error, mirroring `OpenUIError.severity` from
/// `@openuidev/react-lang`.
enum OpenUIErrorSeverity { error, warning }

/// One error produced while parsing a program. Never thrown — the renderer
/// shows a readable notice and drops the offending node.
class OpenUIParseError {
  const OpenUIParseError(
    this.message, {
    this.severity = OpenUIErrorSeverity.error,
    this.statementId,
  });

  /// Human-readable description, shown to the user.
  final String message;
  final OpenUIErrorSeverity severity;

  /// Statement the error came from, when it had one.
  final String? statementId;

  @override
  String toString() => message;
}

/// The outcome of parsing a program: the root node (when the program has a
/// usable entry) plus every error the parser collected along the way.
class ParseResult {
  const ParseResult({this.root, this.errors = const []});

  /// The rendered entry of the program, or `null` when it is not a program.
  final UiNode? root;
  final List<OpenUIParseError> errors;
}

/// The shared OpenUI parser.
class OpenUIParser {
  const OpenUIParser();

  /// Parse [source] into a [UiNode] tree.
  ///
  /// Never throws: malformed syntax and unknown components are reported as
  /// [OpenUIParseError]s, and the offending node is dropped.
  ParseResult parse(String source) {
    final errors = <OpenUIParseError>[];
    final statements = <String, _Expr>{};
    final reader = _Reader(source);

    while (true) {
      reader.skipWs();
      if (reader.atEnd) break;
      try {
        final name = reader.readIdentifier();
        reader.skipWs();
        reader.expectChar('=');
        statements[name] = reader.readExpr();
      } on _SyntaxError catch (e) {
        errors.add(OpenUIParseError(e.message));
        if (!reader.recoverToNextLine()) break;
      }
    }

    if (statements.isEmpty) return ParseResult(errors: errors);
    if (!statements.containsKey('root')) {
      errors.add(const OpenUIParseError('Program has no "root" statement.'));
      return ParseResult(errors: errors);
    }

    final builder = _NodeBuilder(statements, errors);
    final root = builder.build('root');
    return ParseResult(root: root, errors: errors);
  }
}

/// The shared parser instance for the whole app.
const OpenUIParser openallParser = OpenUIParser();

// ─────────────────────────────────────────────────────────────────────────────
// Expressions
// ─────────────────────────────────────────────────────────────────────────────

sealed class _Expr {}

class _StrExpr extends _Expr {
  _StrExpr(this.value);
  final String value;
}

class _NumExpr extends _Expr {
  _NumExpr(this.value);
  final num value;
}

class _BoolExpr extends _Expr {
  _BoolExpr(this.value);
  final bool value;
}

class _ListExpr extends _Expr {
  _ListExpr(this.items);
  final List<_Expr> items;
}

class _ObjExpr extends _Expr {
  _ObjExpr(this.fields);
  final Map<String, _Expr> fields;
}

class _CallExpr extends _Expr {
  _CallExpr(this.name, this.args);
  final String name;
  final List<_Expr> args;
}

class _ActionExpr extends _Expr {
  _ActionExpr(this.kind, this.args);
  final String kind;
  final List<_Expr> args;
}

class _RefExpr extends _Expr {
  _RefExpr(this.name);
  final String name;
}

class _SyntaxError implements Exception {
  _SyntaxError(this.message);
  final String message;
}

// ─────────────────────────────────────────────────────────────────────────────
// Reader
// ─────────────────────────────────────────────────────────────────────────────

const String _wsChars = ' \t\n\r\f\v';
final RegExp _numberRe = RegExp(r'-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?');

class _Reader {
  _Reader(this.source);

  final String source;
  int pos = 0;

  bool get atEnd => pos >= source.length;

  void skipWs() {
    while (!atEnd && _wsChars.contains(source[pos])) {
      pos++;
    }
  }

  void expectChar(String ch) {
    skipWs();
    if (atEnd || source[pos] != ch) {
      throw _SyntaxError('Expected "$ch".');
    }
    pos++;
  }

  /// Skip to the start of the next line after a syntax error, so one bad
  /// statement does not abort the rest of the program.
  bool recoverToNextLine() {
    final index = source.indexOf('\n', pos);
    if (index < 0) return false;
    pos = index + 1;
    return true;
  }

  String readIdentifier() {
    skipWs();
    final start = pos;
    while (!atEnd && _isIdentChar(source[pos], first: pos == start)) {
      pos++;
    }
    if (pos == start) {
      throw _SyntaxError(atEnd
          ? 'Unexpected end of program.'
          : 'Unexpected character "${source[pos]}".');
    }
    return source.substring(start, pos);
  }

  static bool _isIdentChar(String ch, {required bool first}) {
    final code = ch.codeUnitAt(0);
    final isLetter = (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
    final isDigit = code >= 0x30 && code <= 0x39;
    if (first) return isLetter || ch == '_' || ch == r'$';
    return isLetter || isDigit || ch == '_' || ch == r'$';
  }

  String readString() {
    expectChar('"');
    final buf = StringBuffer();
    while (true) {
      if (atEnd) throw _SyntaxError('Unterminated string.');
      final ch = source[pos];
      if (ch == '"') {
        pos++;
        return buf.toString();
      }
      if (ch == '\\') {
        pos++;
        if (atEnd) throw _SyntaxError('Unterminated string.');
        final esc = source[pos];
        switch (esc) {
          case 'n':
            buf.write('\n');
          case 't':
            buf.write('\t');
          case 'r':
            buf.write('\r');
          case '"':
            buf.write('"');
          case r'\':
            buf.write(r'\');
          default:
            buf.write(esc);
        }
        pos++;
        continue;
      }
      buf.write(ch);
      pos++;
    }
  }

  _Expr readExpr() {
    skipWs();
    if (atEnd) throw _SyntaxError('Unexpected end of program.');
    final ch = source[pos];

    if (ch == '"') return _StrExpr(readString());
    if (ch == '[') {
      pos++;
      return _ListExpr(_readArgs(']'));
    }
    if (ch == '{') return _readObject();
    if (ch == '@') return _readAction();
    if (ch == '(') {
      pos++;
      final inner = readExpr();
      expectChar(')');
      return inner;
    }

    final numMatch = _numberRe.matchAsPrefix(source, pos);
    if (numMatch != null && _isNumberStart(ch)) {
      pos = numMatch.end;
      final parsed = num.parse(numMatch.group(0)!);
      return _NumExpr(parsed);
    }

    final ident = readIdentifier();
    if (ident == 'true') return _BoolExpr(true);
    if (ident == 'false') return _BoolExpr(false);

    skipWs();
    if (!atEnd && source[pos] == '(') {
      pos++;
      return _CallExpr(ident, _readArgs(')'));
    }
    return _RefExpr(ident);
  }

  static bool _isNumberStart(String ch) {
    final code = ch.codeUnitAt(0);
    return (code >= 0x30 && code <= 0x39) || ch == '-';
  }

  /// Read `expr (',' expr)*` up to and including the [closer].
  List<_Expr> _readArgs(String closer) {
    final args = <_Expr>[];
    skipWs();
    if (!atEnd && source[pos] == closer) {
      pos++;
      return args;
    }
    while (true) {
      args.add(readExpr());
      skipWs();
      if (atEnd) throw _SyntaxError('Expected "$closer".');
      final ch = source[pos];
      if (ch == ',') {
        pos++;
        continue;
      }
      if (ch == closer) {
        pos++;
        return args;
      }
      throw _SyntaxError('Expected "," or "$closer".');
    }
  }

  _ObjExpr _readObject() {
    pos++;
    final fields = <String, _Expr>{};
    skipWs();
    if (!atEnd && source[pos] == '}') {
      pos++;
      return _ObjExpr(fields);
    }
    while (true) {
      final key = readString();
      expectChar(':');
      fields[key] = readExpr();
      skipWs();
      if (atEnd) throw _SyntaxError('Expected "}".');
      final ch = source[pos];
      if (ch == ',') {
        pos++;
        continue;
      }
      if (ch == '}') {
        pos++;
        return _ObjExpr(fields);
      }
      throw _SyntaxError('Expected "," or "}".');
    }
  }

  _ActionExpr _readAction() {
    pos++;
    final kind = readIdentifier();
    final args = <_Expr>[];
    skipWs();
    if (!atEnd && source[pos] == '(') {
      pos++;
      args.addAll(_readArgs(')'));
    }
    return _ActionExpr(kind, args);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Node building — positional args mapped onto props in spec order
// ─────────────────────────────────────────────────────────────────────────────

class _NodeBuilder {
  _NodeBuilder(this.statements, this.errors);

  final Map<String, _Expr> statements;
  final List<OpenUIParseError> errors;
  final Set<String> _resolving = <String>{};

  void _err(String message, [String? statementId]) {
    errors.add(OpenUIParseError(message, statementId: statementId));
  }

  /// Resolve a statement by name into a node, dropping it on failure.
  UiNode? build(String name) => buildRef(name, from: name);

  UiNode? buildRef(String name, {String? from}) {
    final expr = statements[name];
    if (expr == null) {
      _err('Unknown statement "$name".', from);
      return null;
    }
    if (_resolving.contains(name)) {
      _err('Circular reference to "$name".', from);
      return null;
    }
    _resolving.add(name);
    final node = buildExpr(expr, statementId: name);
    _resolving.remove(name);
    return node;
  }

  UiNode? buildExpr(_Expr expr, {String? statementId}) {
    if (expr is _RefExpr) {
      return buildRef(expr.name, from: statementId);
    }
    if (expr is _CallExpr) return _buildCall(expr, statementId);
    _err('Expected a component call.', statementId);
    return null;
  }

  UiNode? _buildCall(_CallExpr call, String? statementId) {
    final spec = componentSpecByName(call.name);
    if (spec == null) {
      _err('Unknown component "${call.name}".', statementId);
      return null;
    }
    if (call.args.length > spec.props.length) {
      _err(
        '${call.name} takes at most ${spec.props.length} arguments; got ${call.args.length}.',
        statementId,
      );
    }

    final props = <String, Object?>{};
    for (var i = 0; i < call.args.length && i < spec.props.length; i++) {
      final propSpec = spec.props[i];
      final value = _convert(call.args[i], spec, propSpec, statementId);
      if (value == null) {
        if (propSpec.required) {
          _err('${call.name}.${propSpec.name} is required.', statementId);
          return null;
        }
        continue;
      }
      props[propSpec.name] = value;
    }
    for (final p in spec.props) {
      if (p.required && !props.containsKey(p.name)) {
        _err('${call.name}.${p.name} is required.', statementId);
        return null;
      }
    }
    return _makeNode(spec, props, statementId);
  }

  /// Coerce one positional argument onto its prop, reporting type errors.
  /// Returns `null` for "absent" (an optional prop keeps its default).
  Object? _convert(
    _Expr expr,
    ComponentSpec spec,
    PropSpec prop,
    String? statementId,
  ) {
    String? typeErr(String expected) {
      _err('${spec.name}.${prop.name} must be $expected.', statementId);
      return null;
    }

    switch (prop.kind) {
      case PropKind.string:
      case PropKind.text:
        if (expr is _StrExpr) return expr.value;
        return typeErr('a string');
      case PropKind.number:
        if (expr is _NumExpr) return expr.value;
        return typeErr('a number');
      case PropKind.boolean:
        if (expr is _BoolExpr) return expr.value;
        return typeErr('a boolean');
      case PropKind.stringList:
        if (expr is! _ListExpr) return typeErr('a list of strings');
        final out = <String>[];
        for (final item in expr.items) {
          if (item is! _StrExpr) return typeErr('a list of strings');
          out.add(item.value);
        }
        return out;
      case PropKind.numberList:
        if (expr is! _ListExpr) return typeErr('a list of numbers');
        final out = <double>[];
        for (final item in expr.items) {
          if (item is! _NumExpr) return typeErr('a list of numbers');
          out.add(item.value.toDouble());
        }
        return out;
      case PropKind.enumValues:
        if (expr is! _StrExpr) return typeErr('a string');
        final allowed = prop.enumValues ?? const <String>[];
        if (!allowed.contains(expr.value)) {
          _err(
            '${spec.name}.${prop.name} must be one of ${allowed.map((v) => '"$v"').join(', ')}.',
            statementId,
          );
          return null;
        }
        return expr.value;
      case PropKind.cellTable:
        if (expr is! _ListExpr) return typeErr('a list of rows');
        final rows = <List<Object>>[];
        for (final rowExpr in expr.items) {
          if (rowExpr is! _ListExpr) return typeErr('a list of rows');
          final row = <Object>[];
          for (final cell in rowExpr.items) {
            if (cell is _StrExpr) {
              row.add(cell.value);
            } else if (cell is _NumExpr) {
              row.add(cell.value);
            } else {
              return typeErr('a row of strings or numbers');
            }
          }
          rows.add(row);
        }
        return rows;
      case PropKind.formFields:
        if (expr is! _ListExpr) return typeErr('a list of field objects');
        final fields = <FormFieldData>[];
        for (final fieldExpr in expr.items) {
          final field = _parseFormField(fieldExpr, spec.name, statementId);
          if (field == null) return null; // zod: one bad field fails the Form
          fields.add(field);
        }
        return fields;
      case PropKind.stepItems:
        if (expr is! _ListExpr) return typeErr('a list of step objects');
        final items = <StepItemData>[];
        for (final itemExpr in expr.items) {
          final item = _parseStepItem(itemExpr, spec.name, statementId);
          if (item == null) return null; // zod: one bad step fails Steps
          items.add(item);
        }
        return items;
      case PropKind.action:
        if (expr is! _ActionExpr) {
          return typeErr('an action expression, e.g. @ToAssistant("...")');
        }
        return _parseAction(expr, spec.name, statementId);
      case PropKind.leafChildren:
      case PropKind.stackChildren:
        if (expr is! _ListExpr) return typeErr('a list of components');
        final children = <UiNode>[];
        for (final childExpr in expr.items) {
          final child = buildExpr(childExpr, statementId: statementId);
          if (child == null) continue; // the child is dropped, rest renders
          final allowed = prop.kind == PropKind.stackChildren
              ? (child is! StackNode)
              : isLeafNode(child);
          if (!allowed) {
            _err(
              'Component "${child.typeName}" cannot be used inside ${spec.name}.',
              statementId,
            );
            continue;
          }
          children.add(child);
        }
        return children;
    }
  }

  OpenUIAction? _parseAction(
    _ActionExpr expr,
    String component,
    String? statementId,
  ) {
    final kind = switch (expr.kind) {
      'ToAssistant' => OpenUIActionKind.toAssistant,
      'OpenUrl' => OpenUIActionKind.openUrl,
      _ => null,
    };
    if (kind == null) {
      _err('@${expr.kind} is not a known action in $component.', statementId);
      return null;
    }
    if (expr.args.isEmpty || expr.args.first is! _StrExpr) {
      _err('$component action @${expr.kind} needs a message string.', statementId);
      return null;
    }
    final message = (expr.args.first as _StrExpr).value;
    Map<String, Object?>? params;
    if (expr.args.length > 1 && expr.args[1] is _ObjExpr) {
      params = _literalFields((expr.args[1] as _ObjExpr).fields);
    }
    return OpenUIAction(kind: kind, message: message, params: params);
  }

  Map<String, Object?>? _literalFields(Map<String, _Expr> fields) {
    final out = <String, Object?>{};
    fields.forEach((key, value) {
      Object? literal;
      if (value is _StrExpr) {
        literal = value.value;
      } else if (value is _NumExpr) {
        literal = value.value;
      } else if (value is _BoolExpr) {
        literal = value.value;
      } else if (value is _ListExpr) {
        literal = [
          for (final item in value.items)
            if (item is _StrExpr)
              item.value
            else if (item is _NumExpr)
              item.value
            else if (item is _BoolExpr)
              item.value,
        ];
      }
      out[key] = literal;
    });
    return out;
  }

  FormFieldData? _parseFormField(
    _Expr expr,
    String component,
    String? statementId,
  ) {
    if (expr is! _ObjExpr) {
      _err('$component fields must be objects.', statementId);
      return null;
    }
    final f = expr.fields;

    String? str(String key, {required bool required}) {
      final value = f[key];
      if (value == null) {
        if (required) {
          _err('$component field is missing "$key".', statementId);
        }
        return null;
      }
      if (value is! _StrExpr) {
        _err('$component field "$key" must be a string.', statementId);
        return null;
      }
      return value.value;
    }

    final name = str('name', required: true);
    if (name == null || name.isEmpty) return null;
    final label = str('label', required: true);
    if (label == null || label.isEmpty) return null;
    final typeRaw = str('type', required: true);
    if (typeRaw == null) return null;
    final type = switch (typeRaw) {
      'text' => FieldType.text,
      'textarea' => FieldType.textarea,
      'number' => FieldType.number,
      'select' => FieldType.select,
      'checkbox' => FieldType.checkbox,
      _ => null,
    };
    if (type == null) {
      _err(
        '$component field type must be one of "text", "textarea", "number", "select", "checkbox".',
        statementId,
      );
      return null;
    }

    final placeholder = str('placeholder', required: false);
    bool requiredFlag = false;
    final requiredExpr = f['required'];
    if (requiredExpr is _BoolExpr) requiredFlag = requiredExpr.value;

    List<String>? options;
    final optionsExpr = f['options'];
    if (optionsExpr is _ListExpr) {
      options = <String>[];
      for (final option in optionsExpr.items) {
        if (option is! _StrExpr) {
          _err('$component field options must be strings.', statementId);
          return null;
        }
        options.add(option.value);
      }
    }

    double? min, max;
    final minExpr = f['min'];
    if (minExpr is _NumExpr) min = minExpr.value.toDouble();
    final maxExpr = f['max'];
    if (maxExpr is _NumExpr) max = maxExpr.value.toDouble();

    return FormFieldData(
      name: name,
      label: label,
      type: type,
      placeholder: placeholder,
      required: requiredFlag,
      options: options,
      min: min,
      max: max,
    );
  }

  StepItemData? _parseStepItem(
    _Expr expr,
    String component,
    String? statementId,
  ) {
    if (expr is! _ObjExpr) {
      _err('$component items must be objects.', statementId);
      return null;
    }
    final f = expr.fields;
    final titleExpr = f['title'];
    if (titleExpr is! _StrExpr || titleExpr.value.isEmpty) {
      _err('$component step needs a "title".', statementId);
      return null;
    }
    String? description;
    final descExpr = f['description'];
    if (descExpr is _StrExpr) description = descExpr.value;
    StepStatus? status;
    final statusExpr = f['status'];
    if (statusExpr is _StrExpr) {
      status = switch (statusExpr.value) {
        'pending' => StepStatus.pending,
        'active' => StepStatus.active,
        'done' => StepStatus.done,
        _ => null,
      };
      if (status == null) {
        _err(
          '$component step status must be one of "pending", "active", "done".',
          statementId,
        );
        return null;
      }
    }
    return StepItemData(
      title: titleExpr.value,
      description: description,
      status: status,
    );
  }

  UiNode _makeNode(
    ComponentSpec spec,
    Map<String, Object?> props,
    String? statementId,
  ) {
    T opt<T>(String key, T fallback) {
      final value = props[key];
      return value is T ? value : fallback;
    }

    switch (spec.name) {
      case 'Stack':
        return StackNode(
          children: (props['children'] as List<UiNode>? ?? const [])
              .take(Limits.maxChildren)
              .toList(),
          direction: switch (opt<String>('direction', 'column')) {
            'row' => StackDirection.row,
            _ => StackDirection.column,
          },
          gap: switch (opt<String>('gap', 'md')) {
            'none' => Gap.none,
            'sm' => Gap.sm,
            'lg' => Gap.lg,
            _ => Gap.md,
          },
          statementId: statementId,
        );
      case 'Card':
        return CardNode(
          title: props['title']! as String,
          children: (props['children'] as List<UiNode>? ?? const [])
              .take(Limits.maxChildren)
              .toList(),
          description: opt<String?>('description', null),
          statementId: statementId,
        );
      case 'Text':
        final raw = props['text']! as String;
        return TextNode(
          // Trim to the schema bound: an oversized block is never rendered whole.
          text: raw.length > Limits.maxTextLength
              ? raw.substring(0, Limits.maxTextLength)
              : raw,
          size: switch (opt<String>('size', 'default')) {
            'small' => TextSize.small,
            'large' => TextSize.large,
            _ => TextSize.normal,
          },
          statementId: statementId,
        );
      case 'Table':
        final columns = (props['columns'] as List<String>? ?? const [])
            .take(Limits.maxTableColumns)
            .toList();
        final rows = (props['rows'] as List<List<Object>>? ?? const [])
            .take(Limits.maxTableRows)
            .map((row) => row.take(Limits.maxTableCells).toList())
            .toList();
        return TableNode(
          columns: columns,
          rows: rows,
          caption: opt<String?>('caption', null),
          statementId: statementId,
        );
      case 'Chart':
        return ChartNode(
          chartType: switch (opt<String>('chartType', 'bar')) {
            'line' => ChartType.line,
            'area' => ChartType.area,
            _ => ChartType.bar,
          },
          labels: props['labels'] as List<String>? ?? const [],
          values: props['values'] as List<double>? ?? const [],
          title: opt<String?>('title', null),
          statementId: statementId,
        );
      case 'Form':
        return FormNode(
          fields: (props['fields'] as List<FormFieldData>? ?? const [])
              .take(Limits.maxFormFields)
              .toList(),
          action: props['action'] as OpenUIAction?,
          title: opt<String?>('title', null),
          submitLabel: opt<String?>('submitLabel', null),
          statementId: statementId,
        );
      case 'Steps':
        return StepsNode(
          items: (props['items'] as List<StepItemData>? ?? const [])
              .take(Limits.maxSteps)
              .toList(),
          statementId: statementId,
        );
      case 'Button':
        return ButtonNode(
          label: props['label']! as String,
          action: props['action'] as OpenUIAction?,
          variant: switch (opt<String>('variant', 'primary')) {
            'secondary' => ButtonVariant.secondary,
            'ghost' => ButtonVariant.ghost,
            _ => ButtonVariant.primary,
          },
          statementId: statementId,
        );
      default:
        // Unreachable: the allowlist lookup above already rejected it.
        return TextNode(
          text: 'Component ${spec.name} is not renderable.',
          statementId: statementId,
        );
    }
  }
}

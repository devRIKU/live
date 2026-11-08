/// Splitting an assistant message into prose and OpenUI Lang programs.
///
/// A chat answer can be plain prose, a program, or prose around a program.
/// The decision is made with the shared parser rather than with a regex, so
/// "is this a program?" is answered the same way the runtime answers it.
library;

import 'parser.dart';

/// One rendered part of an assistant message: prose or a program.
sealed class MessagePart {
  const MessagePart();
}

/// Plain markdown prose.
class ProsePart extends MessagePart {
  const ProsePart(this.text);
  final String text;
}

/// The raw text of an OpenUI Lang program.
class ProgramPart extends MessagePart {
  const ProgramPart(this.text);
  final String text;
}

/// Fence languages the model may use for an OpenUI Lang program.
const Set<String> programLanguages = {'openui-lang', 'openui', 'oui'};

/// A statement line: `identifier = expression`.
final RegExp _statementRe =
    RegExp(r'^\s*[A-Za-z_$][\w$]*\s*=\s*[^=]', multiLine: true);

/// A fenced block. The closing fence may be missing while the answer streams.
final RegExp _fenceRe = RegExp(r'```([^\n`]*)\n([\s\S]*?)(?:```|$)');

/// True when the text parses as an OpenUI Lang program with a usable entry.
bool isProgram(String text) {
  if (text.trim().isEmpty) return false;
  try {
    return openallParser.parse(text).root != null;
  } catch (_) {
    return false;
  }
}

/// Split an unfenced message into the prose that precedes the program and the
/// program itself. Returns an empty list when the message is not a program.
List<MessagePart> _splitUnfenced(String content) {
  final lines = content.split('\n');
  var index = -1;
  for (var i = 0; i < lines.length; i++) {
    if (_statementRe.hasMatch(lines[i])) {
      index = i;
      break;
    }
  }
  if (index < 0) return const [];

  final prose = lines.sublist(0, index).join('\n');
  final program = lines.sublist(index).join('\n');

  if (isProgram(program)) {
    return prose.trim().isNotEmpty
        ? [ProsePart(prose), ProgramPart(program)]
        : [ProgramPart(program)];
  }

  // The tail is not a program — the whole message might still be one.
  return isProgram(content) ? [ProgramPart(content)] : const [];
}

/// Split an assistant message into the parts that should be rendered.
///
/// Fenced blocks tagged `openui-lang` (or `openui` / `oui`) are programs. An
/// untagged fence is a program only when its body parses as one; otherwise it
/// stays in the prose and is rendered as an ordinary markdown code block.
List<MessagePart> splitMessage(String content) {
  if (content.isEmpty) return const [];

  final parts = <MessagePart>[];
  var last = 0;
  var foundProgramFence = false;

  for (final match in _fenceRe.allMatches(content)) {
    final language = (match.group(1) ?? '').trim().toLowerCase();
    final body = match.group(2) ?? '';
    final isProgramFence =
        programLanguages.contains(language) || (language.isEmpty && isProgram(body));
    if (!isProgramFence) continue;

    foundProgramFence = true;
    if (match.start > last) {
      parts.add(ProsePart(content.substring(last, match.start)));
    }
    parts.add(ProgramPart(body));
    last = match.end;
  }

  if (foundProgramFence) {
    if (last < content.length) {
      parts.add(ProsePart(content.substring(last)));
    }
    return parts;
  }

  final unfenced = _splitUnfenced(content);
  if (unfenced.isNotEmpty) return unfenced;
  return [ProsePart(content)];
}

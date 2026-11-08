import 'dart:convert';
import 'dart:math';

import '../../models/models.dart';

/// Tool call detector — parses `{{TOOL_CALL}}` blocks from model responses
/// (port of `src/tools/toolCallDetector.ts`).
///
/// Format:
/// ```
/// {{TOOL_CALL}}
/// {"name": "mcp:test:echo", "args": {"message": "hi"}, "description": "…", "targetPath": null}
/// {{/TOOL_CALL}}
/// ```
///
/// Returns all tool calls found in the text, plus the text with the blocks
/// stripped (so the remaining text can be shown to the user).
///
/// Dart note: JS `RegExp` instances are stateful (`lastIndex` with the `g`
/// flag); Dart's [RegExp] is stateless, so `allMatches` is used and no
/// `lastIndex` reset is needed.

const String _toolCallPattern =
    r'\{\{TOOL_CALL\}\}\s*\n([\s\S]*?)\n\{\{\/TOOL_CALL\}\}';

final RegExp _toolCallRe = RegExp(_toolCallPattern);

/// One detected tool call plus the raw block it came from.
class ParsedToolCall {
  final ToolCall call;
  final String raw;
  const ParsedToolCall({required this.call, required this.raw});
}

/// Result of [detectToolCalls].
class ToolCallDetection {
  final List<ParsedToolCall> calls;
  final String cleanText;
  const ToolCallDetection({required this.calls, required this.cleanText});
}

const String _base36 = '0123456789abcdefghijklmnopqrstuvwxyz';

/// `tc_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`
/// equivalent.
String _newToolCallId() {
  final now = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final random = Random.secure();
  final suffix =
      List.generate(6, (_) => _base36[random.nextInt(36)]).join();
  return 'tc_${now}_$suffix';
}

/// Parse every `{{TOOL_CALL}}` block in [text].
ToolCallDetection detectToolCalls(String text) {
  final calls = <ParsedToolCall>[];
  final clean = StringBuffer();
  var lastIndex = 0;

  for (final m in _toolCallRe.allMatches(text)) {
    clean.write(text.substring(lastIndex, m.start));
    final block = m.group(0)!;
    final inner = m.group(1)!.trim();
    lastIndex = m.end;

    try {
      final obj = jsonDecode(inner);
      if (obj is! Map) continue; // not an object — skip this block
      final map = Map<String, dynamic>.from(obj);
      final name = map['name'];
      if (name is String && name.isNotEmpty) {
        final args = map['args'];
        final toolArgs = map['toolArgs'];
        final mcpArgs = map['mcpArgs'];
        final parsed = ToolCall(
          id: _newToolCallId(),
          name: name,
          args: args is Map ? Map<String, dynamic>.from(args) : const {},
          description: map['description'] as String? ?? 'Call $name',
          targetPath: map['targetPath'] as String?,
          command: map['command'] as String?,
          mcpArgs: mcpArgs is List ? mcpArgs.map((e) => '$e').toList() : null,
          workingDir: map['workingDir'] as String?,
          toolName: map['toolName'] as String?,
          toolArgs: toolArgs is Map
              ? Map<String, dynamic>.from(toolArgs)
              : null,
        );
        calls.add(ParsedToolCall(call: parsed, raw: block));
      }
    } catch (_) {
      // Invalid JSON — skip this block (it is still stripped from `clean`)
    }
  }
  clean.write(text.substring(lastIndex));
  return ToolCallDetection(calls: calls, cleanText: clean.toString().trim());
}

/// Whether [text] contains at least one tool-call block.
bool hasToolCall(String text) => _toolCallRe.firstMatch(text) != null;

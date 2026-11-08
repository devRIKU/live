/// Attachments — images and text files that travel with a user turn.
/// Port of `src/chat/attachments.ts` for the desktop runtime (dart:io files).
///
/// Images become OpenAI-style `image_url` content parts (data URLs, so the
/// provider fetches nothing). Text files are inlined into the prompt with a
/// fenced block, which every provider can read, including ones without vision.
///
/// Limits are enforced before a byte is read: four files, 8 MB each, 12 MB
/// total, and 60k characters of inlined text.
library;

import 'dart:io';

import 'chat_transport.dart';
import '../../models/models.dart' show MessageAttachment;

// ─── Limits & classification ────────────────────────────────────────────────

class AttachmentLimits {
  static const maxFiles = 4;
  static const maxFileBytes = 8 * 1024 * 1024;
  static const maxTotalBytes = 12 * 1024 * 1024;
  static const maxTextChars = 60000;
}

class FileLike {
  final String name;
  final String type;
  final int size;
  final String path;
  const FileLike({required this.name, required this.type, required this.size, required this.path});
}

class REJECTED {
  final String name;
  final String reason;
  const REJECTED(this.name, this.reason);
}

class SelectionResult {
  final List<FileLike> accepted;
  final List<REJECTED> rejected;
  const SelectionResult({required this.accepted, required this.rejected});
}

const _imageTypes = {'image/png', 'image/jpeg', 'image/webp', 'image/gif'};
const _textExtensions = {
  'txt', 'md', 'markdown', 'csv', 'tsv', 'json', 'yaml', 'yml', 'toml',
  'ts', 'tsx', 'js', 'jsx', 'py', 'rb', 'go', 'rs', 'java', 'c', 'h', 'cpp',
  'css', 'html', 'xml', 'svg', 'sql', 'sh', 'log',
};

/// 'image' | 'text' | 'reject'
typedef FileKind = String;

String extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
}

({FileKind kind, String? reason}) classifyFile(FileLike file) {
  if (_imageTypes.contains(file.type)) return (kind: 'image', reason: null);
  if (file.type.startsWith('text/') ||
      file.type == 'application/json' ||
      file.type == 'application/xml') {
    return (kind: 'text', reason: null);
  }
  if (file.type.isEmpty || file.type == 'application/octet-stream') {
    // Windows often leaves type empty for source files; fall back to the name.
    if (_textExtensions.contains(extensionOf(file.name))) {
      return (kind: 'text', reason: null);
    }
  }
  if (_textExtensions.contains(extensionOf(file.name))) {
    return (kind: 'text', reason: null);
  }
  return (
    kind: 'reject',
    reason: 'Only images (PNG, JPEG, WebP, GIF) and text files are supported.',
  );
}

/// Apply count, size and vision limits to a new selection.
/// `allowImages` is false when the active model is text-only.
SelectionResult selectAttachments(
  Iterable<MessageAttachment> existing,
  Iterable<FileLike> files, {
  required bool allowImages,
}) {
  final accepted = <FileLike>[];
  final rejected = <REJECTED>[];

  var count = existing.length;
  var total = existing.fold(0, (sum, a) => sum + a.size);

  for (final file in files) {
    if (count >= AttachmentLimits.maxFiles) {
      rejected.add(REJECTED(
        file.name,
        'At most ${AttachmentLimits.maxFiles} files per message.',
      ));
      continue;
    }
    final (:kind, :reason) = classifyFile(file);
    if (kind == 'reject') {
      rejected.add(REJECTED(file.name, reason ?? 'Unsupported file.'));
      continue;
    }
    if (kind == 'image' && !allowImages) {
      rejected.add(REJECTED(
        file.name,
        'The selected model is text-only. Switch to a vision model to attach images.',
      ));
      continue;
    }
    if (file.size > AttachmentLimits.maxFileBytes) {
      rejected.add(REJECTED(
        file.name,
        'Each file must be 8 MB or smaller.',
      ));
      continue;
    }
    if (total + file.size > AttachmentLimits.maxTotalBytes) {
      rejected.add(REJECTED(
        file.name,
        'Attachments exceed the 12 MB total limit.',
      ));
      continue;
    }
    accepted.add(file);
    count += 1;
    total += file.size;
  }

  return SelectionResult(accepted: accepted, rejected: rejected);
}

// ─── Reading ────────────────────────────────────────────────────────────────

String _newId() =>
    'att_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '_${DateTime.now().millisecondsSinceEpoch.toRadixString(36).substring(0, 2)}';

/// Read a desktop file into an attachment, applying the text-length cap.
Future<MessageAttachment> readAttachment(FileLike file, FileKind kind) async {
  final decodedKind = kind == 'image' ? 'image' : 'text';

  if (decodedKind == 'image') {
    final bytes = await File(file.path).readAsBytes();
    final dataUrl = 'data:${file.type.isEmpty ? 'image/png' : file.type}'
        ';base64,${_base64Url(bytes)}';
    return MessageAttachment(
      id: _newId(),
      kind: 'image',
      name: file.name,
      mime: file.type.isEmpty ? 'image/png' : file.type,
      size: file.size,
      dataUrl: dataUrl,
    );
  }

  final raw = await File(file.path).readAsString();
  final text = raw.length > AttachmentLimits.maxTextChars
      ? '${raw.substring(0, AttachmentLimits.maxTextChars)}\n\n'
          '[…truncated at ${AttachmentLimits.maxTextChars} characters]'
      : raw;
  return MessageAttachment(
    id: _newId(),
    kind: 'text',
    name: file.name,
    mime: file.type.isEmpty ? 'text/plain' : file.type,
    size: file.size,
    text: text,
  );
}

/// Base64 without the RFC-safe line breaks (OpenAI data URLs expect plain).
String _base64Url(List<int> bytes) {
  const digits = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  final out = StringBuffer();
  var i = 0;
  final len = bytes.length;
  while (i < len) {
    final b1 = bytes[i++];
    final b2 = i < len ? bytes[i++] : -1;
    final b3 = i < len ? bytes[i++] : -1;
    out.write(digits[b1 >> 2]);
    out.write(digits[((b1 & 3) << 4) | (b2 == -1 ? 0 : b2 >> 4)]);
    if (b2 == -1) {
      out.write('==');
      break;
    }
    out.write(digits[((b2 & 15) << 2) | (b3 == -1 ? 0 : b3 >> 6)]);
    if (b3 == -1) {
      out.write('=');
      break;
    }
    out.write(digits[b3 & 63]);
  }
  return out.toString();
}

// ─── Wire conversion ────────────────────────────────────────────────────────

/// Fence language for an inlined text file.
String fenceFor(String name) {
  const map = {
    'ts': 'ts', 'tsx': 'tsx', 'js': 'js', 'jsx': 'jsx', 'py': 'python',
    'rb': 'ruby', 'rs': 'rust', 'sh': 'bash', 'yml': 'yaml', 'md': 'markdown',
  };
  final ext = extensionOf(name);
  return map[ext] ?? ext;
}

/// The text block appended to the prompt for every text attachment.
String inlineTextAttachments(List<MessageAttachment> attachments) {
  final textFiles = attachments.where((a) => a.kind == 'text' && a.text != null);
  if (textFiles.isEmpty) return '';
  return textFiles
      .map((a) =>
          '\n\n[Attached file: ${a.name}]\n\`\`\`${fenceFor(a.name)}\n${a.text}\n\`\`\`')
      .join();
}

/// Build wire content for a turn. Returns a plain string when there are no
/// images, so text-only providers receive exactly the shape they expect.
ChatContent toWireContent(
  String text, [
  List<MessageAttachment> attachments = const [],
]) {
  final images = attachments.where((a) => a.kind == 'image' && a.dataUrl != null);
  final withText = '$text${inlineTextAttachments(attachments)}'.trim();

  if (images.isEmpty) return ChatContent.string(withText);

  final parts = <ChatContentPart>[];
  if (withText.isNotEmpty) parts.add(ChatContentPart.text(withText));
  for (final image in images) {
    parts.add(ChatContentPart.imageUrl(image.dataUrl!));
  }
  return ChatContent.parts(parts);
}

/// Total characters contributed by text attachments (for the token meter).
int attachmentTextChars([List<MessageAttachment> attachments = const []]) =>
    attachments.fold(
      0,
      (sum, a) => sum + (a.kind == 'text' ? (a.text?.length ?? 0) : 0),
    );
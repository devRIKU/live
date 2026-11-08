/// Artifact detector — parses markdown fenced code blocks with a supported
/// language tag (html, react, svg, markdown) into [Artifact] objects.
///
/// Supports optional metadata in the info string, e.g.
///   ```html title="Tip Calculator"
/// Size cap: 1 MB per artifact. Oversized blocks are dropped.
/// Port of `src/canvas/artifactDetector.ts` for the desktop runtime.
library;

import 'dart:math';

/// What the canvas pane knows how to render.
enum ArtifactType { html, react, svg, markdown }

/// One detected artifact: a fenced code block worth opening in the pane.
class Artifact {
  final String id;
  final ArtifactType type;
  final String title;
  final String code;
  const Artifact({
    required this.id,
    required this.type,
    required this.title,
    required this.code,
  });
}

const String _base36 = '0123456789abcdefghijklmnopqrstuvwxyz';

/// `art_${Date.now().toString(36)}_${random.toString(36).slice(2, 8)}` shape.
String newArtifactId() {
  final now = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final random = Random.secure();
  final suffix = List.generate(6, (_) => _base36[random.nextInt(36)]).join();
  return 'art_${now}_$suffix';
}

const Set<String> _supportedLangs = {
  'html',
  'react',
  'jsx',
  'svg',
  'markdown',
  'md',
};

const int _maxBytes = 1024 * 1024; // 1 MB

/// Normalize a fence language to an artifact type, or `null` when the
/// language has no canvas renderer.
ArtifactType? artifactTypeForLang(String lang) {
  switch (lang) {
    case 'html':
      return ArtifactType.html;
    case 'react':
    case 'jsx':
      return ArtifactType.react;
    case 'svg':
      return ArtifactType.svg;
    case 'markdown':
    case 'md':
      return ArtifactType.markdown;
    default:
      return null;
  }
}

String _parseTitle(String info, ArtifactType type) {
  final dq = RegExp(r'title\s*=\s*"([^"]*)"').firstMatch(info);
  if (dq != null) return dq.group(1)!;
  final sq = RegExp(r"title\s*=\s*'([^']*)'").firstMatch(info);
  if (sq != null) return sq.group(1)!;
  // fallback: first non-language token
  final tokens =
      info.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (tokens.length > 1) return tokens.sublist(1).join(' ');
  final name = type.name;
  return '${name[0].toUpperCase()}${name.substring(1)} artifact';
}

/// Parse every supported fenced block in [text]. [_supportedLangs] keeps the
/// language allowlist explicit, mirroring the TS `SUPPORTED` record.
List<Artifact> detectArtifacts(String text) {
  final out = <Artifact>[];
  final regex = RegExp(r'```([A-Za-z0-9_-]+)([^\n]*)\n([\s\S]*?)```');
  for (final m in regex.allMatches(text)) {
    final lang = m.group(1)!.toLowerCase();
    if (!_supportedLangs.contains(lang)) continue;
    final info = m.group(2) ?? '';
    final code = m.group(3)!.replaceAll(RegExp(r'\n$'), '');
    final type = artifactTypeForLang(lang);
    if (type == null) continue;
    if (code.isEmpty) continue;
    if (code.length > _maxBytes) continue; // size cap
    out.add(Artifact(
      id: newArtifactId(),
      type: type,
      title: _parseTitle(info, type),
      code: code,
    ));
  }
  return out;
}

bool hasArtifact(String text) => detectArtifacts(text).isNotEmpty;

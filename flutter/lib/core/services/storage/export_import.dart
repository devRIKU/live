/// Export / Import utility for chat history and facts.
/// Port of `src/db/exportImport.ts`.
///
/// Validates format on import; strips any detected secrets. On the web the
/// original downloaded a Blob — here `exportData` writes to a file path and
/// returns it so the caller can show it in a toast or open a save dialog.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/models.dart';
import '../storage_adapter.dart';

/// The suggested file name: `openall-export-YYYY-MM-DD.json`.
String exportFileName({DateTime? now}) {
  final date = (now ?? DateTime.now()).toUtc();
  final mm = date.month.toString().padLeft(2, '0');
  final dd = date.day.toString().padLeft(2, '0');
  return 'openall-export-${date.year}-$mm-$dd.json';
}

/// Serialize the whole store to pretty-printed JSON.
String encodeExport(ExportPayload payload) =>
    const JsonEncoder.withIndent('  ').convert(payload.toJson());

/// Export everything and write it to `directory` (defaults to the app
/// documents directory). Returns the path of the written file.
Future<String> exportData(
  StorageAdapter storage, {
  Directory? directory,
}) async {
  final payload = await storage.exportAll();
  final dir = directory ?? await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, exportFileName()));
  await file.writeAsString(encodeExport(payload));
  return file.path;
}

/// Import from a JSON file. Throws with a user-facing message when the file
/// is not a valid, secret-free v1 export.
Future<ImportResult> importData(
  StorageAdapter storage,
  File file, {
  Future<ImportResult> Function(ExportPayload)? importAll,
}) async {
  final text = await file.readAsString();

  // Basic secret scan on the raw text.
  if (containsSecrets(text)) {
    throw Exception(
        'Import rejected: the file appears to contain API keys or secrets.');
  }

  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    throw Exception('Import failed: invalid JSON file.');
  }
  if (decoded is! Map) {
    throw Exception('Import failed: invalid JSON file.');
  }
  final map = Map<String, dynamic>.from(decoded);

  final ExportPayload data;
  try {
    data = ExportPayload.fromJson(map);
  } catch (_) {
    throw Exception('Import failed: invalid export file structure.');
  }

  // Validate the raw JSON's version field (the model's `version` is a static
  // const, so read it off the decoded map like the TS original did).
  final rawVersion = map['version'];
  if (rawVersion != ExportPayload.version) {
    throw Exception(
        'Unsupported export version: $rawVersion. Expected version 1.');
  }

  final hasThreads = map['threads'] is List;
  final hasFacts = map['facts'] is List;
  if (!hasThreads && !hasFacts) {
    throw Exception('Import failed: no threads or facts found in the file.');
  }

  return await (importAll ?? storage.importAll)(data);
}

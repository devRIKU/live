import '../models/models.dart';

/// Generic async interface for persisting threads, messages, settings, facts.
/// Security rule: methods MUST reject any payload containing raw secret keys.
abstract class StorageAdapter {
  // Threads
  Future<Thread?> getThread(String id);
  Future<void> saveThread(Thread thread);
  Future<List<ThreadSummary>> listThreads();
  Future<void> deleteThread(String id);

  // Settings (key-value)
  Future<T?> getSetting<T>(String key);
  Future<void> setSetting<T>(String key, T value);

  // Facts (memory)
  Future<Fact?> getFact(String id);
  Future<void> saveFact(Fact fact);
  Future<List<Fact>> listFacts();
  Future<void> deleteFact(String id);
  Future<void> clearFacts();

  // Bulk export / import
  Future<ExportPayload> exportAll();
  Future<ImportResult> importAll(ExportPayload data);
}

class ImportResult {
  final int imported;
  final int skipped;
  const ImportResult({required this.imported, required this.skipped});
}
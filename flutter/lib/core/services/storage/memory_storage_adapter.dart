/// MemoryStorageAdapter — in-memory implementation of `StorageAdapter`.
///
/// Port of `src/db/indexedDbAdapter.ts`. IndexedDB is unavailable in a
/// Flutter desktop/web runtime, and `sqflite` needs a plugin per platform,
/// so this adapter keeps parity semantics for tests and as a web fallback:
/// same ordering, same secret filtering, same import/skip behaviour.
library;

import 'dart:convert';

import '../../models/models.dart';
import '../storage_adapter.dart';

class MemoryStorageAdapter implements StorageAdapter {
  final Map<String, Thread> _threads = {};
  final Map<String, Fact> _facts = {};
  final Map<String, Object?> _settings = {};

  // ── Threads ──────────────────────────────────────────────────────────────

  @override
  Future<Thread?> getThread(String id) async => _threads[id];

  @override
  Future<void> saveThread(Thread thread) async {
    assertNoSecrets(thread.toJson(), 'thread');
    _threads[thread.id] = thread;
  }

  @override
  Future<List<ThreadSummary>> listThreads() async {
    final summaries = _threads.values
        .map((t) => ThreadSummary(
              id: t.id,
              title: t.title,
              createdAt: t.createdAt,
              updatedAt: t.updatedAt,
            ))
        .toList();
    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return summaries;
  }

  @override
  Future<void> deleteThread(String id) async {
    _threads.remove(id);
  }

  // ── Settings ─────────────────────────────────────────────────────────────

  @override
  Future<T?> getSetting<T>(String key) async {
    final value = _settings[key];
    if (value == null) return null;
    if (value is Map) return Map<String, dynamic>.from(value) as T?;
    return value as T?;
  }

  @override
  Future<void> setSetting<T>(String key, T value) async {
    assertNoSecrets(<String, Object?>{'key': key, 'value': value}, 'setting');
    _settings[key] = value;
  }

  // ── Facts ────────────────────────────────────────────────────────────────

  @override
  Future<Fact?> getFact(String id) async => _facts[id];

  @override
  Future<void> saveFact(Fact fact) async {
    assertNoSecrets(fact.toJson(), 'fact');
    _facts[fact.id] = fact;
  }

  @override
  Future<List<Fact>> listFacts() async {
    final facts = _facts.values.toList();
    facts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return facts;
  }

  @override
  Future<void> deleteFact(String id) async {
    _facts.remove(id);
  }

  @override
  Future<void> clearFacts() async {
    _facts.clear();
  }

  // ── Export / Import ──────────────────────────────────────────────────────

  @override
  Future<ExportPayload> exportAll() async {
    // Strip any accidental secrets from the export (parity with the
    // IndexedDB adapter, which filtered by `containsSecrets`).
    final safeThreads = _threads.values
        .where((t) => !containsSecrets(jsonEncode(t.toJson())))
        .toList();
    final safeFacts = _facts.values
        .where((f) => !containsSecrets(jsonEncode(f.toJson())))
        .toList();

    return ExportPayload(
      exportedAt: DateTime.now().millisecondsSinceEpoch,
      threads: safeThreads,
      facts: safeFacts,
    );
  }

  @override
  Future<ImportResult> importAll(ExportPayload data) async {

    var imported = 0;
    var skipped = 0;

    for (final thread in data.threads) {
      try {
        assertNoSecrets(thread.toJson(), 'imported thread');
        await saveThread(thread);
        imported++;
      } catch (_) {
        skipped++;
      }
    }

    for (final fact in data.facts) {
      try {
        assertNoSecrets(fact.toJson(), 'imported fact');
        await saveFact(fact);
        imported++;
      } catch (_) {
        skipped++;
      }
    }

    return ImportResult(imported: imported, skipped: skipped);
  }
}

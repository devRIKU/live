/// Storage barrel — the adapter set implements `StorageAdapter`:
///
/// • [SqliteStorageAdapter] — desktop SQLite via sqflite_common_ffi.
/// • [MemoryStorageAdapter] — tests and web fallback (IndexedDB parity).
/// • `encodeExport` / `importData` — the shared JSON export format.
library;

export '../storage_adapter.dart';
export 'memory_storage_adapter.dart';
export 'sqlite_storage_adapter.dart';
export 'export_import.dart';

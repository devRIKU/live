/// Persistent provider-key storage backed by the OS secure store.
///
/// Keys live in `flutter_secure_storage` (OS-protected storage on Windows),
/// never in the app database, the params store or export files — the export
/// path already refuses payloads that contain secrets.
///
/// The transport resolves a key per request and cannot await, so every key is
/// loaded into a write-through cache at start-up and [peek] reads from it.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/providers_registry.dart' show providers;
import 'settings_controller.dart' show SecretStore;

class SecureSecretStore implements SecretStore {
  SecureSecretStore._(this._storage, this._cache);

  final FlutterSecureStorage _storage;
  final Map<String, String> _cache;

  static const String _prefix = 'lively.providerKey.';

  /// Open the store and load every known provider's key into the cache.
  /// Throws if the OS store is unavailable — the caller falls back to the
  /// in-memory store rather than starting without a settings path at all.
  static Future<SecureSecretStore> open() async {
    const storage = FlutterSecureStorage();
    final cache = <String, String>{};
    for (final p in providers) {
      final value = await storage.read(key: '$_prefix${p.id}');
      if (value != null && value.isNotEmpty) cache[p.id] = value;
    }
    return SecureSecretStore._(storage, cache);
  }

  @override
  String? peek(String providerId) => _cache[providerId];

  @override
  Future<bool> hasSecret(String providerId) async => _cache.containsKey(providerId);

  @override
  Future<void> setSecret(String providerId, String secret) async {
    final value = secret.trim();
    if (value.isEmpty) return deleteSecret(providerId);
    // Persist first: a key shown as saved must survive a restart.
    await _storage.write(key: '$_prefix$providerId', value: value);
    _cache[providerId] = value;
  }

  @override
  Future<void> deleteSecret(String providerId) async {
    await _storage.delete(key: '$_prefix$providerId');
    _cache.remove(providerId);
  }
}

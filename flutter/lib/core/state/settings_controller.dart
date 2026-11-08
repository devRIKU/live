import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/chat/model_params.dart'
    show
        ModelParams,
        clampParamsToModel,
        defaultParams,
        defaultParamsFor,
        paramsKey,
        sanitizeParams;
import '../services/chat/thread_controller.dart' show chatStorage;
import '../services/providers_registry.dart' show LlmProvider;
import '../services/storage_adapter.dart';

/// Settings state + persistence (port of `src/app/SettingsDialog.tsx` state,
/// `src/app/theme.ts`, and `src/chat/modelParams.ts` persistence).
///
/// Every control writes to storage and takes effect immediately: there is no
/// Save button for a switch. The controller is the single source of truth for
/// the settings surface; the dialog is a pure view over it.

// ─── Theme ────────────────────────────────────────────────────────────────

/// One palette with two states. `system` follows the device.
enum LivelyTheme { system, light, dark }

extension LivelyThemeName on LivelyTheme {
  String get storageName => name; // 'system' | 'light' | 'dark'
  String get label => switch (this) {
        LivelyTheme.system => 'System',
        LivelyTheme.light => 'Light',
        LivelyTheme.dark => 'Dark',
      };

  static LivelyTheme parse(String? raw) => switch (raw) {
        'light' => LivelyTheme.light,
        'dark' => LivelyTheme.dark,
        _ => LivelyTheme.system,
      };
}

const String _themeKey = 'lively.theme';
const String _accountKey = 'lively.accountName';

// ─── Secret store abstraction ────────────────────────────────────────────

/// Foundation for an OS credential-vault-backed key store.
abstract class SecretStore {
  Future<bool> hasSecret(String providerId);
  Future<void> setSecret(String providerId, String secret);
  Future<void> deleteSecret(String providerId);

  /// The secret for [providerId] if it is already in memory, else `null`.
  /// Synchronous on purpose: the chat transport resolves a key per request
  /// and cannot await. Implementations keep a write-through cache.
  String? peek(String providerId);
}

/// Volatile, process-lifetime secret store (default).
class MemorySecretStore implements SecretStore {
  final Map<String, String> _secrets = {};

  @override
  Future<bool> hasSecret(String providerId) async =>
      _secrets.containsKey(providerId);

  @override
  Future<void> setSecret(String providerId, String secret) async {
    if (secret.isEmpty) {
      _secrets.remove(providerId);
    } else {
      _secrets[providerId] = secret;
    }
  }

  @override
  Future<void> deleteSecret(String providerId) async {
    _secrets.remove(providerId);
  }

  @override
  String? peek(String providerId) => _secrets[providerId];
}

/// Ambient secret store for the transport layer. Set from `main` before the
/// first chat request; `chat_transport.providerKeyResolver` consults it.
SecretStore? globalSecretStore;

// ─── State + controller ──────────────────────────────────────────────────

class SettingsState {
  final LivelyTheme theme;
  final String accountName;

  /// Per-model generation parameters.
  final ModelParams params;
  final bool loaded;

  /// Fact memory surfaced in the dialog.
  final List<Fact> facts;

  const SettingsState({
    this.theme = LivelyTheme.system,
    this.accountName = 'Lively Franklin',
    this.params = defaultParams,
    this.facts = const [],
    this.loaded = false,
  });

  SettingsState copyWith({
    LivelyTheme? theme,
    String? accountName,
    ModelParams? params,
    List<Fact>? facts,
    bool? loaded,
  }) =>
      SettingsState(
        theme: theme ?? this.theme,
        accountName: accountName ?? this.accountName,
        params: params ?? this.params,
        facts: facts ?? this.facts,
        loaded: loaded ?? this.loaded,
      );
}

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, SettingsState>((ref) {
  // The same adapter the chat layer uses: `main.dart` installs the SQLite one
  // before `runApp`, so settings, facts and export/import all see real data.
  final controller = SettingsController(
    storage: chatStorage,
    secrets: globalSecretStore ??= MemorySecretStore(),
  );
  ref.onDispose(controller.dispose);
  controller.load();
  return controller;
});

/// Riverpod StateNotifier holding every settings value, persisted through
/// the injected `StorageAdapter` key-value store.
class SettingsController extends StateNotifier<SettingsState> {
  SettingsController({
    required StorageAdapter storage,
    required SecretStore secrets,
    this.modelLabel = 'default',
    this.providerId = 'openrouter',
    this.modelId = 'default',
  })  : _storage = storage,
        _secrets = secrets,
        super(const SettingsState());

  final StorageAdapter _storage;
  final SecretStore _secrets;

  /// Label of the active model, shown in the generation heading.
  String modelLabel;

  /// Which provider/model the generation params belong to (used for the
  /// storage key, mirroring `paramsKey(providerId, modelId)`). Updated by
  /// [selectModel] so params follow the model the user picked.
  String providerId;
  String modelId;

  /// Point the generation params at another model: remember which model the
  /// params belong to, then load that model's saved params (or its defaults),
  /// clamped to what the model supports. Port of the `setParams(loadModelParams
  /// (provider, nextModelId))` step of `selectModel` in App.tsx.
  Future<void> selectModel(LlmProvider provider, String model, String label) async {
    providerId = provider.id;
    modelId = model;
    modelLabel = label;
    ModelParams params;
    try {
      final raw =
          await _storage.getSetting<Map<String, dynamic>>(paramsKey(provider.id, model));
      params = raw == null
          ? defaultParamsFor(provider, model)
          : clampParamsToModel(sanitizeParams(raw), provider, model);
    } catch (_) {
      params = defaultParamsFor(provider, model);
    }
    // A fast second switch must not be overwritten by this slower first one.
    if (providerId == provider.id && modelId == model && mounted) {
      state = state.copyWith(params: params);
    }
  }

  StorageAdapter get storage => _storage;
  SecretStore get secrets => _secrets;

  /// Load persisted theme, account name, params, and facts.
  Future<void> load() async {
    try {
      final themeRaw = await _storage.getSetting<String>(_themeKey);
      final name = await _storage.getSetting<String>(_accountKey);
      final paramsRaw =
          await _storage.getSetting<Map<String, dynamic>>(paramsKey(providerId, modelId));
      final facts = await _storage.listFacts();
      state = state.copyWith(
        theme: LivelyThemeName.parse(themeRaw),
        accountName: name ?? state.accountName,
        params: sanitizeParams(paramsRaw),
        facts: facts,
        loaded: true,
      );
    } catch (_) {
      // A corrupt or unavailable store must not block the UI.
      state = state.copyWith(loaded: true);
    }
  }

  // ── Theme ────────────────────────────────────────────────────────────────

  Future<void> setTheme(LivelyTheme theme) async {
    state = state.copyWith(theme: theme);
    try {
      await _storage.setSetting(_themeKey, theme.storageName);
    } catch (_) {
      // A theme that cannot be persisted is still applied for this session.
    }
  }

  // ── Account ──────────────────────────────────────────────────────────────

  Future<void> setAccountName(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    state = state.copyWith(accountName: clean);
    try {
      await _storage.setSetting(_accountKey, clean);
    } catch (_) {
      // ignore — in-memory value still applies
    }
  }

  // ── Generation params ────────────────────────────────────────────────────

  Future<void> setParams(ModelParams params) async {
    final clean = sanitizeParams(params.toJson());
    state = state.copyWith(params: clean);
    try {
      await _storage.setSetting(paramsKey(providerId, modelId), clean.toJson());
    } catch (_) {
      // ignore — in-memory value still applies
    }
  }

  Future<void> setTemperature(double v) => setParams(state.params.copyWith(temperature: v));
  Future<void> setTopP(double v) => setParams(state.params.copyWith(topP: v));
  Future<void> setMaxTokens(num v) => setParams(state.params.copyWith(maxTokens: v.toInt()));

  // ── Facts (memory) ───────────────────────────────────────────────────────

  Future<void> refreshFacts() async {
    try {
      state = state.copyWith(facts: await _storage.listFacts());
    } catch (_) {
      // ignore
    }
  }

  Future<void> deleteFact(String id) async {
    try {
      await _storage.deleteFact(id);
      await refreshFacts();
    } catch (_) {
      rethrow;
    }
  }

  Future<void> clearFacts() async {
    try {
      await _storage.clearFacts();
      await refreshFacts();
    } catch (_) {
      rethrow;
    }
  }
}

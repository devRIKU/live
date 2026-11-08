/// backendProviders — fetches live model and provider data from the backend.
/// Port of `src/chat/useBackendProviders.ts` as a Riverpod controller.
///
/// Queries `/api/providers`, `/api/models`, `/api/health` and merges backend
/// data into the local provider registry so the rest of the app (transport,
/// failover, ModelBar, ModelOverlay) sees live data.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'chat_failover.dart';
import '../providers_registry.dart';
import 'dart:convert' show jsonDecode;

// ─── Backend types ───────────────────────────────────────────────────────────

class BackendModel {
  final String id;
  final String label;
  final int contextLimit;
  final int maxOutput;
  final bool vision;
  final bool tools;
  final String providerId;
  final String providerName;
  final bool available;
  final bool isLive;
  final String fullId;
  const BackendModel({
    required this.id,
    required this.label,
    required this.contextLimit,
    required this.maxOutput,
    required this.vision,
    required this.tools,
    required this.providerId,
    required this.providerName,
    required this.available,
    required this.fullId,
    this.isLive = false,
  });

  factory BackendModel.fromJson(Map<String, dynamic> j) => BackendModel(
        id: j['id'] as String? ?? '',
        label: j['label'] as String? ?? '',
        contextLimit: (j['contextLimit'] as num?)?.toInt() ?? 0,
        maxOutput: (j['maxOutput'] as num?)?.toInt() ?? 0,
        vision: j['vision'] as bool? ?? false,
        tools: j['tools'] as bool? ?? false,
        providerId: j['providerId'] as String? ?? '',
        providerName: j['providerName'] as String? ?? '',
        available: j['available'] as bool? ?? false,
        isLive: j['isLive'] as bool? ?? false,
        fullId: j['fullId'] as String? ?? '',
      );
}

class BackendProvider {
  final String id;
  final String name;
  final String? envKey;
  final bool hasKey;
  final String defaultModel;
  final List<BackendModel> models;
  final String state;
  const BackendProvider({
    required this.id,
    required this.name,
    required this.envKey,
    required this.hasKey,
    required this.defaultModel,
    required this.models,
    required this.state,
  });

  factory BackendProvider.fromJson(Map<String, dynamic> j) => BackendProvider(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        envKey: j['envKey'] as String?,
        hasKey: j['hasKey'] as bool? ?? false,
        defaultModel: j['defaultModel'] as String? ?? '',
        models: (j['models'] as List? ?? const [])
            .map((e) => BackendModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        state: j['state'] as String? ?? '',
      );
}

class BackendHealth {
  final String status;
  final String service;
  final String timestamp;
  final List<String> configuredProviders;
  const BackendHealth({
    required this.status,
    required this.service,
    required this.timestamp,
    required this.configuredProviders,
  });
}

// ─── Controller ──────────────────────────────────────────────────────────────

class BackendState {
  /// True while the initial fetch is in progress.
  final bool loading;
  /// True when the backend at /api/health responded OK.
  final bool backendOnline;
  /// Human-readable error, if the last fetch failed.
  final String? error;
  /// Providers enriched with live key/model data from the backend.
  final List<LlmProvider> liveProviders;
  /// Timestamp of last successful sync.
  final int? lastSync;
  const BackendState({
    this.loading = true,
    this.backendOnline = false,
    this.error,
    required this.liveProviders,
    this.lastSync,
  });
}

/// Merge backend provider data into the local provider registry.
///
/// The local registry is the source of truth for fields the backend doesn't
/// own (supportsStreaming, supportsStructuredOutput, etc.). The backend is
/// authoritative for key presence, model availability, and the model list
/// when it has a wider catalog.
List<LlmProvider> mergeProviders(List<BackendProvider> backendProviders) {
  final backendMap = {for (final p in backendProviders) p.id: p};

  // Start from local providers — this preserves order and static fields.
  final merged = <LlmProvider>[];
  for (final local in providers) {
    // Map backend "lively" provider id to local "prototype" id.
    final lookupId = local.id == 'prototype' ? 'lively' : local.id;
    final remote = backendMap[lookupId];
    if (remote == null) {
      merged.add(local);
      continue;
    }

    // Merge models: prefer backend models when available, enriched locally.
    final models = remote.models.isNotEmpty
        ? [
            for (final rm in remote.models)
              ModelOption(
                id: rm.id,
                label: rm.label,
                contextLimit: rm.contextLimit,
                maxOutput: rm.maxOutput,
                vision: rm.vision,
                tools: rm.tools,
                isLive: rm.isLive,
              ),
          ]
        : List.of(local.models);

    var state = local.state;
    if (remote.state == 'available' || remote.state == 'needs-key') {
      // needs-key still shows as available so the user can select; the
      // failover will handle errors.
      state = ProviderState.available;
    }

    merged.add(LlmProvider(
      id: local.id,
      name: remote.name.isNotEmpty ? remote.name : local.name,
      baseUrl: local.baseUrl,
      model: remote.defaultModel.isNotEmpty ? remote.defaultModel : local.model,
      models: models,
      supportsStreaming: local.supportsStreaming,
      supportsTools: local.supportsTools,
      supportsUsage: local.supportsUsage,
      supportsStructuredOutput: local.supportsStructuredOutput,
      contextLimit: local.contextLimit,
      envKey: local.envKey,
      state: state,
    ));
  }

  // Add any backend-only providers not in the local registry.
  for (final remote in backendProviders) {
    final localId = remote.id == 'lively' ? 'prototype' : remote.id;
    if (merged.any((m) => m.id == localId)) continue;

    merged.add(LlmProvider(
      id: localId,
      name: remote.name,
      baseUrl: '', // Backend proxies everything
      model: remote.defaultModel,
      models: [
        for (final rm in remote.models)
          ModelOption(
            id: rm.id,
            label: rm.label,
            contextLimit: rm.contextLimit,
            maxOutput: rm.maxOutput,
            vision: rm.vision,
            tools: rm.tools,
            isLive: rm.isLive,
          ),
      ],
      supportsStreaming: true,
      supportsTools: true,
      supportsUsage: false,
      supportsStructuredOutput: false,
      contextLimit: remote.models.isNotEmpty ? remote.models.first.contextLimit : 128000,
      envKey: remote.envKey ?? '',
      state: ProviderState.available,
    ));
  }

  return merged;
}

final backendProvidersProvider =
    StateNotifierProvider<BackendProvidersController, BackendState>((ref) {
  final controller = BackendProvidersController();
  controller.refresh();
  // Pick up key changes and new models without forcing an upstream refresh.
  controller.startPolling();
  ref.onDispose(controller.stopPolling);
  return controller;
});

class BackendProvidersController extends StateNotifier<BackendState> {
  BackendProvidersController() : super(BackendState(liveProviders: providers));

  Timer? _pollTimer;
  final http.Client _client = http.Client();

  static const _backendRoot = 'http://localhost:3001';

  /// Also update the global `providers` array so the failover logic (which
  /// reads the registry) sees the live state.
  void _syncGlobalProviders(List<LlmProvider> live) {
    for (var i = 0; i < providers.length; i++) {
      final lp = live.firstWhere(
        (l) => l.id == providers[i].id,
        orElse: () => providers.first,
      );
      if (lp.id != providers[i].id) continue;
      recordProviderState(providers[i].id, lp.state);
      setProviderModels(
        providers[i].id,
        models: lp.models,
        model: lp.model,
      );
    }
  }

  Future<void> refresh({bool force = true}) async {
    try {
      // 1. Health check (5 s).
      var backendOnline = false;
      try {
        final healthRes = await _client
            .get(Uri.parse('$_backendRoot/api/health'))
            .timeout(const Duration(seconds: 5));
        if (healthRes.statusCode >= 200 && healthRes.statusCode < 300) {
          backendOnline = true;
        }
      } catch (_) {
        // Backend not reachable — use local providers as-is.
      }

      if (!backendOnline) {
        if (!mounted) return;
        state = BackendState(
          loading: false,
          backendOnline: false,
          error: 'Backend not reachable. Using local provider configuration.',
          liveProviders: providers,
        );
        return;
      }

      // 2. Fetch providers (with live refresh).
      var backendProviders = <BackendProvider>[];
      try {
        final provRes = await _client
            .get(Uri.parse('$_backendRoot/api/providers${force ? '?refresh=true' : ''}'))
            .timeout(const Duration(seconds: 8));
        if (provRes.statusCode >= 200 && provRes.statusCode < 300) {
          final data = jsonDecode(provRes.body);
          if (data is Map<String, dynamic> && data['providers'] is List) {
            backendProviders = [
              for (final e in data['providers'] as List)
                BackendProvider.fromJson(e as Map<String, dynamic>),
            ];
          }
        }
      } catch (_) {
        // Non-fatal: we'll use local providers.
      }

      // 3. Merge with local.
      final live = backendProviders.isNotEmpty ? mergeProviders(backendProviders) : providers;

      // 4. Sync global provider state.
      _syncGlobalProviders(live);

      if (!mounted) return;
      state = BackendState(
        loading: false,
        backendOnline: true,
        error: null,
        liveProviders: live,
        lastSync: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (err) {
      if (!mounted) return;
      state = BackendState(
        loading: false,
        backendOnline: false,
        error: err.toString(),
        liveProviders: providers,
      );
    }
  }

  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) => refresh(force: false));
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _client.close();
  }
}
/// Per-model generation parameters and model selection — port of
/// `src/chat/modelParams.ts`.
///
/// Parameters are a property of the model, not the app: a reasoning model and
/// a small fast model want different temperatures and output caps. They live
/// in local storage, validated on read, and are never sent anywhere else.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../providers_registry.dart';
import 'chat_transport.dart' show WireParams;

// ─── Types ───────────────────────────────────────────────────────────────────

class ModelParams {
  /// Sampling temperature, 0–2.
  final double temperature;
  /// Nucleus sampling, 0–1.
  final double topP;
  /// Maximum tokens the reply may contain.
  final int maxTokens;
  const ModelParams({
    required this.temperature,
    required this.topP,
    required this.maxTokens,
  });

  ModelParams copyWith({double? temperature, double? topP, int? maxTokens}) =>
      ModelParams(
        temperature: temperature ?? this.temperature,
        topP: topP ?? this.topP,
        maxTokens: maxTokens ?? this.maxTokens,
      );

  Map<String, dynamic> toJson() => {
        'temperature': temperature,
        'topP': topP,
        'maxTokens': maxTokens,
      };
}

class ParamBounds {
  final double min, max, step;
  const ParamBounds(this.min, this.max, this.step);
}

/// Bounds for every adjustable parameter.
const paramBounds = (
  temperature: ParamBounds(0, 2, 0.05),
  topP: ParamBounds(0, 1, 0.01),
  maxTokens: (min: 256.0, max: 128000.0, step: 256.0),
);

/// Sensible starting point when a model declares nothing else.
const defaultParams = ModelParams(temperature: 0.7, topP: 1, maxTokens: 2048);

const _storesPrefix = 'lively.params.v1';
const _modelsPrefix = 'lively.model.v1';

/// Minimal storage surface so tests can pass a fake store.
abstract class ParamStore {
  String? getItem(String key);
  void setItem(String key, String value);
  void removeItem(String key);
}

/// Memory-backed store (tests, offline fallback).
class MemoryParamStore implements ParamStore {
  final Map<String, String> _map = {};
  @override
  String? getItem(String key) => _map[key];
  @override
  void setItem(String key, String value) => _map[key] = value;
  @override
  void removeItem(String key) => _map.remove(key);
}

/// Store backed by a SharedPreferences instance.
class SharedParamsStore implements ParamStore {
  final SharedPreferences prefs;
  SharedParamsStore(this.prefs);
  @override
  String? getItem(String key) => prefs.getString(key);
  @override
  void setItem(String key, String value) => prefs.setString(key, value);
  @override
  void removeItem(String key) => prefs.remove(key);
}

SharedPreferences? _prefsInstance;

ParamStore defaultStore() => _prefsInstance == null
    ? MemoryParamStore()
    : SharedParamsStore(_prefsInstance!);

/// Load SharedPreferences once (call from main before first UI build).
Future<void> initParamStore() async {
  try {
    _prefsInstance = await SharedPreferences.getInstance();
  } catch (_) {
    _prefsInstance = null;
  }
}

// ─── Validation ──────────────────────────────────────────────────────────────

double _clamp(double value, double min, double max) =>
    value < min ? min : value > max ? max : value;

/// Coerce arbitrary input into a valid `ModelParams`. Invalid numbers fall
/// back to the default rather than throwing: a corrupt setting must never
/// make the composer unusable.
ModelParams sanitizeParams(Map<String, dynamic>? input) {
  double toDouble(Object? v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? double.nan;

  final temperature = input == null ? double.nan : toDouble(input['temperature']);
  final topP = input == null ? double.nan : toDouble(input['topP']);
  final maxTokens = input == null ? double.nan : toDouble(input['maxTokens']);

  double clamped(double v, ParamBounds b, double fallback) =>
      v.isNaN ? fallback : _clamp(v, b.min, b.max);

  return ModelParams(
    temperature: clamped(temperature, paramBounds.temperature, defaultParams.temperature),
    topP: clamped(topP, paramBounds.topP, defaultParams.topP),
    maxTokens: maxTokens.isNaN
        ? defaultParams.maxTokens
        : _clamp(maxTokens, paramBounds.maxTokens.min, paramBounds.maxTokens.max).round(),
  );
}

/// Defaults derived from the model's own output cap. A model that can emit
/// 64k tokens should not start at 2k.
ModelParams defaultParamsFor(LlmProvider provider, [String? modelId]) {
  final model = getModel(provider, modelId);
  return sanitizeParams({
    'temperature': defaultParams.temperature,
    'topP': defaultParams.topP,
    'maxTokens': model.maxOutput < 8192 ? model.maxOutput : 8192,
  });
}

/// Clamp output cap to what the chosen model actually allows.
ModelParams clampParamsToModel(ModelParams params, LlmProvider provider, [String? modelId]) {
  final model = getModel(provider, modelId);
  return sanitizeParams({
    'temperature': params.temperature,
    'topP': params.topP,
    'maxTokens': params.maxTokens < model.maxOutput ? params.maxTokens : model.maxOutput,
  });
}

// ─── Persistence ─────────────────────────────────────────────────────────────

String paramsKey(String providerId, String modelId) =>
    '$_storesPrefix.$providerId.$modelId';

/// Read saved parameters for one model, falling back to model defaults.
ModelParams loadModelParams(LlmProvider provider, [String? modelId, ParamStore? store]) {
  final model = getModel(provider, modelId);
  final fallback = defaultParamsFor(provider, model.id);
  final s = store ?? defaultStore();
  try {
    final raw = s.getItem(paramsKey(provider.id, model.id));
    if (raw == null) return fallback;
    return clampParamsToModel(
      sanitizeParams(_tryDecode(raw)),
      provider,
      model.id,
    );
  } catch (_) {
    return fallback;
  }
}

Map<String, dynamic>? _tryDecode(String raw) {
  // Minimal JSON parse without importing convert twice; keys are camelCase.
  final body = raw.trim();
  final out = <String, dynamic>{};
  final re = RegExp(r'"([A-Za-z]+)"\s*:\s*(-?[0-9.]+)');
  for (final match in re.allMatches(body)) {
    out[match.group(1)!] = num.tryParse(match.group(2)!) ?? 0;
  }
  return out.isNotEmpty ? out : null;
}

/// Persist parameters for one model. Invalid values are clamped first.
ModelParams saveModelParams(
  LlmProvider provider,
  String modelId,
  ModelParams params, [
  ParamStore? store,
]) {
  final clean = clampParamsToModel(params, provider, modelId);
  try {
    (store ?? defaultStore()).setItem(
      paramsKey(provider.id, modelId),
      '{"temperature":${clean.temperature},"topP":${clean.topP},"maxTokens":${clean.maxTokens}}',
    );
  } catch (_) {
    // Quota or private mode — the in-memory value still applies.
  }
  return clean;
}

/// Remove saved parameters, restoring the model defaults.
ModelParams resetModelParams(LlmProvider provider, String modelId, [ParamStore? store]) {
  try {
    (store ?? defaultStore()).removeItem(paramsKey(provider.id, modelId));
  } catch (_) {
    // ignore
  }
  return defaultParamsFor(provider, modelId);
}

// ─── Model selection ─────────────────────────────────────────────────────────

String _modelKey(String providerId) => '$_modelsPrefix.$providerId';

/// Read the last model chosen for a provider. Unknown ids fall back.
String loadSelectedModel(LlmProvider provider, [ParamStore? store]) {
  final s = store ?? defaultStore();
  try {
    final raw = s.getItem(_modelKey(provider.id));
    if (raw != null && provider.models.any((m) => m.id == raw)) return raw;
  } catch (_) {
    // ignore
  }
  return provider.model;
}

/// Persist the chosen model for a provider.
void saveSelectedModel(String providerId, String modelId, [ParamStore? store]) {
  try {
    (store ?? defaultStore()).setItem(_modelKey(providerId), modelId);
  } catch (_) {
    // ignore
  }
}

/// Build the wire-level sampling object, omitting defaults that add noise.
const ToWire _toWire = ToWire();

class ToWire {
  const ToWire();
  WireParams call(ModelParams params) => WireParams(
        temperature: params.temperature,
        topP: params.topP,
        maxTokens: params.maxTokens,
      );
}

WireParams toWireParams(ModelParams params) => _toWire(params);
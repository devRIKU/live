import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop (window/shell) adapters — port of `src/adapters/desktop.ts` and
/// `src/adapters/desktopAdapter.ts`.
///
/// The compiled app never sees an API key. `setSecret` sends the key to the
/// native side, which stores it in the Windows Credential Manager; the
/// frontend can only ask whether a key exists, never read it back.
///
/// Provider requests are proxied natively (`provider_chat`), so the key is
/// read and attached on the platform side and never crosses the IPC boundary
/// as a value the UI layer can read.
///
/// Tauri deviations (documented per the porting rules):
/// - `isDesktop()` checked for the injected `__TAURI_INTERNALS__` webview
///   marker. The Flutter app *is* the desktop runtime, so the platform check
///   is the equivalent marker (overridable for tests via
///   [DesktopPlatform.isDesktopRuntime]).
/// - Tauri `invoke('set_secret' | 'delete_secret' | 'has_secret' |
///   'secret_status')` commands are replaced by a [MethodChannel]
///   (`com.lively.openall/secrets`). The Windows implementation must call
///   `CredWriteW` / `CredReadW` / `CredDeleteW` (Windows Credential Manager)
///   — see [MethodChannelDesktopBridge] for the exact contract.
/// - The Tauri `Channel<string>` used by `provider_chat` is replaced by an
///   [EventChannel] (`com.lively.openall/provider_chat`) streaming raw SSE
///   chunks keyed by `requestId`; `onChunk` still receives raw SSE text and
///   the caller parses it with the shared SSE parser.
/// - Window/shell integration uses `package:window_manager` instead of the
///   Tauri window API. Calls require `WidgetsFlutterBinding.ensureInitialized()`
///   plus `windowManager.ensureInitialized()` to have run at startup.

// ─── Runtime detection (desktop.ts) ─────────────────────────────────────────

/// Runtime detection.
///
/// The same app used to run in three places (browser dev, Tauri dev,
/// compiled `.exe`). The Flutter port only ships the desktop path, so the
/// platform check replaces Tauri's `__TAURI_INTERNALS__` marker.
class DesktopPlatform {
  DesktopPlatform._();

  /// Toggle used by tests / web embeds. Defaults to "running on a desktop OS".
  static bool isDesktopRuntime =
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;
}

/// Whether the app is running on the desktop (native) runtime.
bool isDesktop() => DesktopPlatform.isDesktopRuntime;

// ─── Secrets (desktopAdapter.ts) ────────────────────────────────────────────

/// Status of one provider's stored key.
class DesktopSecretStatus {
  final String provider;
  final bool present;
  const DesktopSecretStatus({required this.provider, required this.present});

  factory DesktopSecretStatus.fromJson(Map<String, dynamic> j) =>
      DesktopSecretStatus(
        provider: j['provider'] as String? ?? '',
        present: j['present'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() =>
      {'provider': provider, 'present': present};
}

/// Thrown when the native credential-store hook is not registered (for
/// example in a headless unit test or before the Windows plugin attaches).
class DesktopNativeUnavailable implements Exception {
  final String message;
  const DesktopNativeUnavailable(this.message);
  @override
  String toString() => 'DesktopNativeUnavailable: $message';
}

// ─── Native chat wire types (desktopAdapter.ts) ─────────────────────────────

/// Sampling parameters in wire (snake_case) form.
class NativeChatParams {
  final double? temperature;
  final double? topP;
  final int? maxTokens;
  const NativeChatParams({this.temperature, this.topP, this.maxTokens});

  Map<String, dynamic> toJson() => {
        if (temperature != null) 'temperature': temperature,
        if (topP != null) 'top_p': topP,
        if (maxTokens != null) 'max_tokens': maxTokens,
      };
}

/// OpenAI-compatible function definition inside a `tool_calls` entry.
class NativeChatFunctionCall {
  final String name;

  /// Raw JSON arguments string, exactly as the provider sends them.
  final String arguments;
  const NativeChatFunctionCall({required this.name, required this.arguments});

  Map<String, dynamic> toJson() => {'name': name, 'arguments': arguments};
}

/// A `tool_calls` entry of a chat message.
class NativeChatToolCall {
  final String id;
  final String type; // always 'function'
  final NativeChatFunctionCall function;
  const NativeChatToolCall({
    required this.id,
    this.type = 'function',
    required this.function,
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'type': type, 'function': function.toJson()};
}

/// One message on the wire to the native proxy.
class NativeChatMessage {
  final String role;
  final Object? content;
  final String? name;
  final String? toolCallId;
  final List<NativeChatToolCall>? toolCalls;
  const NativeChatMessage({
    required this.role,
    required this.content,
    this.name,
    this.toolCallId,
    this.toolCalls,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        if (name != null) 'name': name,
        if (toolCallId != null) 'tool_call_id': toolCallId,
        if (toolCalls != null)
          'tool_calls': toolCalls!.map((t) => t.toJson()).toList(),
      };
}

/// Request payload for `provider_chat`.
class NativeChatRequest {
  final String provider;
  final String model;
  final List<NativeChatMessage> messages;
  final String requestId;

  /// Sampling parameters in wire (snake_case) form.
  final NativeChatParams? params;

  /// OpenAI-compatible function definitions.
  final List<Map<String, dynamic>>? tools;

  /// Ask the provider to report token usage when the stream ends.
  final bool includeUsage;
  const NativeChatRequest({
    required this.provider,
    required this.model,
    required this.messages,
    required this.requestId,
    this.params,
    this.tools,
    this.includeUsage = false,
  });
}

/// Failure raised by [nativeChat].
class NativeChatError implements Exception {
  final int status;
  final String message;
  const NativeChatError({required this.status, required this.message});

  @override
  String toString() => 'NativeChatError($status): $message';
}

// ─── Native bridge ──────────────────────────────────────────────────────────

/// Native-side operations that in the TS build were Tauri `invoke` commands.
///
/// Swap this out with a fake in tests, or provide a custom implementation if
/// the platform hooks move to FFI instead of method channels.
abstract class DesktopBridge {
  /// Store a provider API key in the OS credential store.
  Future<void> setSecret(String provider, String secret);

  /// Remove a provider API key from the OS credential store.
  Future<void> deleteSecret(String provider);

  /// Report whether a provider has a stored key.
  Future<bool> hasSecret(String provider);

  /// Report key status for several providers at once.
  Future<List<DesktopSecretStatus>> secretStatus(List<String> providers);

  /// Stream a chat completion through the native proxy.
  ///
  /// `onChunk` receives raw SSE text. The caller parses it with the same
  /// logic the web path uses, so both transports share one SSE parser.
  ///
  /// Throws [NativeChatError] when the provider or the transport fails.
  Future<void> nativeChat(
    NativeChatRequest request,
    void Function(String text) onChunk,
  );

  /// Ask the native side to stop an in-flight request.
  Future<void> cancelNativeChat(String requestId);
}

/// Channel / event names for the Windows (or macOS/Linux) side.
///
/// Platform contract (still to be implemented natively):
///
/// MethodChannel `com.lively.openall/secrets`
///   - `set_secret`    args `{provider: String, secret: String}` -> null
///   - `delete_secret` args `{provider: String}` -> null
///   - `has_secret`    args `{provider: String}` -> bool
///   - `secret_status` args `{providers: List<String>}` ->
///       `List<{provider: String, present: bool}>`
///
/// MethodChannel `com.lively.openall/desktop`
///   - `provider_chat` args `{provider, model, messages, requestId, params,
///       tools, includeUsage}` -> null when the stream is finished
///   - `cancel_chat`   args `{requestId}` -> null
///
/// EventChannel `com.lively.openall/provider_chat`
///   - emits `{requestId: String, chunk: String}` (or a bare `String` chunk)
///     for every SSE fragment of the in-flight request.
class MethodChannelDesktopBridge implements DesktopBridge {
  static const MethodChannel _channel =
      MethodChannel('com.lively.openall/desktop');
  static const MethodChannel _secrets =
      MethodChannel('com.lively.openall/secrets');
  static const EventChannel _chatEvents =
      EventChannel('com.lively.openall/provider_chat');

  StreamController<_ChatChunk>? _chatController;
  StreamSubscription<dynamic>? _chatPlatformSub;

  /// Single platform-side event subscription, multiplexed per requestId.
  Stream<_ChatChunk> get _chunks {
    final controller =
        _chatController ??= StreamController<_ChatChunk>.broadcast();
    _chatPlatformSub ??= _chatEvents.receiveBroadcastStream().listen(
      (event) {
        final chunk = _asChatChunk(event);
        if (chunk != null) controller.add(chunk);
      },
      onError: (Object e) {
        if (!controller.isClosed) controller.addError(e);
      },
    );
    return controller.stream;
  }

  static _ChatChunk? _asChatChunk(Object? event) {
    if (event is String) return _ChatChunk(null, event);
    if (event is Map) {
      final chunk = event['chunk'] ?? event['text'];
      if (chunk is String) {
        final requestId = event['requestId'];
        return _ChatChunk(
          requestId is String ? requestId : null,
          chunk,
        );
      }
    }
    return null;
  }

  Future<dynamic> _invoke(String command, [Map<String, dynamic>? args]) async {
    try {
      return await _channel.invokeMethod<dynamic>(command, args);
    } on MissingPluginException catch (e) {
      throw DesktopNativeUnavailable(
        'Native hook "$command" is not registered on this platform. '
        'Register it in the Windows runner / plugin. ($e)',
      );
    }
  }

  @override
  Future<void> setSecret(String provider, String secret) async {
    try {
      await _secrets.invokeMethod<void>('set_secret',
          {'provider': provider, 'secret': secret});
    } on MissingPluginException catch (e) {
      throw DesktopNativeUnavailable(
        'Credential-store hook is not registered. Implement set_secret with '
        'the Windows Credential Manager (CredWriteW). ($e)',
      );
    }
  }

  @override
  Future<void> deleteSecret(String provider) async {
    try {
      await _secrets.invokeMethod<void>('delete_secret', {'provider': provider});
    } on MissingPluginException catch (e) {
      throw DesktopNativeUnavailable(
        'Credential-store hook is not registered. Implement delete_secret '
        'with the Windows Credential Manager (CredDeleteW). ($e)',
      );
    }
  }

  @override
  Future<bool> hasSecret(String provider) async {
    try {
      return await _secrets.invokeMethod<bool>('has_secret',
              {'provider': provider}) ??
          false;
    } on MissingPluginException catch (e) {
      throw DesktopNativeUnavailable(
        'Credential-store hook is not registered. Implement has_secret with '
        'the Windows Credential Manager (CredReadW). ($e)',
      );
    }
  }

  @override
  Future<List<DesktopSecretStatus>> secretStatus(List<String> providers) async {
    try {
      final raw = await _secrets.invokeMethod<dynamic>(
          'secret_status', {'providers': providers});
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((m) => DesktopSecretStatus.fromJson(
              Map<String, dynamic>.from(m)))
          .toList();
    } on MissingPluginException catch (e) {
      throw DesktopNativeUnavailable(
        'Credential-store hook is not registered. Implement secret_status '
        'with the Windows Credential Manager. ($e)',
      );
    }
  }

  @override
  Future<void> nativeChat(
    NativeChatRequest request,
    void Function(String text) onChunk,
  ) async {
    final sub = _chunks
        .where((c) => c.requestId == null || c.requestId == request.requestId)
        .listen((c) => onChunk(c.text));
    try {
      await _invoke('provider_chat', {
        'provider': request.provider,
        'model': request.model,
        'messages': request.messages.map((m) => m.toJson()).toList(),
        'requestId': request.requestId,
        'params': request.params?.toJson(),
        'tools': request.tools,
        'includeUsage': request.includeUsage,
      });
    } on MissingPluginException catch (e) {
      throw NativeChatError(
        status: -1,
        message: 'Native provider_chat hook is not registered. ($e)',
      );
    } on PlatformException catch (e) {
      throw NativeChatError(
        status: int.tryParse(e.code) ?? -1,
        message: e.message ?? e.code,
      );
    } finally {
      await sub.cancel();
    }
  }

  @override
  Future<void> cancelNativeChat(String requestId) async {
    try {
      await _invoke('cancel_chat', {'requestId': requestId});
    } catch (_) {
      // The request may already have finished — cancellation is best effort.
    }
  }
}

class _ChatChunk {
  final String? requestId;
  final String text;
  const _ChatChunk(this.requestId, this.text);
}

/// Active native bridge. Replace in tests with a fake [DesktopBridge].
DesktopBridge desktopBridge = MethodChannelDesktopBridge();

// ─── TS-style top-level API (desktopAdapter.ts) ─────────────────────────────

/// Store a provider API key in the OS credential store.
Future<void> setSecret(String provider, String secret) =>
    desktopBridge.setSecret(provider, secret);

/// Remove a provider API key from the OS credential store.
Future<void> deleteSecret(String provider) =>
    desktopBridge.deleteSecret(provider);

/// Report whether a provider has a stored key.
Future<bool> hasSecret(String provider) => desktopBridge.hasSecret(provider);

/// Report key status for several providers at once.
Future<List<DesktopSecretStatus>> secretStatus(List<String> providers) =>
    desktopBridge.secretStatus(providers);

/// Stream a chat completion through the native proxy.
///
/// `onChunk` receives raw SSE text. The caller parses it with the same logic
/// the web path uses, so both transports share one SSE parser.
///
/// Throws [NativeChatError] when the provider or the transport fails.
Future<void> nativeChat(
  NativeChatRequest request,
  void Function(String text) onChunk,
) =>
    desktopBridge.nativeChat(request, onChunk);

/// Ask the native side to stop an in-flight request.
Future<void> cancelNativeChat(String requestId) =>
    desktopBridge.cancelNativeChat(requestId);

// ─── Window / shell integration (replaces the Tauri window API) ─────────────

/// Window and shell integration for the desktop shell.
///
/// Requires `WidgetsFlutterBinding.ensureInitialized()` and
/// `windowManager.ensureInitialized()` to have run during app startup
/// (see `main()`), otherwise [window_manager] throws.
class DesktopWindow {
  DesktopWindow._();

  static Future<void> ensureInitialized() => windowManager.ensureInitialized();

  static Future<void> setTitle(String title) => windowManager.setTitle(title);

  /// Bring the window to the front and focus it (shell "show in foreground").
  static Future<void> focus() => windowManager.focus();

  static Future<void> minimize() => windowManager.minimize();
  static Future<void> maximize() => windowManager.maximize();
  static Future<void> unmaximize() => windowManager.unmaximize();
  static Future<void> restore() => windowManager.restore();
  static Future<void> close() => windowManager.close();

  /// Window transparency, 0.0 (invisible) … 1.0 (opaque).
  static Future<void> setOpacity(double opacity) =>
      windowManager.setOpacity(opacity);

  /// Prevent the user from closing the window (destructive-flow guard).
  static Future<void> setPreventClose(bool preventClose) =>
      windowManager.setPreventClose(preventClose);

  static Future<void> setSkipTaskbar(bool skip) =>
      windowManager.setSkipTaskbar(skip);

  static Future<bool> isMinimized() => windowManager.isMinimized();
  static Future<bool> isMaximized() => windowManager.isMaximized();
  static Future<bool> isVisible() => windowManager.isVisible();

  static Future<void> setSize(Size size) => windowManager.setSize(size);
  static Future<Size> getSize() => windowManager.getSize();
}

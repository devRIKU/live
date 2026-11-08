import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// VoiceProvider — interface and implementations for Push-to-Talk audio
/// input and Text-to-Speech output (port of `src/adapters/voice.ts`,
/// Milestone 9).
///
/// Rules (from §6, §12.3):
/// - Push-to-talk input and spoken output behind [VoiceProvider].
/// - Full-duplex voice v2 stays a stub in prototype.
/// - Unavailable speech services fail cleanly without crashing or blocking
///   text chat.
///
/// Tauri/browser deviation: the TS build used the browser Web Speech APIs
/// (`SpeechRecognition` for STT, `speechSynthesis` for TTS). Flutter has no
/// cross-platform speech API, so `BrowserVoiceProvider` is ported to
/// `NativeVoiceProvider`, which drives platform code through method /
/// event channels:
///
///   MethodChannel `com.lively.openall/speech`
///     - `startListening` args `{lang: String, continuous: bool,
///         interimResults: bool}` → null
///     - `stopListening` → null
///   EventChannel `com.lively.openall/speech_events`
///     - STT: `{type: 'partial'|'final'|'error', text: String}` and
///       `{type: 'error', error: 'not-allowed' | …}`
///     - TTS: `{type: 'tts_end'}` and `{type: 'tts_error', error: …}`
///   MethodChannel `com.lively.openall/tts`
///     - `speak` args `{text: String, rate: double, pitch: double}` → null
///     - `cancel` → null
///
/// On Windows these hooks can be implemented with the Speech API
/// (`ISpRecognizer` / SAPI `SpVoice`) or WinRT `Windows.Media.SpeechSynthesis`
/// in a Flutter plugin; on macOS with `NSSpeechRecognizer` /
/// `AVSpeechSynthesizer`. Until the plugin registers the channels,
/// [VoicePlatform.nativeVoiceAvailable] should be set to `false` and the
/// mock provider is used.

// ─── Types ──────────────────────────────────────────────────────────────────

/// Current listening/speaking state, for UI binding.
class VoiceState {
  final bool isListening;
  final bool isSpeaking;
  final String? error;
  const VoiceState({
    required this.isListening,
    required this.isSpeaking,
    this.error,
  });
}

/// Receives (interim or final) transcript text.
typedef TranscriptCallback = void Function(String text, bool isFinal);

/// Receives a human-readable voice error.
typedef ErrorCallback = void Function(String error);

abstract class VoiceProvider {
  /// Identifier of the voice provider implementation.
  String get id;

  /// Check if the necessary speech APIs are available in the runtime.
  bool isSupported();

  /// Start recording / listening for speech.
  Future<void> startListening(
    TranscriptCallback onTranscript, [
    ErrorCallback? onError,
  ]);

  /// Stop listening.
  Future<void> stopListening();

  /// Speak text aloud.
  Future<void> speak(
    String text, {
    void Function()? onEnd,
    ErrorCallback? onError,
  });

  /// Stop speaking / cancel active audio output.
  void stopSpeaking();

  /// Current listening state.
  bool isListening();

  /// Current speaking state.
  bool isSpeaking();
}

// ─── Platform hooks ─────────────────────────────────────────────────────────

/// Channel names + availability flag for the native speech plugin.
class VoicePlatform {
  VoicePlatform._();

  static const MethodChannel speech =
      MethodChannel('com.lively.openall/speech');
  static const EventChannel speechEvents =
      EventChannel('com.lively.openall/speech_events');
  static const MethodChannel tts = MethodChannel('com.lively.openall/tts');

  /// Set to `true` by the platform bootstrap once the STT/TTS plugin has
  /// registered the channels above. Default: desktop platforms (the plugin
  /// is expected to exist in the desktop builds).
  static bool nativeVoiceAvailable = false;

  /// Whether a custom channel plugin has registered the channels above.
  /// Off by default: no such plugin ships with this app. The default speech
  /// path on Windows/macOS is [SpeechToTextVoiceProvider].
}

// ─── Native (channel-backed) provider ───────────────────────────────────────

/// Speech-recognition / synthesis backed by the platform plugin.
///
/// Port of `BrowserVoiceProvider`: continuous, interim-result recognition
/// in `en-US`, and markdown-cleaned TTS at rate/pitch 1.0.
class NativeVoiceProvider implements VoiceProvider {
  /// Same wire id as the TS `BrowserVoiceProvider` for settings compat.
  @override
  String get id => 'browser-voice-v1';

  bool _isListening = false;
  bool _isSpeaking = false;
  StreamSubscription<dynamic>? _sttSub;
  StreamSubscription<dynamic>? _ttsSub;

  @override
  bool isSupported() => VoicePlatform.nativeVoiceAvailable;

  @override
  Future<void> startListening(
    TranscriptCallback onTranscript, [
    ErrorCallback? onError,
  ]) async {
    if (!isSupported()) {
      const msg =
          'Speech recognition is not supported in this runtime environment.';
      onError?.call(msg);
      throw Exception(msg);
    }

    if (_isListening) {
      await stopListening();
    }

    // Subscribe before starting so no early events are lost.
    _sttSub = VoicePlatform.speechEvents.receiveBroadcastStream().listen(
      (event) {
        if (event is! Map) return;
        final type = event['type'];
        if (type == 'final') {
          onTranscript('${event['text'] ?? ''}', true);
        } else if (type == 'partial') {
          onTranscript('${event['text'] ?? ''}', false);
        } else if (type == 'error') {
          _isListening = false;
          final code = '${event['error'] ?? 'unknown'}';
          final err = code == 'not-allowed'
              ? 'Microphone access denied by user.'
              : 'Speech recognition error: $code';
          onError?.call(err);
        }
      },
      onError: (Object e) {
        _isListening = false;
        onError?.call('Speech recognition error: $e');
      },
    );

    try {
      await VoicePlatform.speech.invokeMethod<void>('startListening', {
        'lang': 'en-US',
        'continuous': true,
        'interimResults': true,
      });
      _isListening = true;
    } on MissingPluginException catch (e) {
      _isListening = false;
      await _sttSub?.cancel();
      _sttSub = null;
      final msg =
          'Speech recognition plugin is not registered on this platform. ($e)';
      onError?.call(msg);
      throw Exception(msg);
    } catch (e) {
      _isListening = false;
      await _sttSub?.cancel();
      _sttSub = null;
      final msg = e is Exception ? '$e' : e.toString();
      onError?.call(msg);
      rethrow;
    }
  }

  @override
  Future<void> stopListening() async {
    if (_sttSub != null && _isListening) {
      try {
        await VoicePlatform.speech.invokeMethod<void>('stopListening');
      } catch (_) {
        // Ignore stop error
      }
    }
    _isListening = false;
    await _sttSub?.cancel();
    _sttSub = null;
  }

  /// Clean markdown formatting before speaking.
  static final RegExp _codeFence = RegExp(r'```[\s\S]*?```');
  static final RegExp _inlineCode = RegExp(r'`([^`]+)`');
  static final RegExp _markdownLink = RegExp(r'\[([^\]]+)\]\([^\)]+\)');
  static final RegExp _markupChars = RegExp(r'[#*_~>]');

  static String cleanForSpeech(String text) => text
      .replaceAll(_codeFence, ' [code block] ')
      .replaceAll(_inlineCode, r'$1')
      .replaceAll(_markdownLink, r'$1')
      .replaceAll(_markupChars, '')
      .trim();

  @override
  Future<void> speak(
    String text, {
    void Function()? onEnd,
    ErrorCallback? onError,
  }) async {
    if (!VoicePlatform.nativeVoiceAvailable) {
      onError?.call('Speech synthesis not available');
      return;
    }

    stopSpeaking();

    // Clean markdown formatting before speaking
    final cleanText = cleanForSpeech(text);

    if (cleanText.isEmpty) {
      onEnd?.call();
      return;
    }

    // TTS completion events arrive on the shared speech event channel.
    _ttsSub = VoicePlatform.speechEvents.receiveBroadcastStream().listen(
      (event) {
        if (event is! Map) return;
        final type = event['type'];
        if (type == 'tts_end') {
          _isSpeaking = false;
          onEnd?.call();
        } else if (type == 'tts_error') {
          _isSpeaking = false;
          final err = '${event['error'] ?? ''}';
          onError?.call(err.isEmpty ? 'TTS playback failed' : err);
        }
      },
      onError: (Object e) {
        _isSpeaking = false;
        onError?.call('TTS playback failed: $e');
      },
    );

    try {
      await VoicePlatform.tts.invokeMethod<void>('speak', {
        'text': cleanText,
        'rate': 1.0,
        'pitch': 1.0,
      });
      _isSpeaking = true;
    } on MissingPluginException catch (e) {
      _isSpeaking = false;
      await _ttsSub?.cancel();
      _ttsSub = null;
      onError?.call('Speech synthesis plugin is not registered. ($e)');
    } catch (e) {
      _isSpeaking = false;
      await _ttsSub?.cancel();
      _ttsSub = null;
      onError?.call('TTS playback failed: $e');
    }
  }

  @override
  void stopSpeaking() {
    if (VoicePlatform.nativeVoiceAvailable) {
      VoicePlatform.tts.invokeMethod<void>('cancel').catchError((_) {});
    }
    _isSpeaking = false;
    _ttsSub?.cancel();
    _ttsSub = null;
  }

  @override
  bool isListening() => _isListening;

  @override
  bool isSpeaking() => _isSpeaking;
}

// ─── speech_to_text provider ────────────────────────────────────────────────

/// Dictation through the `speech_to_text` plugin (Windows UWP speech
/// recognition, macOS, mobile).
///
/// Honest limits:
/// - The plugin's Windows backend is **beta** upstream ("known issues, not
///   ready for production"), and Windows speech recognition also needs
///   "Online speech recognition" enabled in Settings → Privacy → Speech.
/// - The plugin targets short phrases/commands, not continuous dictation;
///   the OS ends a session after a pause.
/// - It has no speech *output*, so [speak] reports that instead of pretending.
class SpeechToTextVoiceProvider implements VoiceProvider {
  @override
  String get id => 'speech-to-text-v1';

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _initialized = false;
  bool _unavailable = false;
  bool _isListening = false;
  bool _heardFinal = false;
  ErrorCallback? _onError;

  /// Optimistic until `initialize` proves otherwise: availability (permission,
  /// recognizer installed) can only be learned asynchronously.
  @override
  bool isSupported() => !_unavailable;

  @override
  Future<void> startListening(
    TranscriptCallback onTranscript, [
    ErrorCallback? onError,
  ]) async {
    _onError = onError;

    if (!_initialized) {
      final bool ok;
      try {
        ok = await _speech.initialize(
          onError: (e) {
            _isListening = false;
            _onError?.call(_describe(e.errorMsg));
          },
          onStatus: (status) {
            if (status == 'done' || status == 'notListening') {
              // The OS ended the session on its own (a pause). If nothing was
              // recognised, say so — otherwise the UI would wait forever. A
              // user-initiated stop clears `_isListening` first, so it never
              // lands here.
              final endedByOs = _isListening;
              _isListening = false;
              if (endedByOs && !_heardFinal) {
                _onError?.call('No speech was detected. Try again.');
              }
            }
          },
        );
      } catch (e) {
        _unavailable = true;
        throw Exception('Speech recognition could not start: $e');
      }
      if (!ok) {
        _unavailable = true;
        throw Exception(
            'Speech recognition is unavailable. Check that a microphone is connected and '
            'that speech recognition is allowed in Windows privacy settings.');
      }
      _initialized = true;
    }

    if (_isListening) await stopListening();
    _isListening = true;
    _heardFinal = false;
    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) _heardFinal = true;
        onTranscript(result.recognizedWords, result.finalResult);
      },
      localeId: 'en-US',
      listenOptions: stt.SpeechListenOptions(partialResults: true),
    );
  }

  static String _describe(String code) => code.toLowerCase().contains('permission')
      ? 'Microphone access denied.'
      : 'Speech recognition error: $code';

  @override
  Future<void> stopListening() async {
    _isListening = false;
    try {
      await _speech.stop();
    } catch (_) {
      // Already stopped.
    }
  }

  @override
  Future<void> speak(
    String text, {
    void Function()? onEnd,
    ErrorCallback? onError,
  }) async {
    onError?.call('Spoken replies are not available in this build.');
  }

  @override
  void stopSpeaking() {}

  @override
  bool isListening() => _isListening;

  @override
  bool isSpeaking() => false;
}

// ─── Unavailable provider ───────────────────────────────────────────────────

/// Used on platforms with no speech backend: it fails clearly instead of
/// inventing a transcript.
class UnavailableVoiceProvider implements VoiceProvider {
  @override
  String get id => 'unavailable-voice';

  @override
  bool isSupported() => false;

  @override
  Future<void> startListening(
    TranscriptCallback onTranscript, [
    ErrorCallback? onError,
  ]) async {
    const msg = 'Speech recognition is not available on this platform.';
    onError?.call(msg);
    throw Exception(msg);
  }

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> speak(
    String text, {
    void Function()? onEnd,
    ErrorCallback? onError,
  }) async {
    onError?.call('Spoken replies are not available on this platform.');
  }

  @override
  void stopSpeaking() {}

  @override
  bool isListening() => false;

  @override
  bool isSpeaking() => false;
}

// ─── Mock provider ──────────────────────────────────────────────────────────

/// For headless environments, automated tests, or offline tests. It emits a
/// fixed fake transcript, so it is never selected automatically.
class MockVoiceProvider implements VoiceProvider {
  @override
  String get id => 'mock-voice-v1';

  bool _isListening = false;
  bool _isSpeaking = false;
  Timer? _listenTimer;
  Timer? _speakTimer;

  @override
  bool isSupported() => true;

  @override
  Future<void> startListening(
    TranscriptCallback onTranscript, [
    ErrorCallback? onError,
  ]) async {
    _isListening = true;
    _listenTimer = Timer(const Duration(milliseconds: 50), () {
      if (_isListening) {
        onTranscript('Simulated spoken command from user', true);
      }
    });
  }

  @override
  Future<void> stopListening() async {
    _isListening = false;
    _listenTimer?.cancel();
    _listenTimer = null;
  }

  @override
  Future<void> speak(
    String text, {
    void Function()? onEnd,
    ErrorCallback? onError,
  }) async {
    _isSpeaking = true;
    _speakTimer = Timer(const Duration(milliseconds: 50), () {
      _isSpeaking = false;
      onEnd?.call();
    });
  }

  @override
  void stopSpeaking() {
    _isSpeaking = false;
    _speakTimer?.cancel();
    _speakTimer = null;
  }

  @override
  bool isListening() => _isListening;

  @override
  bool isSpeaking() => _isSpeaking;
}

// ─── Full-duplex stub ───────────────────────────────────────────────────────

/// Stub for full-duplex conversational voice (Voice v2).
///
/// Reserved for WebSocket streaming with remote PersonaPlex / Kokoro GPU
/// nodes.
class FullDuplexVoiceV2Stub implements VoiceProvider {
  @override
  String get id => 'fullduplex-v2-stub';

  @override
  bool isSupported() {
    // Stub indicates future WebSocket support
    return false;
  }

  @override
  Future<void> startListening(
    TranscriptCallback onTranscript, [
    ErrorCallback? onError,
  ]) async {
    onError?.call(
        'Full-duplex Voice v2 is a prototype stub. Connect a PersonaPlex/VoiceChat WebSocket endpoint to activate.');
  }

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> speak(
    String text, {
    void Function()? onEnd,
    ErrorCallback? onError,
  }) async {
    onError?.call('Full-duplex Voice v2 is not active.');
  }

  @override
  void stopSpeaking() {}

  @override
  bool isListening() => false;

  @override
  bool isSpeaking() => false;
}

// ─── Singleton ──────────────────────────────────────────────────────────────

VoiceProvider? _defaultVoiceProvider;

/// Return the default singleton voice provider instance.
///
/// The TS build picked the browser provider when Web Speech APIs existed.
/// The Dart port picks, in order: a custom channel plugin if one registered
/// itself, the `speech_to_text` plugin on Windows/macOS, otherwise a provider
/// that reports speech as unavailable. The fake-transcript mock is never a
/// default — install it explicitly with [setVoiceProvider] for tests/demos.
VoiceProvider getVoiceProvider() {
  if (_defaultVoiceProvider == null) {
    if (VoicePlatform.nativeVoiceAvailable) {
      _defaultVoiceProvider = NativeVoiceProvider();
    } else if (Platform.isWindows || Platform.isMacOS) {
      _defaultVoiceProvider = SpeechToTextVoiceProvider();
    } else {
      _defaultVoiceProvider = UnavailableVoiceProvider();
    }
  }
  return _defaultVoiceProvider!;
}

/// Replace the singleton (tests / custom providers).
void setVoiceProvider(VoiceProvider? provider) {
  _defaultVoiceProvider = provider;
}

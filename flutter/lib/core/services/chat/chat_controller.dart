/// chatStreamController — core streaming chat orchestration.
/// Port of `src/chat/useChatStream.ts` as a Riverpod controller.
///
/// Sends messages through the transport, fits the conversation to the model's
/// context window, handles bounded failover, and reports usage, tool calls
/// and errors.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import 'chat_attachments.dart';
import 'chat_failover.dart';
import 'chat_tokens.dart';
import 'chat_transport.dart';
import 'model_params.dart';
import '../providers_registry.dart';

/// The context state of the request that just ran.
class ContextSnapshot {
  final int used;
  final int limit;
  final int reserved;
  final int remaining;
  final double ratio;
  final ContextLevel level;
  /// Messages dropped to fit the window.
  final int dropped;
  const ContextSnapshot({
    required this.used,
    required this.limit,
    required this.reserved,
    required this.remaining,
    required this.ratio,
    required this.level,
    required this.dropped,
  });
}

class ChatStreamState {
  final bool isStreaming;
  final String? error;
  final FailoverMeta? lastMeta;
  /// True while a request is in flight (streaming or awaiting failover).
  final bool pending;
  /// Provider-reported usage for the last completed request.
  final StreamUsage? usage;
  /// Estimated context state for the last request.
  final ContextSnapshot? context;
  /// Model that produced the last request (or the selected one).
  final String modelId;
  /// True when the last error was an authentication failure (401/403).
  final bool authError;
  const ChatStreamState({
    this.isStreaming = false,
    this.error,
    this.lastMeta,
    this.pending = false,
    this.usage,
    this.context,
    this.modelId = 'auto',
    this.authError = false,
  });
}

class ChatStreamCallbacks {
  final void Function(String token) onToken;
  final void Function(StreamResult result, FailoverMeta meta) onComplete;
  final void Function(String message, ChatStreamState state) onError;
  const ChatStreamCallbacks({
    required this.onToken,
    required this.onComplete,
    required this.onError,
  });
}

/// Minimum room for a reply before the turn is considered unsendable.
const int _minOutputTokens = 256;
/// Safety margin subtracted from the window for chat-format overhead.
const int _windowSafety = 64;

final chatStreamProvider =
    StateNotifierProvider<ChatStreamController, ChatStreamState>((ref) {
  return ChatStreamController();
});

/// Replace image parts with a text marker. Used when failover lands on a
/// text-only model: dropping the image is better than a hard 400, and the
/// marker tells the model why it cannot see the picture.
List<ChatMessage> _stripImages(List<ChatMessage> messages) => [
      for (final message in messages)
        if (message.content.parts == null)
          message
        else
          ChatMessage(
            role: message.role,
            name: message.name,
            toolCallId: message.toolCallId,
            toolCalls: message.toolCalls,
            content: ChatContent.parts([
              for (final part in message.content.parts!)
                part.type == 'image_url'
                    ? const ChatContentPart.text(
                        '[image omitted: this model is text-only]')
                    : part,
            ]),
          ),
    ];

/// The token estimator's view of a wire message.
({String role, Object? content}) _estimate(ChatMessage m) => (
      role: m.role,
      content: m.content.text ?? m.content.parts?.map((p) => p.toJson()).toList(),
    );

/// Rebuild the kept wire messages: the fitter dropped entries from the front,
/// so the kept prefix of the original list starts after that many messages.
List<ChatMessage> _keptMessages(List<ChatMessage> all, FitResult<({String role, Object? content})> fitted) {
  final droppedCount = (all.length - fitted.messages.length).clamp(0, all.length);
  return all.sublist(droppedCount);
}

int _minInt(int a, int b) => a < b ? a : b;

class ChatStreamController extends StateNotifier<ChatStreamState> {
  ChatStreamController() : super(const ChatStreamState());

  CancellationToken? _cancelToken;

  /// Send one turn. `userContent` plus optional attachments; a continuation
  /// after a tool result passes an explicit history and no new user text.
  Future<void> sendMessage({
    required String selectedProviderId,
    String? selectedModelId,
    required bool crossProviderFailover,
    required List<Message> history,
    String? systemPrompt,
    required ModelParams params,
    List<MessageAttachment> attachments = const [],
    List<ToolSpec>? tools,
    required ChatStreamCallbacks callbacks,
    String userContent = '',
    List<MessageAttachment>? overrideAttachments,
    List<ChatMessage>? wireHistoryOverride,
  }) async {
    // Deduplication: ignore sends while a request is already in flight.
    if (state.pending) return;

    final primary = providers
        .firstWhere((p) => p.id == selectedProviderId, orElse: () => providers.first);
    final turnAttachments = overrideAttachments ?? attachments;

    state = const ChatStreamState(isStreaming: true, pending: true, modelId: 'auto');
    ContextSnapshot? snapshot;

    // The whole conversation, including the turn being sent. Stored messages
    // may lag the just-added user turn, so it is appended here.
    final wireHistory = wireHistoryOverride ??
        [
          for (final m in history)
            ChatMessage(
              role: m.role,
              // An assistant turn that only requested a tool has no prose.
              // Send a short marker instead of an empty content string,
              // which some providers reject.
              content: toWireContent(
                m.content.trim().isNotEmpty
                    ? m.content.trim()
                    : (m.role == 'assistant' ? '[tool call requested]' : ''),
                m.attachments ?? const [],
              ),
            ),
        ];

    if (userContent.trim().isNotEmpty || turnAttachments.isNotEmpty) {
      wireHistory.add(ChatMessage(
        role: 'user',
        content: toWireContent(userContent, turnAttachments),
      ));
    }

    try {
      final outcome = await failover<StreamResult>(
        FailoverOptions(
          primary: primary,
          allowCrossProviderFailover: crossProviderFailover,
        ),
        (provider, signal, onProgress) async {
          // A fallback provider has its own model and its own window.
          final modelId = provider.id == primary.id
              ? (selectedModelId ?? provider.model)
              : provider.model;
          final model = getModel(provider, modelId);
          final limit = modelContextLimit(provider, modelId);

          // 1. Drop the oldest turns until the prompt itself fits.
          final estimatable = [for (final m in wireHistory) _estimate(m)];
          final fitted = fitMessagesToContext(
            estimatable,
            limit: limit,
            maxOutput: 0,
            systemPrompt: systemPrompt,
          );

          // 2. Give the reply whatever is left, capped by the model's own
          //    output limit and the user's setting.
          final available = limit - fitted.tokens - _windowSafety;
          if (available < _minOutputTokens) {
            // TransportError is "safe to retry": a provider with a larger
            // window may still be able to answer.
            throw TransportError(
              'Conversation is too long for ${model.label} ($limit tokens). '
              'Start a new conversation or remove attachments.',
            );
          }
          final maxTokens = [
            _minOutputTokens,
            params.maxTokens,
            model.maxOutput,
            available,
          ].reduce(_minInt);

          final budget =
              contextBudget(limit: limit, used: fitted.tokens, maxOutput: maxTokens);
          snapshot = ContextSnapshot(
            used: fitted.tokens,
            limit: budget.limit,
            reserved: budget.reserved,
            remaining: budget.remaining,
            ratio: budget.ratio,
            level: budget.level,
            dropped: fitted.dropped,
          );

          final apiMessages = <ChatMessage>[
            if (systemPrompt != null && systemPrompt.trim().isNotEmpty)
              ChatMessage(role: 'system', content: ChatContent.string(systemPrompt.trim())),
            ...(model.vision
                ? _keptMessages(wireHistory, fitted)
                : _stripImages(_keptMessages(wireHistory, fitted))),
          ];

          // Combine the failover cancellation with the user's cancel button.
          final controller = CancellationToken();
          _cancelToken = controller;
          signal.onCancel(() => controller.cancel());

          try {
            return await streamChat(StreamOptions(
              provider: provider,
              model: modelId,
              messages: apiMessages,
              signal: controller,
              onToken: callbacks.onToken,
              params: WireParams(
                temperature: params.temperature,
                topP: params.topP,
                maxTokens: maxTokens,
              ),
              tools: tools != null && tools.isNotEmpty ? tools : null,
              onProgress: onProgress,
            ));
          } finally {
            _cancelToken = null;
          }
        },
      );

      final meta = outcome.meta;
      final result = outcome.data;

      // Prefer provider-reported prompt tokens over the local estimate: the
      // estimate is a safety bound, not a measurement.
      var nextSnapshot = snapshot;
      final promptTokens = result.usage?.promptTokens;
      if (promptTokens != null && nextSnapshot != null) {
        final measured = contextBudget(
          limit: nextSnapshot.limit,
          used: promptTokens,
          maxOutput: nextSnapshot.reserved,
        );
        nextSnapshot = ContextSnapshot(
          used: measured.used,
          limit: nextSnapshot.limit,
          reserved: nextSnapshot.reserved,
          remaining: measured.remaining,
          ratio: measured.ratio,
          level: measured.level,
          dropped: nextSnapshot.dropped,
        );
      }

      state = ChatStreamState(
        isStreaming: false,
        error: null,
        lastMeta: meta,
        pending: false,
        usage: result.usage,
        context: nextSnapshot,
        modelId: meta.answeredBy.id == primary.id
            ? (selectedModelId ?? primary.model)
            : meta.answeredBy.model,
        authError: false,
      );
      callbacks.onComplete(result, meta);
    } catch (err) {
      final message = redactSecrets(err);
      final failure = ChatStreamState(
        isStreaming: false,
        error: message,
        lastMeta: null,
        pending: false,
        usage: null,
        context: snapshot,
        modelId: selectedModelId ?? primary.model,
        authError: isAuthError(err),
      );
      state = failure;
      callbacks.onError(message, failure);
    } finally {
      _cancelToken = null;
    }
  }

  void cancel() => _cancelToken?.cancel();
}
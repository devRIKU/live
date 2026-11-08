/// The shell — 3-column layout: sidebar (244px) | conversation column
/// (720px) | composer at the column's foot. Port of `src/app/App.tsx` for
/// the milestone-M1..M3 chat path; milestone surfaces hang off it as they
/// are ported.
library;

import 'dart:convert' show jsonDecode;
import 'dart:io' show File;

import 'package:file_selector/file_selector.dart' as fs;
import 'package:fluent_ui/fluent_ui.dart' as f;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, MissingPluginException, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/models.dart';
import '../../core/services/storage_adapter.dart' show StorageAdapter;
import '../../core/services/adapters/local_mcp_adapter.dart';
import '../../core/services/adapters/mcp_adapter.dart';
import '../../core/services/adapters/skills.dart';
import '../../core/services/adapters/web_connectors.dart'
    show
        ConnectorType,
        WebConnector,
        executeWebFetch,
        executeWebSearch;
import '../../core/services/adapters/voice_adapter.dart'
    show VoiceProvider, getVoiceProvider;
import '../../core/services/canvas/artifact_detector.dart';
import '../../core/services/chat/chat_attachments.dart';
import '../../core/services/chat/chat_controller.dart';
import '../../core/services/chat/chat_failover.dart' show FailoverMeta;
import '../../core/services/chat/chat_tokens.dart';
import '../../core/services/chat/chat_transport.dart' show StreamResult;
import '../../core/services/chat/model_params.dart'
    show clampParamsToModel, loadSelectedModel, saveSelectedModel;
import '../../core/services/providers_registry.dart';
import '../../core/services/chat/thread_controller.dart';
import '../../core/services/tools/native_tools.dart';
import '../../core/services/tools/tool_call_detector.dart';
import '../../core/state/connectors_provider.dart';
import '../../core/state/settings_controller.dart';
import '../../core/theme/lively_tokens.dart';
import '../../shared/utils.dart' show generateId;
import '../genui/actions.dart'
    show OpenUIActionEvent, actionToUserMessage, isSafeUrl;
import '../genui/prompt.dart' show buildOpenUIPrompt;
import '../settings/settings_dialog.dart';
import '../surfaces/account_panel.dart';
import '../surfaces/artifact_pane.dart';
import '../surfaces/connectors_panel.dart';
import '../surfaces/customize_overlay.dart'
    show CustomizeOverlay, customInstructionsKey, personalities;
import '../surfaces/model_overlay.dart';
import '../surfaces/permission_card.dart';
import '../surfaces/research_overlay.dart';
import '../surfaces/terminal_dock.dart';
import '../surfaces/tools_overlay.dart';
import '../surfaces/voice_dock.dart';
import 'composer.dart' show Composer, ComposerTool, VoiceState;
import 'message_turn.dart' show MessageTurn;
import 'model_bar.dart'
    show ContextMeterState, ModelBar, ModelBarOption, ProviderStatus;
import 'sidebar.dart';

Brightness _bOf(BuildContext context) => f.FluentTheme.of(context).brightness;

/// The full-surface overlays that share the frame above the composer.
enum _Overlay { account, customize, model, tools, connectors }

const List<String> _suggestions = [
  'Compare the providers and give me a form to pick one.',
  'Plan a day in San Francisco.',
  'Draft a release note for the canvas pane.',
];

/// The chips shown in the composer's tool popover. Port of the `TOOLS`
/// constant in App.tsx.
const List<ComposerTool> _composerTools = [
  ComposerTool(
      id: 'image',
      label: 'Create an image',
      hint: 'Generate an image from a text prompt.',
      tint: 'green',
      icon: 'image'),
  ComposerTool(
      id: 'write',
      label: 'Write or edit',
      hint: 'Draft, edit and refine documents.',
      tint: 'orange',
      icon: 'pen'),
  ComposerTool(
      id: 'web',
      label: 'Search the web',
      hint: 'Look up current information on the web.',
      tint: 'blue',
      icon: 'globe'),
  ComposerTool(
      id: 'code',
      label: 'Run code',
      hint: 'Execute Python in a sandboxed environment.',
      icon: 'code'),
  ComposerTool(
      id: 'research',
      label: 'Deep research',
      hint: 'Multi-step research with cited sources.',
      icon: 'globe'),
  ComposerTool(
      id: 'canvas',
      label: 'Canvas',
      hint: 'A persistent document beside the chat.',
      icon: 'pen'),
];

/// The system prompt. The OpenUI Lang spec is always included so the model
/// can answer with genuine UI; bundled skills and durable memory facts fold
/// in when present. Port of the `systemPrompt` useMemo in App.tsx.
Future<String> _buildSystemPrompt({
  required List<SkillMeta> skills,
  required List<Fact> facts,
  StorageAdapter? storage,
}) async {
  final sections = <String>[buildOpenUIPrompt()];
  final skillsSection = buildSkillsPrompt(skills);
  if (skillsSection.isNotEmpty) sections.add(skillsSection);
  if (facts.isNotEmpty) {
    final factLines = [for (final f in facts) '- [${f.category}] ${f.fact}'];
    sections.add('## User Memory Facts (recall when relevant):\n'
        '${factLines.join('\n')}');
  }
  // Fold in custom instructions saved via the Customize overlay.
  if (storage != null) {
    try {
      final value = await storage.getSetting<Map<String, dynamic>>(customInstructionsKey);
      if (value != null) {
        final about = (value['about'] ?? '').toString().trim();
        final respond = (value['respond'] ?? '').toString().trim();
        final personality = value['personality'];
        final persona = (personality is int &&
                personality >= 0 &&
                personality < personalities.length)
            ? personalities[personality]
            : null;
        final lines = <String>[];
        if (persona != null) lines.add('Personality: $persona');
        if (about.isNotEmpty) lines.add('About the user: $about');
        if (respond.isNotEmpty) lines.add('How to respond: $respond');
        if (lines.isNotEmpty) {
          sections.add('## Custom Instructions\n${lines.join('\n')}');
        }
      }
    } catch (_) {
      // Settings may not be loaded yet; skip custom instructions this turn.
    }
  }
  return sections.join('\n\n');
}

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  // ── Local UI state ──
  String _selectedProviderId = providers.first.id;
  String? _selectedModelId;
  int _effort = 1;
  final Set<String> _enabledTools = <String>{'web'};

  /// Bundled skills, loaded once from the asset bundle (`SKILL.md` files
  /// under `assets/skills/*/`, mirroring the Vite glob in App.tsx).
  List<SkillMeta> _skills = const [];

  /// Tool calls awaiting a user decision (the approval queue).
  ToolCall? _pendingCall;
  List<ToolCall> _callQueue = const [];

  /// The artifact currently open beside the conversation.
  Artifact? _openArtifact;

  /// Overlay surfaces (M8–M13).
  String? _researchQuery;
  VoicePhase _voicePhase = VoicePhase.idle;
  String? _voiceError;
  bool _terminalOpen = false;
  _Overlay? _overlay;

  /// Tools advertised by the connected remote MCP servers, refreshed
  /// asynchronously (`tools/list` is a network call; `_nativeDefs` is sync).
  List<McpServerTools> _mcpServers = const [];

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<MessageAttachment> _attachments = const [];
  final StringBuffer _streamingText = StringBuffer();
  bool _streamingActive = false;

  @override
  void initState() {
    super.initState();
    _loadSkills();
    _refreshMcpTools();
    // Restore the model chosen last session, and point the params at it.
    final restored = loadSelectedModel(_provider);
    _selectedModelId = restored;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(settingsControllerProvider.notifier)
          .selectModel(_provider, restored, getModel(_provider, restored).label);
    });
    // Durable facts feed the system prompt; refresh on arrival.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(settingsControllerProvider.notifier).refreshFacts();
    });
  }

  Future<void> _loadSkills() async {
    try {
      // `AssetManifest.json` is stable across recent Flutter versions; filter
      // the bundled SKILL.md paths out of it so new skills need no code
      // change — only a pubspec assets entry.
      final manifest = await rootBundle.loadString('AssetManifest.json');
      final decoded = jsonDecode(manifest);
      if (decoded is! Map) return;
      final pattern = RegExp(r'assets/skills/[^/]+/SKILL\.md$');
      final paths = decoded.keys
          .whereType<String>()
          .where(pattern.hasMatch)
          .toList()
        ..sort();
      final skills = <SkillMeta>[];
      for (final path in paths) {
        final text = await rootBundle.loadString(path);
        final id = path.split('/').reversed.toList()[1];
        skills.add(loadSkill(id, text));
      }
      if (mounted) setState(() => _skills = List.unmodifiable(skills));
    } catch (_) {
      // A missing manifest must never break the shell; skills are optional.
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Derived ──

  LlmProvider get _provider =>
      providers.firstWhere((p) => p.id == _selectedProviderId, orElse: () => providers.first);

  ModelOption get _model => getModel(_provider, _selectedModelId);

  List<ProviderStatus> _providerStatuses() => [
        for (final p in providers)
          ProviderStatus(
            id: p.id,
            name: p.name,
            model: p.model,
            state: switch (p.state) {
              ProviderState.rateLimited => 'rate-limited',
              ProviderState.degraded => 'degraded',
              ProviderState.down => 'down',
              _ => 'available',
            },
            models: [
              for (final m in p.models) ModelBarOption(id: m.id, label: m.label),
            ],
          ),
      ];

  void _setInput(String value) {
    _input.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  // ── Send / stop ──

  void _onSubmit() {
    final text = _input.text.trim();
    _sendText(text, attachments: _attachments);
  }

  /// The function list offered to the model for this turn. Built-ins are
  /// always offered; deep research is only offered when the research chip is
  /// not already routing the whole turn to its surface.
  List<NativeToolDefinition> _nativeDefs() {
    return buildNativeTools(
      BuildNativeToolsOptions(
        builtins: _enabledTools.contains('research')
            ? const [NativeBuiltinTool.saveMemory]
            : const [
                NativeBuiltinTool.saveMemory,
                NativeBuiltinTool.deepResearch,
              ],
        mcpServers: _mcpServers,
        // Only connectors the app can actually execute are offered: search
        // and page-reader. REST connectors have no call semantics here and MCP
        // connectors contribute through `mcpServers` instead; offering a tool
        // that then answers "unknown tool" would only confuse the model.
        connectors: [
          for (final c in ref.read(webConnectorsProvider))
            if (c.enabled &&
                (c.type == ConnectorType.search || c.type == ConnectorType.fetch))
              c,
        ],
      ),
    );
  }

  /// Ask every connected remote MCP server for its tools. A server that
  /// fails to answer is skipped rather than blocking the others — its tools
  /// are simply not offered this turn. Local stdio servers are spawned per
  /// call and cannot be listed without spawning, so they are not advertised.
  Future<void> _refreshMcpTools() async {
    final servers = <McpServerTools>[];
    final names = {for (final c in ref.read(webConnectorsProvider)) c.id: c.name};
    for (final id in mcpClient.connectedServerIds) {
      try {
        final tools = await mcpClient.listTools(id);
        if (tools.isNotEmpty) {
          servers.add(McpServerTools(
              serverId: id, serverName: names[id] ?? id, tools: tools));
        }
      } catch (_) {
        // Unreachable server: leave its tools out.
      }
    }
    if (mounted) setState(() => _mcpServers = List.unmodifiable(servers));
  }

  ProviderUsage? _usageOf(StreamUsage? usage) => usage == null
      ? null
      : ProviderUsage(
          promptTokens: usage.promptTokens,
          completionTokens: usage.completionTokens,
          totalTokens: usage.totalTokens,
        );

  /// Provider tag for the finished turn — which provider actually answered,
  /// whether failover was used, and the reported token usage.
  ProviderInfo _providerInfoOf(FailoverMeta meta, StreamUsage? usage) {
    final modelId =
        meta.answeredBy.id == _provider.id ? _model.id : meta.answeredBy.model;
    return ProviderInfo(
      providerId: meta.answeredBy.id,
      model: modelId,
      fallbackUsed: meta.usedFallback,
      usage: _usageOf(usage),
    );
  }

  ChatStreamCallbacks _turnCallbacks() {
    return ChatStreamCallbacks(
      onToken: (token) {
        _streamingText.write(token);
        if (mounted) setState(() {});
      },
      onComplete: (result, meta) {
        _completeAssistantTurn(result, meta, defs: _nativeDefs());
      },
      onError: (message, state) {
        _finishAssistantMessage(
          '⚠ $message',
          providerId: _provider.id,
          modelId: _model.id,
          fallbackUsed: false,
        );
      },
    );
  }

  /// One chat turn. [text] may be a manual entry or a genui action's
  /// follow-up.
  Future<void> _sendText(String text, {List<MessageAttachment> attachments = const []}) async {
    // Deep research is a full surface, not a chat reply: the query opens the
    // overlay and the bounded pipeline runs there.
    if (_enabledTools.contains('research')) {
      if (text.isEmpty) return;
      setState(() {
        _researchQuery = text;
        _overlay = null;
        _setInput('');
      });
      return;
    }

    if (text.isEmpty && attachments.isEmpty) return;
    if (_streamingActive) return;

    final manager = ref.read(threadManagerProvider.notifier);
    if (ref.read(threadManagerProvider).activeThread == null) {
      manager.createThread();
    }
    final threadId = ref.read(threadManagerProvider).activeThread!.id;
    final history = List<Message>.of(
        ref.read(threadManagerProvider).activeThread!.messages);

    manager.addMessageDetailed(threadId, 'user', text, attachments: attachments);

    // Native tool specs are offered only to models that support tools.
    final modelId = _selectedModelId ?? _model.id;
    final toolsForModel =
        modelSupportsTools(_provider, modelId) ? toolSpecs(_nativeDefs()) : null;

    setState(() {
      _attachments = const [];
      _setInput('');
      _streamingText.clear();
      _streamingActive = true;
    });

    ref.read(chatStreamProvider.notifier).sendMessage(
          selectedProviderId: _selectedProviderId,
          selectedModelId: _selectedModelId,
          crossProviderFailover: true,
          history: history,
          systemPrompt: await _buildSystemPrompt(
            skills: _skills,
            facts: ref.read(settingsControllerProvider).facts,
            storage: ref.read(settingsControllerProvider.notifier).storage,
          ),
          params: clampParamsToModel(
              ref.read(settingsControllerProvider).params, _provider, modelId),
          attachments: attachments,
          tools: toolsForModel,
          userContent: text,
          callbacks: _turnCallbacks(),
        );
  }

  void _onStop() => ref.read(chatStreamProvider.notifier).cancel();

  void _toggleTool(String id) {
    final willEnable = !_enabledTools.contains(id);
    if (willEnable && id == 'image') {
      if (_input.text.isEmpty) _setInput('Generate an image of ');
      setState(() {
        _selectedProviderId = 'google';
        _selectedModelId = 'gemini-3.1-flash-lite-image';
      });
      saveSelectedModel('google', 'gemini-3.1-flash-lite-image');
      _showToast('Switched to Gemini 3.1 Flash Lite Image');
    }
    setState(() {
      if (willEnable) {
        _enabledTools.add(id);
      } else {
        _enabledTools.remove(id);
      }
    });
  }

  /// A generated component asked for something structured.
  void _handleAction(OpenUIActionEvent event) {
    if (event.type == 'open_url') {
      final url = event.params['url']?.toString() ?? '';
      if (isSafeUrl(url)) {
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      return;
    }
    final followUp = actionToUserMessage(event);
    if (followUp != null && !_streamingActive) {
      _sendText(followUp);
    }
  }

  /// Dictation. The microphone cycles through its states and the transcript
  /// lands in the composer rather than being sent on its own. Port of
  /// `handleVoice` in App.tsx.
  Future<void> _toggleVoice() async {
    setState(() => _voiceError = null);
    final VoiceProvider provider = getVoiceProvider();

    if (_voicePhase != VoicePhase.idle) {
      try {
        await provider.stopListening();
      } catch (_) {
        // Already stopped.
      }
      if (mounted) setState(() => _voicePhase = VoicePhase.idle);
      return;
    }

    // The dock is hidden while idle, so a failure is also toasted: it would
    // otherwise be invisible.
    void fail(String message) {
      if (!mounted) return;
      setState(() {
        _voiceError = message;
        _voicePhase = VoicePhase.idle;
      });
      _showToast(message);
    }

    if (!provider.isSupported()) {
      fail('Speech recognition is not available here. Type instead.');
      return;
    }

    setState(() => _voicePhase = VoicePhase.listening);
    try {
      await provider.startListening(
        (text, isFinal) {
          if (!isFinal || !mounted) return;
          setState(() => _voicePhase = VoicePhase.processing);
          final current = _input.text;
          _setInput(current.isEmpty ? text : '$current $text');
          Future.delayed(const Duration(milliseconds: 400), () {
            if (mounted) setState(() => _voicePhase = VoicePhase.idle);
          });
        },
        fail,
      );
    } on MissingPluginException {
      // The platform speech plugin is not part of this build.
      fail('Speech recognition is not installed in this build. Type instead.');
    } catch (e) {
      fail('$e'.replaceFirst('Exception: ', ''));
    }
  }

  /// Composer-facing voice state for the current phase.
  VoiceState get _composerVoiceState => switch (_voicePhase) {
        VoicePhase.idle => VoiceState.idle,
        VoicePhase.listening => VoiceState.listening,
        VoicePhase.processing => VoiceState.processing,
        VoicePhase.speaking => VoiceState.speaking,
      };

  void _finishAssistantMessage(
    String content, {
    required String providerId,
    required String modelId,
    required bool fallbackUsed,
  }) {
    final manager = ref.read(threadManagerProvider.notifier);
    final thread = ref.read(threadManagerProvider).activeThread;
    if (mounted) {
      setState(() {
        _streamingActive = false;
        _streamingText.clear();
      });
    }
    if (thread == null) return;
    manager.addMessageDetailed(thread.id, 'assistant', content);
    manager.updateLastAssistantMessage(
      thread.id,
      content,
      providerInfo: ProviderInfo(
        providerId: providerId,
        model: modelId,
        fallbackUsed: fallbackUsed,
      ),
    );
  }

  /// The turn completed. Two calling conventions are supported: the text
  /// protocol some models still prefer, and native function calls. Both land
  /// in the same approval queue; artifacts open beside the conversation.
  void _completeAssistantTurn(
    StreamResult result,
    FailoverMeta meta, {
    required List<NativeToolDefinition> defs,
  }) {
    final info = _providerInfoOf(meta, result.usage);
    if (mounted) {
      setState(() {
        _streamingActive = false;
        _streamingText.clear();
      });
    }
    final thread = ref.read(threadManagerProvider).activeThread;
    if (thread == null) return;
    final manager = ref.read(threadManagerProvider.notifier);

    final detection = detectToolCalls(result.text);
    final preambleRaw = detection.cleanText;
    final nativeCalls = toApprovalCalls(defs, [
      for (final c in result.toolCalls)
        ProviderToolCall(id: c.id, name: c.name, arguments: c.arguments),
    ]);
    final allCalls = [
      for (final parsedToolCall in detection.calls) parsedToolCall.call,
      ...nativeCalls,
    ];

    if (allCalls.isNotEmpty) {
      // A native call carries no prose. Give the turn a readable line so the
      // transcript never shows an empty assistant bubble once the card is
      // resolved; a model-authored preamble is kept as-is.
      final preamble = preambleRaw.trim().isNotEmpty
          ? preambleRaw.trim()
          : 'Requested permission to use '
              '${[for (final c in allCalls) '`${c.name}`'].join(', ')}.';
      manager.addMessageDetailed(thread.id, 'assistant', preamble);
      manager.updateLastAssistantMessage(thread.id, preamble, providerInfo: info);
      setState(() {
        _callQueue = allCalls;
        _pendingCall = allCalls.first;
      });
      return;
    }

    manager.addMessageDetailed(thread.id, 'assistant', result.text);
    manager.updateLastAssistantMessage(thread.id, result.text, providerInfo: info);

    final found = detectArtifacts(result.text);
    if (found.isNotEmpty && mounted) setState(() => _openArtifact = found.first);
  }

  /// Run a tool the user just allowed. The result goes back into the
  /// conversation as a user turn so the model can continue.
  Future<String> _executeToolCall(ToolCall call) async {
    // Built-in: write a durable fact the user asked the assistant to keep.
    if (call.name == 'memory:save') {
      final fact = '${call.args['fact'] ?? ''}'.trim();
      final rawCategory = '${call.args['category'] ?? 'general'}'.trim();
      final category = rawCategory.isEmpty ? 'general' : rawCategory;
      if (fact.isEmpty) return 'Nothing was saved: the fact was empty.';
      await chatStorage.saveFact(Fact(
        id: generateId(),
        fact: fact,
        category: category,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      await ref.read(settingsControllerProvider.notifier).refreshFacts();
      return 'Saved to memory ($category): $fact';
    }

    // Built-in: open the research surface. The tool call is the trigger; the
    // surface runs the bounded Search → Extract → Map → Reduce job.
    if (call.name == 'research:start') {
      final query = '${call.args['query'] ?? ''}'.trim();
      if (query.isEmpty) return 'No research query was provided.';
      if (mounted) {
        setState(() {
          _researchQuery = query;
          _overlay = null;
        });
      }
      return 'Opened the research surface for: $query';
    }

    if (call.name.startsWith('connector:')) return _executeConnectorCall(call);

    if (!call.name.startsWith('mcp:')) return 'Unknown tool "${call.name}".';
    final parts = call.name.split(':');
    if (parts.length < 3 || parts[1].isEmpty || parts[2].isEmpty) {
      return 'Invalid MCP tool name "${call.name}".';
    }
    final serverId = parts[1];
    final toolName = parts[2];

    final local = localMcpClient.getServer(serverId);
    if (local != null) {
      final result =
          await localMcpClient.callLocalTool(serverId, toolName, call.args, call.targetPath);
      return result.ok ? (result.output ?? '(no output)') : 'Local MCP error: ${result.error}';
    }
    final result = await mcpClient.callTool(serverId, toolName, call.args);
    return result.ok ? (result.output ?? '(no output)') : 'Tool error: ${result.error}';
  }

  /// Run a web-connector tool (`connector:<id>:<tool>`). Search and page-reader
  /// connectors go through the backend's `/api/connectors/*` routes; other
  /// types are never offered to the model, so reaching one here is an error.
  Future<String> _executeConnectorCall(ToolCall call) async {
    final parts = call.name.split(':');
    if (parts.length < 3) return 'Invalid connector tool name "${call.name}".';
    final connectors = ref.read(webConnectorsProvider);
    WebConnector? connector;
    for (final c in connectors) {
      if (c.id == parts[1]) connector = c;
    }
    if (connector == null) return 'Connector "${parts[1]}" is not configured.';
    if (!connector.enabled) return 'Connector "${connector.name}" is disabled.';

    switch (connector.type) {
      case ConnectorType.search:
        final query = '${call.args['query'] ?? ''}'.trim();
        if (query.isEmpty) return 'No search query was provided.';
        final countArg = call.args['count'];
        final count = countArg is num ? countArg.toInt().clamp(1, 5) : 3;
        final out = await executeWebSearch(query, count: count);
        if (!out.ok) return 'Search failed: ${out.error}';
        final results = out.results ?? const [];
        if (results.isEmpty) return 'No results for "$query".';
        return [
          for (var i = 0; i < results.length; i++)
            '${i + 1}. ${results[i].title}\n   ${results[i].url}\n   ${results[i].snippet}',
        ].join('\n');
      case ConnectorType.fetch:
        final url = '${call.args['url'] ?? ''}'.trim();
        if (url.isEmpty) return 'No URL was provided.';
        final out = await executeWebFetch(url);
        if (!out.ok) return 'Could not read the page: ${out.error}';
        // A page can be enormous; keep the tool result inside the context budget.
        const maxChars = 20000;
        final content = out.content ?? '';
        final body = content.length > maxChars
            ? '${content.substring(0, maxChars)}\n[…truncated]'
            : content;
        return '${out.title ?? url}\n\n$body';
      case ConnectorType.mcp:
      case ConnectorType.rest:
        return 'Connector "${connector.name}" (${connector.type.name}) cannot run tool calls from chat.';
    }
  }

  /// One user decision on the pending permission card, then either the next
  /// queued call or a continuation turn so the model can use the result.
  Future<void> _decideCall({required bool allowed}) async {
    final call = _pendingCall;
    if (call == null) return;
    setState(() {
      _pendingCall = null;
      _callQueue = _callQueue.length > 1
          ? _callQueue.sublist(1)
          : const <ToolCall>[];
    });

    final thread = ref.read(threadManagerProvider).activeThread;
    final next = ref.read(threadManagerProvider.notifier);

    if (!allowed) {
      _showToast('Tool call "${call.name}" was denied.');
      if (thread != null) {
        next.addMessageDetailed(
          thread.id,
          'user',
          '[Tool result: ${call.name}]\n'
              'The user denied this tool call. Do not retry it; continue without it.',
        );
        _continueAfterToolQueue();
      }
      return;
    }

    _showToast('Running ${call.name}…');
    Future<void> executeTurn() async {
      try {
        final output = await _executeToolCall(call);
        if (!mounted) return;
        final current = ref.read(threadManagerProvider).activeThread;
        if (current == null) return;
        ref
            .read(threadManagerProvider.notifier)
            .addMessageDetailed(current.id, 'user', '[Tool result: ${call.name}]\n$output');
        _continueAfterToolQueue();
      } catch (err) {
        _showToast('Tool failed: $err');
        if (_callQueue.isNotEmpty && mounted) {
          setState(() => _pendingCall = _callQueue.first);
        }
      }
    }

    executeTurn();
  }

  /// The queue is drained after a decision; hand the final tool result back
  /// so the assistant can finish the turn, or surface the next call.
  void _continueAfterToolQueue() {
    if (_callQueue.isNotEmpty) {
      if (mounted) setState(() => _pendingCall = _callQueue.first);
      return;
    }
    _continueTurn();
  }

  /// A continuation: the explicit history (already containing the tool
  /// result) is sent back and the assistant answers from it. No new user
  /// turn is added.
  Future<void> _continueTurn() async {
    if (_streamingActive) return;
    final thread = ref.read(threadManagerProvider).activeThread;
    if (thread == null) return;
    final history = List<Message>.of(thread.messages);

    final modelId = _selectedModelId ?? _model.id;
    final toolsForModel =
        modelSupportsTools(_provider, modelId) ? toolSpecs(_nativeDefs()) : null;

    setState(() {
      _streamingText.clear();
      _streamingActive = true;
    });

    ref.read(chatStreamProvider.notifier).sendMessage(
          selectedProviderId: _selectedProviderId,
          selectedModelId: _selectedModelId,
          crossProviderFailover: true,
          history: history,
          systemPrompt: await _buildSystemPrompt(
            skills: _skills,
            facts: ref.read(settingsControllerProvider).facts,
            storage: ref.read(settingsControllerProvider.notifier).storage,
          ),
          params: clampParamsToModel(
              ref.read(settingsControllerProvider).params, _provider, modelId),
          tools: toolsForModel,
          userContent: '',
          callbacks: _turnCallbacks(),
        );
  }

  // ── Attachments ──

  static const _imageExtensions = ['png', 'jpg', 'jpeg', 'webp', 'gif'];
  static const _textExtensions = [
    'txt', 'md', 'markdown', 'csv', 'json', 'yaml', 'yml', 'ts', 'tsx',
    'js', 'jsx', 'py', 'css', 'html', 'xml', 'sql', 'log',
  ];

  Future<void> _addAttachments(List<fs.XFile> files) async {
    final allowImages = modelSupportsVision(_provider, _selectedModelId);
    final accepted = <MessageAttachment>[];
    var count = _attachments.length;
    var total = _attachments.fold(0, (sum, a) => sum + a.size);

    for (final xfile in files) {
      if (count >= AttachmentLimits.maxFiles) break;
      final file = File(xfile.path);
      final size = await file.length();
      if (size > AttachmentLimits.maxFileBytes) continue;
      if (total + size > AttachmentLimits.maxTotalBytes) continue;

      final ext = _extOf(xfile.name);
      final isImage = allowImages && _imageExtensions.contains(ext);
      if (!isImage && !_textExtensions.contains(ext)) continue;

      final like = FileLike(
        name: xfile.name,
        type: isImage ? 'image/${ext == 'jpg' ? 'jpeg' : ext}' : '',
        size: size,
        path: xfile.path,
      );
      accepted.add(await readAttachment(like, isImage ? 'image' : 'text'));
      count += 1;
      total += size;
    }

    if (accepted.isNotEmpty && mounted) {
      setState(() => _attachments = [..._attachments, ...accepted]);
    }
  }

  static String _extOf(String name) {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final b = _bOf(context);
    final threads = ref.watch(threadManagerProvider);
    final chat = ref.watch(chatStreamProvider);
    final settings = ref.watch(settingsControllerProvider);

    // An MCP connector connecting/disconnecting changes which tools exist.
    ref.listen<List<WebConnector>>(webConnectorsProvider, (previous, next) {
      _refreshMcpTools();
    });

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: Lively.sidebarWidth,
          child: Sidebar(
            threads: [
              for (final t in threads.threads)
                SidebarThread(id: t.id, title: t.title, updatedAt: t.updatedAt),
            ],
            activeThreadId: threads.activeThreadId,
            onSelectThread: (id) =>
                ref.read(threadManagerProvider.notifier).setActiveThreadId(id),
            onNewThread: () => ref.read(threadManagerProvider.notifier).createThread(),
            onDeleteThread: (id) =>
                ref.read(threadManagerProvider.notifier).deleteThread(id),
            onRenameThread: (id, title) =>
                ref.read(threadManagerProvider.notifier).renameThread(id, title),
            onOpenSettings: _openSettings,
            onOpenShortcuts: _openSettings,
            onOpenAccount: () => setState(() => _overlay = _Overlay.account),
            onResetDemo: _resetDemo,
            accountName: settings.accountName,
          ),
        ),
        VerticalDivider(width: 1, thickness: 1, color: Lively.separator(b)),
        Expanded(child: _buildConversation(context, b, threads, chat)),
      ],
    );
  }

  Widget _buildConversation(
    BuildContext context,
    Brightness b,
    ThreadManagerState threads,
    ChatStreamState chat,
  ) {
    final settings = ref.watch(settingsControllerProvider);
    final allowImages = modelSupportsVision(_provider, _selectedModelId);
    final contextMeter = chat.context == null
        ? null
        : ContextMeterState(
            used: chat.context!.used,
            limit: chat.context!.limit,
            ratio: chat.context!.ratio,
            level: switch (chat.context!.level) {
              ContextLevel.critical => 'critical',
              ContextLevel.warn => 'warn',
              _ => 'ok',
            },
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Model bar ──
        Padding(
          padding: const EdgeInsets.fromLTRB(Lively.s3, Lively.s2, Lively.s3, Lively.s1),
          child: ModelBar(
            providers: _providerStatuses(),
            activeId: _provider.id,
            onPick: () => setState(() => _overlay = _Overlay.model),
            contextState: contextMeter,
          ),
        ),
        Divider(height: 1, thickness: Lively.bHairline, color: Lively.separator(b)),

        // ── Message list (+ artifact pane beside it) ──
        Expanded(
          child: _openArtifact == null
              ? _buildMessageList(context, b, threads, chat)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildMessageList(context, b, threads, chat)),
                    VerticalDivider(
                        width: 1, thickness: 1, color: Lively.separator(b)),
                    SizedBox(
                      width: 420,
                      child: ArtifactPane(
                        artifact: _openArtifact!,
                        onClose: () => setState(() => _openArtifact = null),
                        onToast: _showToast,
                      ),
                    ),
                  ],
                ),
        ),
        Divider(height: 1, thickness: Lively.bHairline, color: Lively.separator(b)),

        // ── Overlay surfaces (rendered inline, docked above composer) ──
        if (_terminalOpen)
          TerminalDock(
            onClose: () => setState(() => _terminalOpen = false),
            defaultWorkingDir: './workspace',
          ),
        if (_researchQuery != null)
          ResearchOverlay(
            query: _researchQuery!,
            onClose: () => setState(() => _researchQuery = null),
          ),
        if (_voicePhase != VoicePhase.idle)
          Padding(
            padding: const EdgeInsets.fromLTRB(Lively.s3, Lively.s2, Lively.s3, 0),
            child: VoiceDock(
              phase: _voicePhase,
              error: _voiceError,
              onEnd: _toggleVoice,
            ),
          ),
        if (_overlay == _Overlay.account)
          Padding(
            padding: const EdgeInsets.fromLTRB(Lively.s3, Lively.s2, Lively.s3, 0),
            child: AccountPanel(
              accountName: settings.accountName,
              planLabel: 'Free plan',
              conversationCount: threads.threads.length,
              onManagePlan: () => _showToast('This build has no plan to manage.'),
              onEditProfile: () {
                setState(() => _overlay = null);
                _openSettings();
              },
              onSignOut: () => _showToast('This build has no accounts to sign out of.'),
            ),
          ),
        if (_overlay == _Overlay.customize)
          CustomizeOverlay(
            factCount: settings.facts.length,
            onOpenMemory: () {
              setState(() => _overlay = null);
              _openSettings();
            },
            onClose: () => setState(() => _overlay = null),
            onToast: _showToast,
          ),
        if (_overlay == _Overlay.model)
          ModelOverlay(
            activeProviderId: _provider.id,
            activeModelId: _model.id,
            onSelect: _selectModel,
            onClose: () => setState(() => _overlay = null),
          ),
        if (_overlay == _Overlay.tools)
          ToolsOverlay(
            tools: _composerTools,
            enabled: _enabledTools,
            onToggle: _toggleTool,
            onOpenTerminal: () => setState(() {
              _overlay = null;
              _terminalOpen = true;
            }),
            onOpenConnectors: () => setState(() => _overlay = _Overlay.connectors),
            onClose: () => setState(() => _overlay = null),
          ),
        if (_overlay == _Overlay.connectors)
          ConnectorsOverlay(
            onClose: () => setState(() => _overlay = null),
            onToast: _showToast,
          ),

        // ── Composer ──
        Padding(
          padding: const EdgeInsets.fromLTRB(Lively.s3, Lively.s2, Lively.s3, Lively.s3),
          child: Composer(
            controller: _input,
            onChanged: (_) => setState(() {}),
            onSubmit: _onSubmit,
            onStop: _onStop,
            isStreaming: _streamingActive,
            isPending: chat.pending,
            isOnline: true,
            effort: _effort,
            onEffort: (v) => setState(() => _effort = v),
            tools: _composerTools,
            enabledTools: _enabledTools.toList(),
            onToggleTool: _toggleTool,
            voiceState: _composerVoiceState,
            onVoiceToggle: _toggleVoice,
            onManageTools: () => setState(() => _overlay = _Overlay.tools),
            attachments: _attachments,
            onAddFiles: _addAttachments,
            onRemoveAttachment: (id) =>
                setState(() => _attachments = [..._attachments.where((a) => a.id != id)]),
            allowImages: allowImages,
          ),
        ),
      ],
    );
  }

  Widget _buildMessageList(
    BuildContext context,
    Brightness b,
    ThreadManagerState threads,
    ChatStreamState chat,
  ) {
    final thread = threads.activeThread;
    final messages = thread?.messages ?? const <Message>[];
    final isEmpty = messages.isEmpty && !_streamingActive;

    final turnList = <Widget>[
      for (var i = 0; i < messages.length; i++)
        MessageTurn(
          message: messages[i],
          onCopy: (text) => _copy(text, context, b),
          onAction: _handleAction,
        ),
      if (_streamingActive)
        MessageTurn(
          message: Message(
            id: 'streaming',
            threadId: thread?.id ?? '',
            role: 'assistant',
            content: '',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
          isStreaming: true,
          streamingContent: _streamingText.toString(),
        ),
      if (_pendingCall != null)
        PermissionCard(
          call: _pendingCall!,
          onAllow: () => _decideCall(allowed: true),
          onDeny: () => _decideCall(allowed: false),
        ),
    ];

    return isEmpty
        ? _EmptyState(brightness: b, onSuggestion: (s) => _setInput(s))
        : Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(
                  horizontal: Lively.s6, vertical: Lively.threadGap),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: Lively.columnWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: turnList,
                  ),
                ),
              ),
            ),
          );
  }

  void _copy(String text, BuildContext context, Brightness b) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted || !context.mounted) return;
    f.displayInfoBar(
      context,
      builder: (inner, close) => _ToastBar(text: 'Copied to clipboard', brightness: b),
    );
  }

  /// A quiet toast near the composer (App.tsx `showToast`).
  void _showToast(String message) {
    if (!mounted) return;
    f.displayInfoBar(
      context,
      builder: (inner, close) => _ToastBar(text: message, brightness: _bOf(inner)),
    );
  }

  // ── Overlays ──

  void _openSettings() {
    SettingsDialog.show(
      context,
      onClose: () => Navigator.of(context, rootNavigator: true).pop(),
      onToast: _showToast,
      // "Customize" lives in settings: close the dialog, then open the surface.
      onCustomize: () {
        Navigator.of(context, rootNavigator: true).pop();
        if (mounted) setState(() => _overlay = _Overlay.customize);
      },
    );
  }

  Future<void> _resetDemo() async {
    final manager = ref.read(threadManagerProvider.notifier);
    final current = ref.read(threadManagerProvider).threads;
    for (final t in List.of(current)) {
      await chatStorage.deleteThread(t.id);
    }
    manager.createThread();
  }

  /// The user picked a model in the overlay. Port of `selectModel` in
  /// App.tsx: remember the choice, close the overlay, and drop image
  /// attachments the new model cannot read.
  void _selectModel(String providerId, String modelId) {
    final provider = providers.firstWhere(
      (p) => p.id == providerId,
      orElse: () => providers.first,
    );
    if (provider.id != providerId) return;
    saveSelectedModel(providerId, modelId);
    // Params follow the model: load this model's saved params (or defaults).
    ref
        .read(settingsControllerProvider.notifier)
        .selectModel(provider, modelId, getModel(provider, modelId).label);

    var droppedImages = false;
    setState(() {
      _selectedProviderId = providerId;
      _selectedModelId = modelId;
      _overlay = null;
      if (!getModel(provider, modelId).vision) {
        final kept = [for (final a in _attachments) if (a.kind != 'image') a];
        droppedImages = kept.length != _attachments.length;
        _attachments = kept;
      }
    });
    if (droppedImages) _showToast('Images removed: the selected model is text-only.');
  }
}

// ── Toast ────────────────────────────────────────────────────────────────────

class _ToastBar extends StatelessWidget {
  final String text;
  final Brightness brightness;
  const _ToastBar({required this.text, required this.brightness});

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    return Padding(
      padding: const EdgeInsets.all(Lively.s2),
      child: Row(children: [
        Icon(f.FluentIcons.check_mark, size: 14, color: Lively.appleGreen),
        const SizedBox(width: Lively.s2),
        Text(text, style: TextStyle(color: Lively.textPrimary(b), fontSize: Lively.tFootnote)),
      ]),
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final Brightness brightness;
  final ValueChanged<String> onSuggestion;

  const _EmptyState({required this.brightness, required this.onSuggestion});

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: _EmptyMark(),
          ),
          const SizedBox(height: Lively.s3),
          Text(
            'Start a conversation',
            style: TextStyle(
              color: Lively.textPrimary(b),
              fontSize: Lively.tTitle,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Lively.s1),
          Text(
            'Ask anything, attach files, or pick a tool.',
            style: TextStyle(color: Lively.textSecondary(b), fontSize: Lively.tCallout),
          ),
          const SizedBox(height: Lively.s6),
          Wrap(
            spacing: Lively.s2,
            runSpacing: Lively.s2,
            alignment: WrapAlignment.center,
            children: [
              for (final s in _suggestions)
                GestureDetector(
                  onTap: () => onSuggestion(s),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: Lively.s3, vertical: Lively.s2),
                    decoration: BoxDecoration(
                      color: Lively.fill(b, 1),
                      borderRadius: BorderRadius.circular(Lively.rLg),
                      border:
                          Border.all(color: Lively.separator(b), width: Lively.bHairline),
                    ),
                    child: Text(
                      s,
                      style: TextStyle(color: Lively.textSecondary(b), fontSize: Lively.tFootnote),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Reuses the sidebar's pixel emblem at small scale for the empty state.
class _EmptyMark extends StatelessWidget {
  const _EmptyMark();

  @override
  Widget build(BuildContext context) {
    final b = _bOf(context);
    return CustomPaint(
      painter: _MarkPainter(Lively.textPrimary(b)),
      size: const Size(36, 36),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final Color color;
  _MarkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 5;
    final inset = cell * 0.07;
    final radius = Radius.circular(cell * 0.22);

    void pixel(int x, int y, Paint paint) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x * cell + inset, y * cell + inset,
              cell - inset * 2, cell - inset * 2),
          radius,
        ),
        paint,
      );
    }

    final main = Paint()..color = color;
    const pixels = [(0, 2), (1, 2), (2, 1), (2, 2), (3, 1), (1, 3)];
    for (final (x, y) in pixels) {
      pixel(x, y, main);
    }
    pixel(3, 3, Paint()..color = Lively.orange500);
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) => old.color != color;
}


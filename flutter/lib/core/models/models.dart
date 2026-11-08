import 'dart:convert';

/// Shared domain models — port of `src/db/storageAdapter.ts`,
/// `src/chat/attachments.ts`, `src/tools/types.ts`.

// ─── Messages & threads ─────────────────────────────────────────────────────

class ProviderUsage {
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
  const ProviderUsage({this.promptTokens, this.completionTokens, this.totalTokens});

  factory ProviderUsage.fromJson(Map<String, dynamic> j) => ProviderUsage(
        promptTokens: j['promptTokens'] as int?,
        completionTokens: j['completionTokens'] as int?,
        totalTokens: j['totalTokens'] as int?,
      );

  Map<String, dynamic> toJson() => {
        if (promptTokens != null) 'promptTokens': promptTokens,
        if (completionTokens != null) 'completionTokens': completionTokens,
        if (totalTokens != null) 'totalTokens': totalTokens,
      };
}

class ProviderInfo {
  final String providerId;
  final String model;
  final bool fallbackUsed;
  final ProviderUsage? usage;
  const ProviderInfo({
    required this.providerId,
    required this.model,
    this.fallbackUsed = false,
    this.usage,
  });

  factory ProviderInfo.fromJson(Map<String, dynamic> j) => ProviderInfo(
        providerId: j['providerId'] as String? ?? '',
        model: j['model'] as String? ?? '',
        fallbackUsed: j['fallbackUsed'] as bool? ?? false,
        usage: j['usage'] == null
            ? null
            : ProviderUsage.fromJson(j['usage'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'providerId': providerId,
        'model': model,
        if (fallbackUsed) 'fallbackUsed': true,
        if (usage != null) 'usage': usage!.toJson(),
      };
}

class MessageAttachment {
  final String id;
  final String kind; // 'image' | 'text'
  final String name;
  final String mime;
  final int size;
  final String? dataUrl;
  final String? text;
  const MessageAttachment({
    required this.id,
    required this.kind,
    required this.name,
    required this.mime,
    required this.size,
    this.dataUrl,
    this.text,
  });

  factory MessageAttachment.fromJson(Map<String, dynamic> j) => MessageAttachment(
        id: j['id'] as String,
        kind: j['kind'] as String,
        name: j['name'] as String,
        mime: j['mime'] as String? ?? '',
        size: j['size'] as int? ?? 0,
        dataUrl: j['dataUrl'] as String?,
        text: j['text'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'name': name,
        'mime': mime,
        'size': size,
        if (dataUrl != null) 'dataUrl': dataUrl,
        if (text != null) 'text': text,
      };
}

class Message {
  final String id;
  final String threadId;
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  final List<MessageAttachment>? attachments;
  final ProviderInfo? providerInfo;
  final int createdAt;
  const Message({
    required this.id,
    required this.threadId,
    required this.role,
    required this.content,
    this.attachments,
    this.providerInfo,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: j['id'] as String,
        threadId: j['threadId'] as String,
        role: j['role'] as String,
        content: j['content'] as String? ?? '',
        attachments: (j['attachments'] as List?)
            ?.map((e) => MessageAttachment.fromJson(e as Map<String, dynamic>))
            .toList(),
        providerInfo: j['providerInfo'] == null
            ? null
            : ProviderInfo.fromJson(j['providerInfo'] as Map<String, dynamic>),
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'threadId': threadId,
        'role': role,
        'content': content,
        if (attachments != null)
          'attachments': attachments!.map((a) => a.toJson()).toList(),
        if (providerInfo != null) 'providerInfo': providerInfo!.toJson(),
        'createdAt': createdAt,
      };

  Message copyWith({String? content, ProviderInfo? providerInfo}) => Message(
        id: id,
        threadId: threadId,
        role: role,
        content: content ?? this.content,
        attachments: attachments,
        providerInfo: providerInfo ?? this.providerInfo,
        createdAt: createdAt,
      );
}

class Thread {
  final String id;
  final String title;
  final int createdAt;
  final int updatedAt;
  final List<Message> messages;
  const Thread({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.messages = const [],
  });

  factory Thread.fromJson(Map<String, dynamic> j) => Thread(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'New conversation',
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
        messages: (j['messages'] as List? ?? const [])
            .map((e) => Message.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  Thread copyWith({
    String? title,
    int? updatedAt,
    List<Message>? messages,
  }) =>
      Thread(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        messages: messages ?? this.messages,
      );
}

class ThreadSummary {
  final String id;
  final String title;
  final int createdAt;
  final int updatedAt;
  const ThreadSummary({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });
}

class Fact {
  final String id;
  final String fact;
  final String category;
  final int createdAt;
  const Fact({
    required this.id,
    required this.fact,
    required this.category,
    required this.createdAt,
  });

  factory Fact.fromJson(Map<String, dynamic> j) => Fact(
        id: j['id'] as String,
        fact: j['fact'] as String? ?? '',
        category: j['category'] as String? ?? '',
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'fact': fact,
        'category': category,
        'createdAt': createdAt,
      };
}

class ExportPayload {
  static const version = 1;
  final int exportedAt;
  final List<Thread> threads;
  final List<Fact> facts;
  const ExportPayload({
    required this.exportedAt,
    this.threads = const [],
    this.facts = const [],
  });

  factory ExportPayload.fromJson(Map<String, dynamic> j) => ExportPayload(
        exportedAt: (j['exportedAt'] as num?)?.toInt() ?? 0,
        threads: (j['threads'] as List? ?? const [])
            .map((e) => Thread.fromJson(e as Map<String, dynamic>))
            .toList(),
        facts: (j['facts'] as List? ?? const [])
            .map((e) => Fact.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'exportedAt': exportedAt,
        'threads': threads.map((t) => t.toJson()).toList(),
        'facts': facts.map((f) => f.toJson()).toList(),
      };
}

// ─── Tool calls ─────────────────────────────────────────────────────────────
// Security rule (spec §9.1): every tool call requires explicit user approval
// before execution. No "Always Allow" mode in v0.

class ToolCall {
  final String id;
  final String name;
  final String description;
  final Map<String, dynamic> args;
  final String? targetPath;
  final String? command;
  final List<String>? mcpArgs;
  final String? workingDir;
  final String? toolName;
  final Map<String, dynamic>? toolArgs;
  const ToolCall({
    required this.id,
    required this.name,
    required this.description,
    this.args = const {},
    this.targetPath,
    this.command,
    this.mcpArgs,
    this.workingDir,
    this.toolName,
    this.toolArgs,
  });
}

class ToolResult {
  final bool ok;
  final String? output;
  final String? error;
  const ToolResult({required this.ok, this.output, this.error});
}

/// User decision on a pending approval.
enum ApprovalDecision { allowed, denied }

// ─── Secret-detection guard ─────────────────────────────────────────────────

final List<RegExp> _secretPatterns = [
  RegExp(r'sk-[A-Za-z0-9_-]{20,}'), // OpenAI / OpenRouter
  RegExp(r'gsk_[A-Za-z0-9_-]{20,}'), // Groq
  RegExp(r'AIza[A-Za-z0-9_-]{30,}'), // Google AI
  RegExp(r'Bearer\s+[A-Za-z0-9._-]{20,}', caseSensitive: false),
];

bool containsSecrets(String text) =>
    _secretPatterns.any((p) => p.hasMatch(text));

void assertNoSecrets(Object payload, String label) {
  final json = jsonEncode(payload);
  if (containsSecrets(json)) {
    throw Exception(
        '[StorageAdapter] Refusing to persist $label: potential secret detected.');
  }
}
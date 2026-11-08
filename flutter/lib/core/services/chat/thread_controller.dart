/// chatThreadManager — Riverpod controller for managing conversation threads.
/// Port of `src/chat/threadHooks.ts`: CRUD + debounced auto-save against the
/// StorageAdapter.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../storage/storage_adapters.dart';
import '../storage_adapter.dart';
import '../../models/models.dart';

/// Storage adapter used by the chat controllers; wired up at app start.
/// The default is an in-memory adapter until the SQLite one is installed.
StorageAdapter chatStorage = MemoryStorageAdapter();

final threadManagerProvider =
    StateNotifierProvider<ThreadManager, ThreadManagerState>((ref) {
  return ThreadManager();
});

class ThreadManagerState {
  final List<ThreadSummary> threads;
  final String? activeThreadId;
  final Thread? activeThread;
  const ThreadManagerState({
    this.threads = const [],
    this.activeThreadId,
    this.activeThread,
  });
}

class ThreadManagerStateUpdate {
  final ThreadManagerState state;
  final Thread? createdThread;
  const ThreadManagerStateUpdate(this.state, this.createdThread);
}

class ThreadManager extends StateNotifier<ThreadManagerState> {
  ThreadManager() : super(const ThreadManagerState()) {
    _load();
  }

  final Uuid _uuid = const Uuid();
  Timer? _saveTimer;
  Thread? _activeThread;
  Thread? _pendingSave;
  bool _ready = false;

  // Keep the ref in step with async loads and external state changes.
  Thread? get currentThread => _activeThread;

  // Load thread list on mount.
  Future<void> _load() async {
    try {
      final list = await chatStorage.listThreads();
      if (!mounted) return;
      var activeId = state.activeThreadId;
      // Auto-select the most recent thread if one exists.
      if (list.isNotEmpty && (activeId == null || activeId.isEmpty)) {
        activeId = list.first.id;
      }
      _ready = true;
      state = ThreadManagerState(threads: list, activeThreadId: activeId);
      await loadThread(activeId);
    } catch (_) {
      // Storage not ready yet — threads stay empty until ready.
    }
  }

  /// Load full thread when the active id changes.
  Future<void> loadThread(String? activeThreadId) async {
    if (!_ready || activeThreadId == null) {
      _activeThread = null;
      state = ThreadManagerState(
        threads: state.threads,
        activeThreadId: state.activeThreadId,
      );
      return;
    }
    try {
      final loaded = await chatStorage.getThread(activeThreadId);
      if (!mounted) return;
      // A thread that was created or updated in memory a moment ago is newer
      // than the stored copy we just read — keep it, otherwise the first
      // message of a new conversation is wiped before it renders.
      final prev = state.activeThread;
      final keep = prev != null &&
          prev.id == activeThreadId &&
          prev.updatedAt >= (loaded?.updatedAt ?? 0);
      final selected = keep ? prev : loaded;
      _activeThread = selected;
      state = ThreadManagerState(
        threads: state.threads,
        activeThreadId: activeThreadId,
        activeThread: selected,
      );
    } catch (_) {
      // Thread load failed — keep the previous state.
    }
  }

  /// Select an existing thread by id (loads it).
  Future<void> setActiveThreadId(String? id) async {
    state = ThreadManagerState(threads: state.threads, activeThreadId: id);
    await loadThread(id);
  }

  /// Create a new thread, persist it immediately and select it.
  Thread createThread() {
    final thread = Thread(
      id: _uuid.v4(),
      title: 'New conversation',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      messages: const [],
    );
    _activeThread = thread;
    state = ThreadManagerState(
      threads: [
        ThreadSummary(
          id: thread.id,
          title: thread.title,
          createdAt: thread.createdAt,
          updatedAt: thread.updatedAt,
        ),
        ...state.threads,
      ],
      activeThreadId: thread.id,
      activeThread: thread,
    );
    // Persist immediately.
    chatStorage.saveThread(thread).catchError((_) => null);
    return thread;
  }

  /// Debounced save — 500 ms after the last change.
  void saveThread(Thread thread) {
    _activeThread = thread;
    _pendingSave = thread;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      final pending = _pendingSave;
      _pendingSave = null;
      if (pending != null) {
        chatStorage.saveThread(pending).catchError((_) => null);
      }
      _refreshSummary(pending);
      state = ThreadManagerState(
        threads: _threadsAfterSave(thread),
        activeThreadId: state.activeThreadId,
        activeThread: thread,
      );
      _activeThread = _activeThread ?? thread;
    });
    state = ThreadManagerState(
      threads: _threadsAfterSave(thread),
      activeThreadId: thread.id,
      activeThread: thread,
    );
    _activeThread = thread;
  }

  List<ThreadSummary> _threadsAfterSave(Thread thread) {
    final updated = ThreadSummary(
      id: thread.id,
      title: thread.title,
      createdAt: thread.createdAt,
      updatedAt: thread.updatedAt,
    );
    final without = state.threads.where((t) => t.id != thread.id).toList();
    return [updated, ...without];
  }

  void _refreshSummary(Thread? _) {}

  /// Write the newest pending change before the app goes away.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final pending = _pendingSave;
    _pendingSave = null;
    if (pending != null) {
      try {
        await chatStorage.saveThread(pending);
      } catch (_) {}
    }
  }

  Future<void> deleteThread(String id) async {
    if (_pendingSave?.id == id) {
      _saveTimer?.cancel();
      _saveTimer = null;
      _pendingSave = null;
    }
    await chatStorage.deleteThread(id);
    final remaining = state.threads.where((t) => t.id != id).toList();
    if (state.activeThreadId == id) {
      _activeThread = null;
      state = ThreadManagerState(threads: remaining);
      return;
    }
    state = ThreadManagerState(
      threads: remaining,
      activeThreadId: state.activeThreadId,
      activeThread: state.activeThread,
    );
  }

  void renameThread(String id, String title) {
    final current = _activeThread;
    if (current == null || current.id != id) return;
    saveThread(current.copyWith(
      title: title,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Message addMessage(String threadId, String role, String content,
      {MessageAttachmentList? attachments}) {
    return addMessageDetailed(threadId, role, content, attachments: attachments);
  }

  Message addMessageDetailed(
    String threadId,
    String role,
    String content, {
    MessageAttachmentList? attachments,
  }) {
    final thread = _activeThread;
    final noThread = thread == null || thread.id != threadId;
    if (noThread) {
      throw StateError('No active thread');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final messages = [...thread.messages];
    messages.add(Message(
      id: _uuid.v4(),
      threadId: threadId,
      role: role,
      content: content,
      attachments: attachments,
      createdAt: now,
    ));
    saveThread(thread.copyWith(
      updatedAt: now,
      messages: messages,
      // Auto-title from first user message.
      title: messages.length == 1 && role == 'user'
          ? content.safeSlice(0, 50) + (content.length > 50 ? '…' : '')
          : thread.title,
    ));
    return messages.last;
  }

  void updateLastAssistantMessage(
    String threadId,
    String content, {
    ProviderInfo? providerInfo,
  }) {
    final current = _activeThread;
    if (current == null) return;
    final messages = [...current.messages];
    var lastIdx = -1;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == 'assistant') {
        lastIdx = i;
        break;
      }
    }
    if (lastIdx == -1) return;
    messages[lastIdx] =
        messages[lastIdx].copyWith(content: content, providerInfo: providerInfo);
    saveThread(current.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      messages: messages,
    ));
  }
}

extension on String {
  String safeSlice(int start, int end) {
    if (start >= length) return '';
    final capped = end > length ? length : end;
    return substring(start, capped);
  }
}

typedef MessageAttachmentList = List<MessageAttachment>;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/services/chat/chat_transport.dart';
import 'core/services/chat/model_params.dart';
import 'core/services/chat/thread_controller.dart';
import 'core/services/storage/storage_adapters.dart';
import 'core/services/providers_registry.dart' show providers;
import 'core/state/secure_secret_store.dart';
import 'core/state/settings_controller.dart'
    show MemorySecretStore, SecretStore, globalSecretStore;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Persistence: real params store + desktop SQLite once ready. Until the
  // SQLite adapter is installed, `thread_controller.chatStorage` keeps the
  // in-memory fallback so the first frames render regardless.
  await initParamStore();
  try {
    final adapter = await SqliteStorageAdapter.open();
    chatStorage = adapter;
  } catch (_) {
    // Without a database the app still runs on the memory adapter; saving
    // failures surface per-thread rather than blocking launch.
  }

  // Provider keys. Keys saved in Settings live in the OS secure store; if it
  // is unavailable the app still starts on an in-memory store (keys then last
  // only for the session). A key saved in-app wins over the environment.
  SecretStore secrets;
  try {
    secrets = await SecureSecretStore.open();
  } catch (_) {
    secrets = MemorySecretStore();
  }
  globalSecretStore = secrets;

  final env = Platform.environment;
  providerKeyResolver = (envKey) {
    if (envKey.isEmpty) return null;
    for (final p in providers) {
      if (p.envKey == envKey) {
        final saved = secrets.peek(p.id);
        if (saved != null && saved.isNotEmpty) return saved;
      }
    }
    return env[envKey];
  };

  // Desktop window bootstrap (frameless Fluent chrome).
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1280, 820),
    minimumSize: Size(960, 640),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const ProviderScope(child: LivelyApp()));
}

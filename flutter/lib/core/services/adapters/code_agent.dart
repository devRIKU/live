import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_pty/flutter_pty.dart';

/// CodeAgentProvider — interface and implementations for running the code
/// agent (OpenCode) in an embedded terminal pane (port of
/// `src/adapters/codeAgent.ts`).
///
/// Rules (from §9.4):
/// - The terminal UI (xterm) is a terminal UI, not a process supervisor.
/// - The native desktop shell launches and manages the process.
/// - Scoped to user-approved working directory.
/// - Commands and consequential actions require approval.
/// - Reliable stop with exit code / error surfaced.
///
/// Tauri deviation: the TS `NativeCodeAgentProvider` asked the Tauri Rust
/// side to spawn the child process (`start_code_agent` /
/// `send_code_agent_input` / `stop_code_agent`). In the Flutter port Dart
/// *is* the native side, so [NativeCodeAgentProvider] spawns the process
/// directly with `dart:io` `Process` and pumps its stdout/stderr to the
/// output listeners.
///
/// Native hook still needed for full TTY behaviour: plain pipes are not a
/// pseudo-console, so interactive ANSI/PTY programs (like `opencode`
/// itself) need a ConPTY (Windows) or PTY (macOS/Linux) launcher. Plug one
/// in via [CodeAgentLauncher]; the default [ProcessCodeAgentLauncher]
/// uses plain pipes, which is fine for non-interactive commands.

// ─── Types ──────────────────────────────────────────────────────────────────

/// Options for starting a code agent session.
class CodeAgentOptions {
  final String workingDir;
  final String? command;
  final List<String> args;
  final Map<String, String>? env;
  const CodeAgentOptions({
    required this.workingDir,
    this.command,
    this.args = const [],
    this.env,
  });
}

/// Running process handle handed back by a [CodeAgentLauncher].
///
/// Structured so that a ConPTY-based launcher (raw pipes, no [Process])
/// can be adapted as well.
class RunningCodeAgentProcess {
  /// Send keystrokes / text to the process.
  final Future<void> Function(String data) write;
  final Stream<List<int>> stdout;
  final Stream<List<int>> stderr;
  final Future<int> exitCode;

  /// Send a termination signal; returns false when the process is gone.
  final bool Function() kill;

  /// Tell the process its terminal changed size. `null` for plain pipes,
  /// which have no notion of a terminal size.
  final void Function(int columns, int rows)? resize;
  const RunningCodeAgentProcess({
    required this.write,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.kill,
    this.resize,
  });
}

/// Spawns the agent process. Swap in a PTY/ConPTY implementation if the
/// agent needs a real terminal.
abstract class CodeAgentLauncher {
  Future<RunningCodeAgentProcess> launch(CodeAgentOptions options);
}

/// Default launcher using `dart:io` `Process.start`.
class ProcessCodeAgentLauncher implements CodeAgentLauncher {
  const ProcessCodeAgentLauncher();

  @override
  Future<RunningCodeAgentProcess> launch(CodeAgentOptions options) async {
    final process = await Process.start(
      options.command ?? 'opencode',
      options.args,
      workingDirectory: options.workingDir,
      environment: options.env,
      // `.cmd`/`.bat` shims (e.g. npx on Windows) need a shell.
      runInShell: Platform.isWindows,
    );
    return RunningCodeAgentProcess(
      write: (data) async {
        process.stdin.write(data);
        await process.stdin.flush();
      },
      stdout: process.stdout,
      stderr: process.stderr,
      exitCode: process.exitCode,
      kill: () => process.kill(),
    );
  }
}

/// Launches the agent inside a real pseudo-console (ConPTY on Windows, a PTY
/// elsewhere) via `flutter_pty`, so interactive programs — `opencode`'s TUI,
/// shells, anything that reads raw keys or draws with ANSI — behave as they
/// would in a normal terminal. Output is one merged stream: a pseudo-terminal
/// does not separate stdout from stderr.
class PtyCodeAgentLauncher implements CodeAgentLauncher {
  const PtyCodeAgentLauncher({this.columns = 80, this.rows = 24});

  final int columns;
  final int rows;

  @override
  Future<RunningCodeAgentProcess> launch(CodeAgentOptions options) async {
    final command = options.command ?? 'opencode';

    // `opencode` is typically an npm `.cmd` shim on Windows, which
    // CreateProcess cannot start directly (it only appends `.exe`). Go through
    // cmd.exe, as the pipe launcher does with `runInShell`.
    final executable = Platform.isWindows ? 'cmd.exe' : command;
    final arguments = Platform.isWindows
        ? ['/c', command, ...options.args]
        : options.args;

    final pty = Pty.start(
      executable,
      arguments: arguments,
      workingDirectory: options.workingDir,
      // A custom environment must extend the parent's: replacing it would
      // drop PATH and the agent could not even be found.
      environment: {...Platform.environment, ...?options.env},
      columns: columns,
      rows: rows,
    );

    return RunningCodeAgentProcess(
      write: (data) async => pty.write(const Utf8Encoder().convert(data)),
      stdout: pty.output,
      stderr: const Stream<List<int>>.empty(),
      exitCode: pty.exitCode,
      kill: () => pty.kill(),
      // flutter_pty takes (rows, columns).
      resize: (cols, rows) => pty.resize(rows, cols),
    );
  }
}

abstract class CodeAgentProvider {
  Future<void> start(CodeAgentOptions options);
  Future<void> sendInput(String data);
  Future<void> stop();

  /// The terminal showing this process changed size. Remembered and applied
  /// once the process exists; a no-op for providers without a terminal.
  void resize(int columns, int rows);

  /// Subscribe to process output; returns an unsubscribe callback.
  void Function() onOutput(void Function(String data) callback);

  /// Subscribe to process exit; returns an unsubscribe callback.
  void Function() onExit(void Function(int code, String? error) callback);

  bool isRunning();
  String? getWorkingDir();
}

// ─── Mock provider ──────────────────────────────────────────────────────────

/// Simulates OpenCode terminal interaction safely without spawning OS
/// processes (browser dev phase in the TS build; tests in Dart).
class MockCodeAgentProvider implements CodeAgentProvider {
  bool _running = false;
  String? _workingDir;
  final Set<void Function(String)> _outputListeners = {};
  final Set<void Function(int, String?)> _exitListeners = {};
  String _inputBuffer = '';
  Timer? _testTimer;

  @override
  Future<void> start(CodeAgentOptions options) async {
    if (_running) {
      await stop();
    }
    _running = true;
    _workingDir = options.workingDir;

    // Emit initial banner
    _emit(
        '\x1b[1;34m=== OpenCode Agent (Browser Simulation Mode) ===\x1b[0m\r\n'
        '\x1b[90mWorking directory: ${options.workingDir}\x1b[0m\r\n'
        '\x1b[90mZen free models active: Space Bunny, Beam, Nemotron 3.5, DeepSeek 4.1 Flash\x1b[0m\r\n'
        '\x1b[32mAgent ready. Type a prompt or command (e.g. "help", "status", "test"):\x1b[0m\r\n\r\n> ');
  }

  @override
  void resize(int columns, int rows) {}

  @override
  Future<void> sendInput(String data) async {
    if (!_running) return;

    // Handle Enter
    if (data == '\r' || data == '\n') {
      _emit('\r\n');
      final cmd = _inputBuffer.trim();
      _inputBuffer = '';
      _handleCommand(cmd);
      return;
    }

    // Handle Backspace
    if (data == '\x7f' || data == '\b') {
      if (_inputBuffer.isNotEmpty) {
        _inputBuffer = _inputBuffer.substring(0, _inputBuffer.length - 1);
        _emit('\b \b');
      }
      return;
    }

    // Handle Ctrl+C
    if (data == '\x03') {
      _emit('^C\r\n> ');
      _inputBuffer = '';
      return;
    }

    _inputBuffer += data;
    _emit(data);
  }

  void _handleCommand(String cmd) {
    if (cmd.isEmpty) {
      _emit('> ');
      return;
    }

    if (cmd == 'exit' || cmd == 'quit') {
      _emit('Exiting OpenCode agent...\r\n');
      unawaited(stop());
      return;
    }

    if (cmd == 'help') {
      _emit('Available simulated commands:\r\n'
          '  help     - Show this help\r\n'
          '  status   - Display agent workspace status\r\n'
          '  test     - Run simulated test suite\r\n'
          '  exit     - Stop agent session\r\n\r\n> ');
      return;
    }

    if (cmd == 'status') {
      _emit('Agent Status: Active\r\n'
          'Directory: $_workingDir\r\n'
          'Platform: Web Browser Sandbox (M7 Mock)\r\n\r\n> ');
      return;
    }

    if (cmd == 'test') {
      _emit('Running tests in $_workingDir...\r\n');
      _testTimer = Timer(const Duration(milliseconds: 300), () {
        _emit('\x1b[32m✓ All tests passed (3/3)\x1b[0m\r\n\r\n> ');
      });
      return;
    }

    // Default simulated response
    _emit('\x1b[36m[OpenCode]\x1b[0m Received instruction: "$cmd"\r\n'
        'Simulated execution completed in $_workingDir.\r\n\r\n> ');
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _testTimer?.cancel();
    _emit('\r\n\x1b[33m[OpenCode Process stopped]\x1b[0m\r\n');
    for (final l in _exitListeners.toList()) {
      l(0, null);
    }
  }

  @override
  void Function() onOutput(void Function(String data) callback) {
    _outputListeners.add(callback);
    return () => _outputListeners.remove(callback);
  }

  @override
  void Function() onExit(void Function(int code, String? error) callback) {
    _exitListeners.add(callback);
    return () => _exitListeners.remove(callback);
  }

  @override
  bool isRunning() => _running;

  @override
  String? getWorkingDir() => _workingDir;

  void _emit(String data) {
    for (final l in _outputListeners.toList()) {
      l(data);
    }
  }
}

// ─── Native provider ────────────────────────────────────────────────────────

/// Communicates with a real child process spawned by the desktop shell.
class NativeCodeAgentProvider implements CodeAgentProvider {
  NativeCodeAgentProvider({CodeAgentLauncher? launcher})
      : _launcher = launcher ?? const ProcessCodeAgentLauncher();

  final CodeAgentLauncher _launcher;

  bool _running = false;
  bool _exitNotified = false;
  String? _workingDir;
  final Set<void Function(String)> _outputListeners = {};
  final Set<void Function(int, String?)> _exitListeners = {};
  RunningCodeAgentProcess? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  @override
  Future<void> start(CodeAgentOptions options) async {
    if (_running) await stop();
    _workingDir = options.workingDir;
    _exitNotified = false;

    try {
      final process = await _launcher.launch(options);
      _process = process;
      _running = true;
      // Apply the size the terminal reported before the process existed.
      final size = _size;
      if (size != null) process.resize?.call(size.$1, size.$2);

      _stdoutSub = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_emit);
      _stderrSub = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_emit);

      // Surface the exit code / error when the process ends on its own.
      process.exitCode.then((code) {
        _running = false;
        _notifyExit(code, null);
      }).catchError((Object e) {
        _running = false;
        _notifyExit(1, '$e');
      });
    } catch (err) {
      final msg = err is Exception ? '$err' : err.toString();
      _running = false;
      _notifyExit(1, msg);
      rethrow;
    }
  }

  /// Last terminal size (columns, rows) reported by the UI.
  (int, int)? _size;

  @override
  void resize(int columns, int rows) {
    if (columns <= 0 || rows <= 0) return;
    _size = (columns, rows);
    _process?.resize?.call(columns, rows);
  }

  @override
  Future<void> sendInput(String data) async {
    if (!_running) return;
    final process = _process;
    if (process == null) return;
    await process.write(data);
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    try {
      _process?.kill();
    } catch (_) {
      // Ignore cleanup error
    }
    _process = null;
    _notifyExit(0, null);
  }

  @override
  void Function() onOutput(void Function(String data) callback) {
    _outputListeners.add(callback);
    return () => _outputListeners.remove(callback);
  }

  @override
  void Function() onExit(void Function(int code, String? error) callback) {
    _exitListeners.add(callback);
    return () => _exitListeners.remove(callback);
  }

  @override
  bool isRunning() => _running;

  @override
  String? getWorkingDir() => _workingDir;

  void _emit(String data) {
    for (final l in _outputListeners.toList()) {
      l(data);
    }
  }

  void _notifyExit(int code, String? error) {
    if (_exitNotified) return;
    _exitNotified = true;
    for (final l in _exitListeners.toList()) {
      l(code, error);
    }
  }
}

// ─── Selection ──────────────────────────────────────────────────────────────

/// Runtime switch for the code-agent provider.
class CodeAgentPlatform {
  CodeAgentPlatform._();

  /// The TS build returned the native provider only inside Tauri and the
  /// mock in the browser. The Flutter app is always the desktop runtime, so
  /// the native process provider is the default; flip this for tests.
  static bool useNativeProcess =
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;
}

/// Return the appropriate code agent provider for this runtime.
CodeAgentProvider getCodeAgentProvider() {
  if (CodeAgentPlatform.useNativeProcess) {
    // A real pseudo-console, so interactive agents work. Pass
    // `const ProcessCodeAgentLauncher()` instead for non-interactive use.
    return NativeCodeAgentProvider(launcher: const PtyCodeAgentLauncher());
  }
  return MockCodeAgentProvider();
}

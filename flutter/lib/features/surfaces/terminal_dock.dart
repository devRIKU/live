/// Terminal dock (M7) — the code agent's terminal, docked above the composer.
///
/// The dock is a flex child of the main column, so it can never cover the
/// input: the thread gives up the space the dock needs. The terminal is a
/// real `xterm` emulator (ANSI colours, cursor, selection); the process is
/// supervised by the code-agent provider, not by the widget. The terminal
/// reports its size to the provider so interactive programs redraw correctly
/// when the dock is resized.
/// Port of `src/surfaces/TerminalDock.tsx`.
library;

import 'dart:math';

import 'package:fluent_ui/fluent_ui.dart' as f;
import 'package:flutter/material.dart';
import 'package:xterm2/xterm.dart';
import 'package:xterm2/flutter.dart';

import '../../core/services/adapters/code_agent.dart';
import '../../core/theme/lively_tokens.dart';
import 'overlay_surface.dart';

class TerminalDock extends StatefulWidget {
  final VoidCallback onClose;
  final String defaultWorkingDir;

  const TerminalDock({
    super.key,
    required this.onClose,
    this.defaultWorkingDir = './workspace',
  });

  @override
  State<TerminalDock> createState() => _TerminalDockState();
}

class _TerminalDockState extends State<TerminalDock> {
  final Terminal _terminal = Terminal(maxLines: 10000);
  late final TerminalController _controller;
  late final CodeAgentProvider _provider;
  late final TextEditingController _dir;
  void Function()? _unsubOutput;
  void Function()? _unsubExit;

  bool _running = false;
  String? _exitStatus;

  @override
  void initState() {
    super.initState();
    _controller = TerminalController();
    _provider = getCodeAgentProvider();
    _dir = TextEditingController(text: widget.defaultWorkingDir);

    // Keystrokes go to the process; its output comes back into the emulator.
    _terminal.onOutput = (data) {
      _provider.sendInput(data).catchError((_) {});
    };
    // Subscribe before start so the banner is not missed.
    _unsubOutput = _provider.onOutput(_terminal.write);
    _unsubExit = _provider.onExit((code, error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _exitStatus = 'Process exited with code $code${error != null ? ': $error' : ''}';
      });
    });

    // The agent starts once, in the directory it was opened with.
    _start();
  }

  Future<void> _start() async {
    try {
      await _provider.start(CodeAgentOptions(workingDir: _dir.text.trim()));
      if (!mounted) return;
      setState(() {
        _running = true;
        _exitStatus = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _exitStatus = '$e';
      });
    }
  }

  Future<void> _stop() async {
    await _provider.stop();
    if (mounted) setState(() => _running = false);
  }

  @override
  void dispose() {
    _unsubOutput?.call();
    _unsubExit?.call();
    _provider.stop().catchError((_) {});
    _dir.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = f.FluentTheme.of(context).brightness;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Lively.s3, Lively.s2, Lively.s3, 0),
      child: Container(
        height: 300,
        decoration: BoxDecoration(
          color: Lively.surfaceRaised(b),
          borderRadius: BorderRadius.circular(Lively.rLg),
          border: Border.all(color: Lively.separator(b), width: Lively.bHairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Lively.s3, Lively.s2, Lively.s2, Lively.s2),
              child: Row(
                children: [
                  Icon(f.FluentIcons.command_prompt, size: 14, color: Lively.textSecondary(b)),
                  const SizedBox(width: Lively.s2),
                  Text('Terminal',
                      style: TextStyle(
                          color: Lively.textPrimary(b),
                          fontSize: Lively.tFootnote,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: Lively.s2),
                  Expanded(
                    child: f.TextBox(
                      controller: _dir,
                      enabled: !_running,
                      placeholder: 'Working directory',
                    ),
                  ),
                  const SizedBox(width: Lively.s2),
                  OverlayBadge(
                    label: _running ? 'running' : 'stopped',
                    color: _running ? Lively.appleGreen : Lively.orange500,
                  ),
                  const SizedBox(width: Lively.s2),
                  f.Button(
                    onPressed: _running ? _stop : null,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(f.FluentIcons.stop, size: 11, color: Lively.appleRed),
                      const SizedBox(width: 4),
                      const Text('Stop'),
                    ]),
                  ),
                  const SizedBox(width: Lively.s2),
                  f.Button(
                    // Erase display + scrollback, cursor home.
                    onPressed: () => _terminal.write('\x1b[2J\x1b[3J\x1b[H'),
                    child: const Text('Clear'),
                  ),
                  IconButton(
                    tooltip: 'Close terminal',
                    icon: Icon(f.FluentIcons.chrome_close,
                        size: 14, color: Lively.textSecondary(b)),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: Lively.bHairline, color: Lively.separator(b)),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // xterm's cell size is font-dependent; approximate columns
                  // and rows from the available space and a 9x18 cell.
                  const cellWidth = 9.0;
                  const cellHeight = 18.0;
                  final cols = (constraints.maxWidth / cellWidth).floor().clamp(1, 400);
                  final rows = (constraints.maxHeight / cellHeight).floor().clamp(1, 200);
                  _provider.resize(cols, rows);
                  return Container(
                    color: const Color(0xFF0D0D10),
                    padding: const EdgeInsets.all(Lively.s2),
                    child: TerminalView(_terminal, controller: _controller),
                  );
                },
              ),
            ),
            if (_exitStatus != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Lively.s2),
                color: Lively.fill(b, 2),
                child: Text(
                  _exitStatus!,
                  style: TextStyle(
                    color: Lively.textSecondary(b),
                    fontSize: Lively.tMicro,
                    fontFamily: 'Consolas',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

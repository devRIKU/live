/// Composer — the input, the tool menu, the effort control, dictation and
/// send. Port of `src/shell/Composer.tsx`.
///
/// Geometry is the shell's own: a 28px capsule holding 20px children, the
/// send button as a 34px circle, and the primary action outermost on the right.
library;

import 'dart:convert';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:fluent_ui/fluent_ui.dart' as f;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, LogicalKeyboardKey;

import '../../core/models/models.dart';
import '../../core/theme/lively_tokens.dart';

Brightness _bOf(BuildContext context) => f.FluentTheme.of(context).brightness;

const _efforts = ['Low', 'Medium', 'High'];
const _short = {0: 'Low', 1: 'Med', 2: 'High'};

class ComposerTool {
  final String id;
  final String label;
  final String hint;
  /// 'green' | 'orange' | 'blue'
  final String? tint;
  /// 'image' | 'pen' | 'globe' | 'code'
  final String icon;
  const ComposerTool({
    required this.id,
    required this.label,
    required this.hint,
    this.tint,
    required this.icon,
  });
}

enum VoiceState { idle, listening, processing, speaking }

class Composer extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final VoidCallback onStop;
  final bool isStreaming;
  final bool isPending;
  final bool isOnline;
  final int effort;
  final ValueChanged<int> onEffort;
  final List<ComposerTool> tools;
  final List<String> enabledTools;
  final ValueChanged<String> onToggleTool;
  final VoiceState voiceState;
  final VoidCallback onVoiceToggle;
  final VoidCallback onManageTools;

  /// Files waiting to be sent with the next message.
  final List<MessageAttachment> attachments;
  final void Function(List<fs.XFile> files) onAddFiles;
  final ValueChanged<String> onRemoveAttachment;

  /// False when the active model cannot accept images.
  final bool allowImages;
  final bool disabled;

  const Composer({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onSubmit,
    required this.onStop,
    required this.isStreaming,
    required this.isPending,
    required this.isOnline,
    required this.effort,
    required this.onEffort,
    required this.tools,
    required this.enabledTools,
    required this.onToggleTool,
    required this.voiceState,
    required this.onVoiceToggle,
    required this.onManageTools,
    required this.attachments,
    required this.onAddFiles,
    required this.onRemoveAttachment,
    required this.allowImages,
    this.disabled = false,
  });

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  bool _toolsOpen = false;
  bool _effortOpen = false;

  bool get _ready => widget.controller.text.trim().isNotEmpty || widget.attachments.isNotEmpty;

  void _closePopovers() {
    if (!_toolsOpen && !_effortOpen) return;
    setState(() {
      _toolsOpen = false;
      _effortOpen = false;
    });
  }

  void _toggleTools() => setState(() {
        _toolsOpen = !_toolsOpen;
        _effortOpen = false;
      });

  void _toggleEffort() => setState(() {
        _effortOpen = !_effortOpen;
        _toolsOpen = false;
      });

  static const _allowedImageTypes = ['png', 'jpg', 'jpeg', 'webp', 'gif'];
  static const _allowedTextExtensions = [
    'txt', 'md', 'markdown', 'csv', 'json', 'yaml', 'yml', 'ts', 'tsx',
    'js', 'jsx', 'py', 'css', 'html', 'xml', 'sql', 'log',
  ];

  Future<void> _pickFiles() async {
    final group = <fs.XTypeGroup>[
      if (widget.allowImages)
        fs.XTypeGroup(
          label: 'Images',
          extensions: _allowedImageTypes,
        ),
      fs.XTypeGroup(
        label: 'Text files',
        extensions: _allowedTextExtensions,
      ),
    ];
    final files = await fs.openFiles(acceptedTypeGroups: group);
    if (files.isNotEmpty) widget.onAddFiles(files);
  }

  @override
  Widget build(BuildContext context) {
    final b = _bOf(context);
    final level = _efforts[widget.effort.clamp(0, 2)];
    final pct = widget.effort / 2;

    return Padding(
      padding: const EdgeInsets.only(top: Lively.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.enabledTools.isNotEmpty)
            Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Lively.columnWidth),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Lively.s2),
                  child: Wrap(
                    spacing: Lively.s2,
                    runSpacing: Lively.s1,
                    children: [
                      for (final id in widget.enabledTools)
                        if (widget.tools.any((t) => t.id == id))
                          _ToolChip(
                            brightness: b,
                            label:
                                widget.tools.firstWhere((t) => t.id == id).label,
                            onRemove: () => widget.onToggleTool(id),
                          ),
                    ],
                  ),
                ),
              ),
            ),

          if (widget.attachments.isNotEmpty)
            Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Lively.columnWidth),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Lively.s2),
                  child: Wrap(
                    spacing: Lively.s2,
                    runSpacing: Lively.s1,
                    children: [
                      for (final attachment in widget.attachments)
                        _AttachChip(
                          brightness: b,
                          attachment: attachment,
                          onRemove: () => widget.onRemoveAttachment(attachment.id),
                        ),
                    ],
                  ),
                ),
              ),
            ),

          Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Lively.columnWidth),
              child: TapRegion(
                onTapOutside: (_) => _closePopovers(),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // ── Tools popover ──
                    if (_toolsOpen)
                      Positioned(
                        left: 0,
                        bottom: Lively.composerRadius + Lively.s2,
                        child: _ToolsPopover(
                          brightness: b,
                          tools: widget.tools,
                          enabledTools: widget.enabledTools,
                          onToggleTool: (id) => widget.onToggleTool(id),
                          onManageTools: () {
                            _toggleTools();
                            widget.onManageTools();
                          },
                        ),
                      ),

                    // ── Effort popover ──
                    if (_effortOpen)
                      Positioned(
                        right: 0,
                        bottom: Lively.composerRadius + Lively.s2,
                        child: _EffortPopover(
                          brightness: b,
                          level: level,
                          effort: widget.effort,
                          onEffort: widget.onEffort,
                        ),
                      ),

                    // ── Capsule ──
                    _ComposerBar(
                      brightness: b,
                      widget: widget,
                      ready: _ready,
                      onToggleTools: _toggleTools,
                      onToggleEffort: _toggleEffort,
                      toolsOpen: _toolsOpen,
                      effortOpen: _effortOpen,
                      level: level,
                      onPickFiles: _pickFiles,
                    ),
                  ],
                ),
              ),
            ),
          ),

          Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.only(top: Lively.s2),
              child: Text(
                'Assistant can make mistakes. Double-check important info.',
                style: TextStyle(
                  color: Lively.textTertiary(b),
                  fontSize: Lively.tMicro,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Capsule ──────────────────────────────────────────────────────────────────

class _ComposerBar extends StatelessWidget {
  final Brightness brightness;
  final Composer widget;
  final bool ready;
  final VoidCallback onToggleTools;
  final VoidCallback onToggleEffort;
  final bool toolsOpen;
  final bool effortOpen;
  final String level;
  final VoidCallback onPickFiles;

  const _ComposerBar({
    required this.brightness,
    required this.widget,
    required this.ready,
    required this.onToggleTools,
    required this.onToggleEffort,
    required this.toolsOpen,
    required this.effortOpen,
    required this.level,
    required this.onPickFiles,
  });

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    final w = widget;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Lively.composerPad, vertical: Lively.s1),
        decoration: BoxDecoration(
          color: b == Brightness.dark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(Lively.composerRadius),
          border: Border.all(color: Lively.separator(b), width: Lively.bHairline),
          boxShadow: const [
            BoxShadow(blurRadius: 22, offset: Offset(0, 8), color: Color(0x19000000)),
            BoxShadow(blurRadius: 6, offset: Offset(0, 2), color: Color(0x12000000)),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Btn(
              brightness: b,
              icon: f.FluentIcons.add,
              tooltip: 'Add tools',
              active: toolsOpen,
              onTap: onToggleTools,
            ),
            _Btn(
              brightness: b,
              icon: f.FluentIcons.attach,
              tooltip: w.allowImages ? 'Attach images or files' : 'Attach text files',
              onTap: w.disabled ? null : onPickFiles,
            ),
            const SizedBox(width: Lively.s1),
            Expanded(
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    if (!w.isStreaming && w.isOnline && !w.isPending && !w.disabled) {
                      w.onSubmit();
                    }
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: w.controller,
                  enabled: !w.disabled,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: TextStyle(
                    color: Lively.textPrimary(b),
                    fontSize: Lively.tBody,
                    height: Lively.lhBody,
                  ),
                  cursorColor: Lively.accent(b),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    filled: false,
                    hintText: 'Ask anything',
                    hintStyle: TextStyle(
                      color: Lively.textTertiary(b),
                      fontSize: Lively.tBody,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: Lively.s2),
                  ),
                  onChanged: w.onChanged,
                ),
              ),
            ),
            const SizedBox(width: Lively.s1),

            // ── Right cluster ──
            _EffortChip(
              brightness: b,
              level: level,
              open: effortOpen,
              onTap: onToggleEffort,
            ),
            const SizedBox(width: Lively.s1),
            _VoiceButton(brightness: b, voiceState: w.voiceState, onTap: w.onVoiceToggle),
            const SizedBox(width: Lively.s1),
            _SendButton(
              brightness: b,
              isStreaming: w.isStreaming,
              ready: ready,
              isOnline: w.isOnline,
              isPending: w.isPending,
              onTap: () => w.isStreaming ? w.onStop() : w.onSubmit(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Entry point helper exposing the text field height cap hint (180 in TS —
/// applied here through a maxHeight box around the capsule in ShellScreen).
const double composerMaxInputHeight = 180;

// ── Buttons ──────────────────────────────────────────────────────────────────

class _Btn extends StatelessWidget {
  final Brightness brightness;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  const _Btn({
    required this.brightness,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.only(right: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? Lively.fill(b, 2) : Colors.transparent,
          ),
          child: Icon(
            icon,
            size: 15,
            color: onTap == null
                ? Lively.textTertiary(b)
                : Lively.textSecondary(b),
          ),
        ),
      ),
    );
  }
}

class _EffortChip extends StatelessWidget {
  final Brightness brightness;
  final String level;
  final bool open;
  final VoidCallback onTap;
  const _EffortChip({
    required this.brightness,
    required this.level,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    return Tooltip(
      message: 'Reasoning effort: $level',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: Lively.s2),
          decoration: BoxDecoration(
            color: open ? Lively.fill(b, 2) : Lively.fill(b, 1),
            borderRadius: BorderRadius.circular(Lively.composerChipRadius),
            border: Border.all(color: Lively.separator(b), width: Lively.bHairline),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(f.FluentIcons.lightning_bolt, size: 12, color: Lively.accentText(b)),
            const SizedBox(width: 4),
            Text(
              level,
              style: TextStyle(
                color: Lively.textPrimary(b),
                fontSize: Lively.tMicro,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(f.FluentIcons.chevron_down, size: 11, color: Lively.textTertiary(b)),
          ]),
        ),
      ),
    );
  }
}

class _VoiceButton extends StatelessWidget {
  final Brightness brightness;
  final VoiceState voiceState;
  final VoidCallback onTap;
  const _VoiceButton({
    required this.brightness,
    required this.voiceState,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    final active = voiceState != VoiceState.idle;
    return Tooltip(
      message: active ? 'Stop dictation' : 'Dictate',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? Lively.accent(b) : Colors.transparent,
          ),
          child: Icon(
            f.FluentIcons.microphone,
            size: 16,
            color: active ? Colors.white : Lively.textSecondary(b),
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final Brightness brightness;
  final bool isStreaming;
  final bool ready;
  final bool isOnline;
  final bool isPending;
  final VoidCallback onTap;

  const _SendButton({
    required this.brightness,
    required this.isStreaming,
    required this.ready,
    required this.isOnline,
    required this.isPending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    final enabled = (ready || isStreaming) && isOnline && !isPending;
    final accent = isStreaming ? Lively.neutral900 : Lively.accent(b);
    return Tooltip(
      message: isStreaming ? 'Stop generating' : 'Send message',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: Lively.dFast,
          curve: Lively.easeOut,
          width: Lively.sendSize,
          height: Lively.sendSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled ? accent : Lively.fill(b, 1),
            boxShadow: enabled
                ? const [
                    BoxShadow(
                        blurRadius: 10, offset: Offset(0, 4), color: Color(0x2E000000)),
                  ]
                : null,
          ),
          child: Icon(
            isStreaming ? f.FluentIcons.stop : f.FluentIcons.send,
            size: 15,
            color: enabled ? Colors.white : Lively.textTertiary(b),
          ),
        ),
      ),
    );
  }
}

// ── Popovers ─────────────────────────────────────────────────────────────────

class _PopoverShell extends StatelessWidget {
  final Brightness brightness;
  final Widget child;
  const _PopoverShell({required this.brightness, required this.child});

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(Lively.s1),
        decoration: BoxDecoration(
          color: Lively.surfaceRaised(b),
          borderRadius: BorderRadius.circular(Lively.popoverRadius),
          border: Border.all(color: Lively.separator(b), width: Lively.bHairline),
          boxShadow: const [
            BoxShadow(blurRadius: 34, offset: Offset(0, 14), color: Color(0x2E000000)),
            BoxShadow(blurRadius: 8, offset: Offset(0, 3), color: Color(0x14000000)),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _ToolsPopover extends StatelessWidget {
  final Brightness brightness;
  final List<ComposerTool> tools;
  final List<String> enabledTools;
  final ValueChanged<String> onToggleTool;
  final VoidCallback onManageTools;

  const _ToolsPopover({
    required this.brightness,
    required this.tools,
    required this.enabledTools,
    required this.onToggleTool,
    required this.onManageTools,
  });

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    return _PopoverShell(
      brightness: b,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final tool in tools)
            _ToolRow(
              brightness: b,
              tool: tool,
              on: enabledTools.contains(tool.id),
              onTap: () => onToggleTool(tool.id),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Lively.s1),
            child: Divider(
              height: 1,
              thickness: Lively.bHairline,
              color: Lively.separator(b),
            ),
          ),
          _ToolRow(
            brightness: b,
            tool: const ComposerTool(id: '__manage', label: 'Manage tools…', hint: '', icon: 'globe'),
            on: false,
            onTap: onManageTools,
          ),
        ],
      ),
    );
  }
}

IconData _toolIconData(String icon) => switch (icon) {
      'image' => f.FluentIcons.photo_collection,
      'pen' => f.FluentIcons.edit,
      'globe' => f.FluentIcons.globe,
      'code' => f.FluentIcons.code,
      _ => f.FluentIcons.toolbox,
    };

class _ToolRow extends StatelessWidget {
  final Brightness brightness;
  final ComposerTool tool;
  final bool on;
  final VoidCallback onTap;

  const _ToolRow({
    required this.brightness,
    required this.tool,
    required this.on,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    final tint = switch (tool.tint) {
      'green' => Lively.appleGreen,
      'orange' => Lively.appleOrange,
      'blue' => Lively.appleBlue,
      _ => Lively.textSecondary(b),
    };
    return _MenuItemButton(
      brightness: b,
      checked: on,
      onTap: onTap,
      leading: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? tint.withOpacity(0.15) : Lively.fill(b, 1),
        ),
        child: Icon(
          _toolIconData(tool.icon),
          size: 12,
          color: on ? tint : Lively.textSecondary(b),
        ),
      ),
      label: tool.label,
    );
  }
}

class _MenuItemButton extends StatelessWidget {
  final Brightness brightness;
  final bool checked;
  final VoidCallback onTap;
  final Widget leading;
  final String label;

  const _MenuItemButton({
    required this.brightness,
    required this.checked,
    required this.onTap,
    required this.leading,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Lively.s2, vertical: Lively.s1 + 2),
        child: Row(children: [
          leading,
          const SizedBox(width: Lively.s2),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Lively.textPrimary(b),
                fontSize: Lively.tFootnote,
              ),
            ),
          ),
          if (checked)
            Icon(f.FluentIcons.check_mark, size: 12, color: Lively.accent(b)),
        ]),
      ),
    );
  }
}

class _EffortPopover extends StatelessWidget {
  final Brightness brightness;
  final String level;
  final int effort;
  final ValueChanged<int> onEffort;

  const _EffortPopover({
    required this.brightness,
    required this.level,
    required this.effort,
    required this.onEffort,
  });

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    return _PopoverShell(
      brightness: b,
      child: SizedBox(
        width: 210,
        child: Padding(
          padding: const EdgeInsets.all(Lively.s2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(f.FluentIcons.lightning_bolt, size: 17, color: Lively.accentText(b)),
                const SizedBox(width: Lively.s2),
                Expanded(
                  child: Text(
                    level,
                    style: TextStyle(
                      color: Lively.textPrimary(b),
                      fontSize: Lively.tFootnote,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Reset to Medium',
                  child: GestureDetector(
                    onTap: () => onEffort(1),
                    child: Icon(f.FluentIcons.reset, size: 15, color: Lively.textTertiary(b)),
                  ),
                ),
              ]),
              const SizedBox(height: Lively.s2),
              _EffortSlider(brightness: b, effort: effort, onEffort: onEffort),
              const SizedBox(height: Lively.s1),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final label in _efforts)
                    Text(
                      label,
                      style: TextStyle(
                        color: _efforts.indexOf(label) == effort
                            ? Lively.textPrimary(b)
                            : Lively.textTertiary(b),
                        fontSize: Lively.tMicro,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Discrete 3-step slider with pointer capture semantics.
class _EffortSlider extends StatelessWidget {
  final Brightness brightness;
  final int effort;
  final ValueChanged<int> onEffort;

  const _EffortSlider({
    required this.brightness,
    required this.effort,
    required this.onEffort,
  });

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    final pct = effort / 2;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _fromLocal(context, d.localPosition.dx),
      onHorizontalDragUpdate: (d) => _fromLocal(context, d.localPosition.dx),
      child: Focus(
        autofocus: false,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
                event.logicalKey == LogicalKeyboardKey.arrowUp) {
              onEffort((effort + 1).clamp(0, 2));
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                event.logicalKey == LogicalKeyboardKey.arrowDown) {
              onEffort((effort - 1).clamp(0, 2));
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: SizedBox(
          height: 28,
          child: LayoutBuilder(builder: (context, constraints) {
            final trackWidth = constraints.maxWidth;
            // The track is inset by half the knob so edge positions fit.
            final usable = trackWidth - 14;
            return Stack(alignment: Alignment.centerLeft, children: [
              // Track.
              Container(
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 7),
                decoration: BoxDecoration(
                  color: Lively.fill(b, 2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Fill.
              Container(
                height: 4,
                margin: const EdgeInsets.only(left: 7),
                width: (usable * pct).clamp(0.0, usable),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: Lively.flowVertical),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Knob.
              Positioned(
                left: (7 + usable * pct - 7).clamp(0.0, usable),
                width: 14,
                top: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: Lively.separator(b), width: Lively.bThin),
                      boxShadow: const [
                        BoxShadow(blurRadius: 4, offset: Offset(0, 1), color: Color(0x33000000)),
                      ],
                    ),
                  ),
                ),
              ),
              // Step dots.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final i in [0, 1, 2])
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              i <= effort ? Lively.textSecondary(b) : Lively.textTertiary(b),
                        ),
                      ),
                  ],
                ),
              ),
            ]);
          }),
        ),
      ),
    );
  }

  void _fromLocal(BuildContext context, double dx) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final width = box.size.width - 14; // knob-inset usable width
    if (width <= 0) return;
    final ratio = ((dx - 7) / width).clamp(0.0, 1.0);
    onEffort((ratio * 2).round().clamp(0, 2));
  }
}

// ── Chips ────────────────────────────────────────────────────────────────────

class _ToolChip extends StatelessWidget {
  final Brightness brightness;
  final String label;
  final VoidCallback onRemove;
  const _ToolChip({required this.brightness, required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    return Container(
      padding: const EdgeInsets.only(left: Lively.s2, right: Lively.s1, top: 3, bottom: 3),
      decoration: BoxDecoration(
        color: Lively.fill(b, 1),
        borderRadius: BorderRadius.circular(Lively.composerChipRadius),
        border: Border.all(color: Lively.separator(b), width: Lively.bHairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(
          label,
          style: TextStyle(color: Lively.textPrimary(b), fontSize: Lively.tMicro),
        ),
        const SizedBox(width: 2),
        GestureDetector(
          onTap: onRemove,
          child: Icon(f.FluentIcons.chrome_close, size: 11, color: Lively.textTertiary(b)),
        ),
      ]),
    );
  }
}

class _AttachChip extends StatelessWidget {
  final Brightness brightness;
  final MessageAttachment attachment;
  final VoidCallback onRemove;
  const _AttachChip({
    required this.brightness,
    required this.attachment,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    final ext = (attachment.name.split('.').length > 1
            ? attachment.name.split('.').last
            : 'FILE')
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final badge = ext.length > 4 ? ext.substring(0, 4) : ext;
    return Container(
      padding: const EdgeInsets.only(left: Lively.s1, right: Lively.s1, top: 3, bottom: 3),
      decoration: BoxDecoration(
        color: Lively.surfaceRaised(b),
        borderRadius: BorderRadius.circular(Lively.rMd),
        border: Border.all(
          color: attachment.kind == 'image'
              ? Lively.accentMuted(b)
              : Lively.separator(b),
          width: Lively.bHairline,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (attachment.kind == 'image' && attachment.dataUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 20,
              height: 20,
              child: _DataImage(dataUrl: attachment.dataUrl!),
            ),
          )
        else
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Lively.fill(b, 2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              badge,
              style: TextStyle(
                color: Lively.textSecondary(b),
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 110),
          child: Text(
            attachment.name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Lively.textPrimary(b), fontSize: Lively.tMicro),
          ),
        ),
        Text(
          ' ${attachment.size < 1024 ? 1 : (attachment.size / 1024).round()}k',
          style: TextStyle(color: Lively.textTertiary(b), fontSize: Lively.tMicro),
        ),
        const SizedBox(width: 2),
        GestureDetector(
          onTap: onRemove,
          child: Icon(f.FluentIcons.chrome_close, size: 11, color: Lively.textTertiary(b)),
        ),
      ]),
    );
  }
}

class _DataImage extends StatelessWidget {
  final String dataUrl;
  const _DataImage({required this.dataUrl});

  @override
  Widget build(BuildContext context) {
    final header = RegExp(r'^data:image/[a-zA-Z+]+;base64,');
    final match = header.firstMatch(dataUrl);
    if (match == null) return const SizedBox.shrink();
    try {
      return Image.memory(
        base64Decode(dataUrl.substring(match.end)),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }
}

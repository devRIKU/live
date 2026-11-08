/// Customization overlay (M10) — personality, custom instructions, memory.
///
/// The instructions are stored as a setting (`lively.customInstructions`).
/// Port of `src/surfaces/CustomizeOverlay.tsx`.
library;

import 'package:fluent_ui/fluent_ui.dart' as f;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/settings_controller.dart';
import '../../core/theme/lively_tokens.dart';
import 'overlay_surface.dart';

const List<String> personalities = [
  'Professional — clear, neutral, structured',
  'Friendly — warm and conversational',
  'Candid — direct, opinionated',
  'Quirky — playful and surprising',
];

const String customInstructionsKey = 'lively.customInstructions';

class CustomizeOverlay extends ConsumerStatefulWidget {
  final int factCount;
  final VoidCallback onOpenMemory;
  final VoidCallback onClose;
  final void Function(String message)? onToast;

  const CustomizeOverlay({
    super.key,
    required this.factCount,
    required this.onOpenMemory,
    required this.onClose,
    this.onToast,
  });

  @override
  ConsumerState<CustomizeOverlay> createState() => _CustomizeOverlayState();
}

class _CustomizeOverlayState extends ConsumerState<CustomizeOverlay> {
  int _personality = 0;
  final _about = TextEditingController();
  final _respond = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _about.dispose();
    _respond.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final storage = ref.read(settingsControllerProvider.notifier).storage;
      final value = await storage.getSetting<Map<String, dynamic>>(customInstructionsKey);
      if (value == null || !mounted) return;
      final p = value['personality'];
      setState(() {
        _about.text = '${value['about'] ?? ''}';
        _respond.text = '${value['respond'] ?? ''}';
        if (p is int && p >= 0 && p < personalities.length) _personality = p;
      });
    } catch (_) {
      // A missing setting is not an error: the fields simply start empty.
    }
  }

  Future<void> _save() async {
    try {
      final storage = ref.read(settingsControllerProvider.notifier).storage;
      await storage.setSetting<Map<String, dynamic>>(customInstructionsKey, {
        'about': _about.text,
        'respond': _respond.text,
        'personality': _personality,
      });
      widget.onToast?.call('Custom instructions saved');
    } catch (_) {
      widget.onToast?.call('Could not save the custom instructions');
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = f.FluentTheme.of(context).brightness;

    return OverlaySurface(
      title: 'Customize Lively',
      onClose: widget.onClose,
      maxHeight: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _heading(b, 'Personality'),
                  const Spacer(),
                  OverlayBadge(
                      label: personalities[_personality].split(' — ').first,
                      color: Lively.appleGreen),
                ]),
                const SizedBox(height: Lively.s1),
                Text('Pick a starting voice. You can always override it below.',
                    style: TextStyle(
                        color: Lively.textSecondary(b), fontSize: Lively.tFootnote)),
                const SizedBox(height: Lively.s2),
                for (var i = 0; i < personalities.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Lively.s1),
                    child: Material(
                      color: i == _personality ? Lively.accentMuted(b) : Colors.transparent,
                      borderRadius: BorderRadius.circular(Lively.rMd),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(Lively.rMd),
                        onTap: () => setState(() => _personality = i),
                        child: Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: Lively.s3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(Lively.rMd),
                            border: Border.all(
                              color: i == _personality
                                  ? Colors.transparent
                                  : Lively.separator(b),
                              width: Lively.bThin,
                            ),
                          ),
                          child: Row(children: [
                            if (i == _personality) ...[
                              Icon(f.FluentIcons.check_mark,
                                  size: 13, color: Lively.accentText(b)),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                personalities[i],
                                style: TextStyle(
                                  color: i == _personality
                                      ? Lively.accentText(b)
                                      : Lively.textPrimary(b),
                                  fontSize: Lively.tFootnote,
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heading(b, 'Custom instructions'),
                const SizedBox(height: Lively.s3),
                _label(b, 'What should Lively know about you?'),
                f.TextBox(
                  controller: _about,
                  maxLines: 3,
                  placeholder:
                      'e.g. I am a frontend engineer. I ship in React and Tailwind.',
                ),
                const SizedBox(height: Lively.s3),
                _label(b, 'How should Lively respond?'),
                f.TextBox(
                  controller: _respond,
                  maxLines: 3,
                  placeholder: 'e.g. Keep replies concise. Use British English. Cite sources.',
                ),
                const SizedBox(height: Lively.s3),
                Align(
                  alignment: Alignment.centerRight,
                  child: f.FilledButton(onPressed: _save, child: const Text('Save')),
                ),
              ],
            ),
          ),
          SurfaceCard(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _heading(b, 'Memory'),
                  const Spacer(),
                  OverlayBadge(label: '${widget.factCount}', color: Lively.textSecondary(b)),
                ]),
                const SizedBox(height: Lively.s1),
                Text(
                    'Lively remembers facts you have taught it. Review or clear them any time.',
                    style: TextStyle(
                        color: Lively.textSecondary(b), fontSize: Lively.tFootnote)),
                const SizedBox(height: Lively.s2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: f.Button(
                    onPressed: widget.onOpenMemory,
                    child: const Text('Manage memory'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heading(Brightness b, String text) => Text(text,
      style: TextStyle(
          color: Lively.textPrimary(b),
          fontSize: Lively.tFootnote,
          fontWeight: FontWeight.w600));

  Widget _label(Brightness b, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: TextStyle(
                color: Lively.textSecondary(b),
                fontSize: Lively.tMicro,
                fontWeight: FontWeight.w600)),
      );
}

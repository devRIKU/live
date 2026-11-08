/// Voice dock (M9) — push-to-talk, docked above the composer.
///
/// The microphone has four legible states. A denied microphone permission
/// fails with an explanation rather than leaving a dead button.
/// Port of `src/surfaces/VoiceDock.tsx`.
library;

import 'package:fluent_ui/fluent_ui.dart' as f;
import 'package:flutter/material.dart';

import '../../core/services/adapters/voice_adapter.dart';
import '../../core/theme/lively_tokens.dart';

/// The current voice phase.
enum VoicePhase { idle, listening, processing, speaking }

class VoiceDock extends StatelessWidget {
  final VoicePhase phase;
  final String? error;
  final VoidCallback onEnd;

  const VoiceDock({
    super.key,
    required this.phase,
    this.error,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final b = _bOf(context);
    final copy = _COPY[phase]!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Lively.s3, vertical: Lively.s2),
      decoration: BoxDecoration(
        color: Lively.surfaceRaised(b),
        border: Border(
          top: BorderSide(color: Lively.separator(b), width: Lively.bHairline),
        ),
      ),
      child: Row(
        children: [
          Icon(f.FluentIcons.microphone, size: 16, color: Lively.textTertiary(b)),
          const SizedBox(width: Lively.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                  text: TextSpan(
                    style: TextStyle(color: Lively.textPrimary(b), fontSize: Lively.tFootnote),
                    children: [
                      TextSpan(
                        text: copy.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: ' — ${error ?? copy.body}'),
                    ],
                  ),
                ),
                const SizedBox(height: Lively.s1),
                // Wave animation
                _Wave(phase: phase, brightness: b),
              ],
            ),
          ),
          if (phase != VoicePhase.idle) ...[
            const SizedBox(width: Lively.s2),
            FilledButton(
              onPressed: onEnd,
              style: FilledButton.styleFrom(
                backgroundColor: Lively.accent(b),
                foregroundColor: Lively.accentText(b),
                minimumSize: const Size(0, Lively.btnHeight),
                padding: const EdgeInsets.symmetric(horizontal: Lively.s3),
              ),
              child: const Text('End'),
            ),
          ],
        ],
      ),
    );
  }

  Brightness _bOf(BuildContext context) => f.FluentTheme.of(context).brightness;
}

const Map<VoicePhase, _VoiceCopy> _COPY = {
  VoicePhase.idle: _VoiceCopy(
    label: 'Push-to-talk',
    body: 'Click the mic to start dictating.',
  ),
  VoicePhase.listening: _VoiceCopy(
    label: 'Listening',
    body: 'Speak now — click End when you are done.',
  ),
  VoicePhase.processing: _VoiceCopy(
    label: 'Transcribing',
    body: 'Turning what you said into text.',
  ),
  VoicePhase.speaking: _VoiceCopy(
    label: 'Speaking',
    body: 'The reply is being read aloud.',
  ),
};

class _VoiceCopy {
  final String label;
  final String body;
  const _VoiceCopy({required this.label, required this.body});
}

/// Simple animated wave bars while listening/processing.
class _Wave extends StatefulWidget {
  final VoicePhase phase;
  final Brightness brightness;
  const _Wave({required this.phase, required this.brightness});

  @override
  State<_Wave> createState() => _WaveState();
}

class _WaveState extends State<_Wave> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<Animation<double>> _bars;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _bars = List.generate(5, (i) {
      return Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(i * 0.1, 0.6 + i * 0.1, curve: Curves.easeInOut),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.brightness;
    final active = widget.phase == VoicePhase.listening ||
        widget.phase == VoicePhase.processing;

    if (!active) return const SizedBox(height: 4);

    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 5; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Container(
                  width: 3,
                  height: 12 * _bars[i].value,
                  decoration: BoxDecoration(
                    color: Lively.accent(b).withValues(alpha: 0.6 + 0.4 * _bars[i].value),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
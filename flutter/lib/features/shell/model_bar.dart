/// Model bar (M1) — the model pill, the provider status dots, the context
/// meter, and the "bounded" marker that says the failover is not going to
/// loop. Port of `src/shell/ModelBar.tsx`.
library;

import 'package:fluent_ui/fluent_ui.dart' as f;
import 'package:flutter/material.dart';

import '../../core/theme/lively_tokens.dart';

Brightness _bOf(BuildContext context) => f.FluentTheme.of(context).brightness;

class ProviderStatus {
  final String id;
  final String name;
  final String model;
  /// 'available' | 'rate-limited' | 'degraded' | 'down'
  final String state;

  /// Every model the provider offers, for the picker.
  final List<ModelBarOption> models;
  const ProviderStatus({
    required this.id,
    required this.name,
    required this.model,
    required this.state,
    required this.models,
  });
}

class ModelBarOption {
  final String id;
  final String label;
  const ModelBarOption({required this.id, required this.label});
}

class ContextMeterState {
  final int used;
  final int limit;
  final double ratio;
  /// 'ok' | 'warn' | 'critical'
  final String level;
  const ContextMeterState({
    required this.used,
    required this.limit,
    required this.ratio,
    required this.level,
  });
}

Color _stateColor(String state) => switch (state) {
      'available' => Lively.appleGreen,
      'rate-limited' => Lively.appleOrange,
      'degraded' => Lively.appleOrange,
      'down' => Lively.appleRed,
      _ => Lively.appleGray,
    };

class ModelBar extends StatelessWidget {
  final List<ProviderStatus> providers;
  final String activeId;
  final VoidCallback onPick;

  /// Context state of the last request; hidden before the first send.
  final ContextMeterState? contextState;

  const ModelBar({
    super.key,
    required this.providers,
    required this.activeId,
    required this.onPick,
    this.contextState,
  });

  @override
  Widget build(BuildContext context) {
    final b = _bOf(context);
    final meter = contextState;
    final active = providers.where((p) => p.id == activeId).firstOrNull ?? providers.firstOrNull;
    final activeModel = active == null
        ? null
        : (active.models.where((m) => m.id == active.model).firstOrNull ??
            active.models.firstOrNull);

    return Row(
      children: [
        // Model pill.
        GestureDetector(
          onTap: onPick,
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: Lively.s2),
            decoration: BoxDecoration(
              color: Lively.fill(b, 1),
              borderRadius: BorderRadius.circular(Lively.rCapsule),
              border: Border.all(color: Lively.separator(b), width: Lively.bHairline),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _Dot(color: _stateColor(active?.state ?? 'available')),
              const SizedBox(width: Lively.s1),
              Text(
                activeModel?.label ?? active?.model ?? 'No model',
                style: TextStyle(
                  color: Lively.textPrimary(b),
                  fontSize: Lively.tFootnote,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(f.FluentIcons.chevron_down,
                  size: 11, color: Lively.textTertiary(b)),
            ]),
          ),
        ),
        const SizedBox(width: Lively.s2),
        // Provider status dots.
        Row(
          children: [
            for (final provider in providers)
              Tooltip(
                message: '${provider.name}: ${provider.state}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: _Dot(color: _stateColor(provider.state), size: 7),
                ),
              ),
          ],
        ),
        const Spacer(),
        // Context meter.
        if (meter != null)
          Tooltip(
            message:
                'Context: ${_formatTokens(meter.used)} of ${_formatTokens(meter.limit)} tokens used',
            child: Row(children: [
              // Bar.
              Container(
                width: 56,
                height: 4,
                decoration: BoxDecoration(
                  color: Lively.fill(b, 2),
                  borderRadius: BorderRadius.circular(2),
                ),
                clipBehavior: Clip.hardEdge,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: meter.ratio.clamp(0.02, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: switch (meter.level) {
                        'critical' => Lively.appleRed,
                        'warn' => Lively.appleOrange,
                        _ => Lively.accent(b),
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Lively.s2),
              Text(
                '${_formatTokens(meter.used)} / ${_formatTokens(meter.limit)}',
                style: TextStyle(
                  color: Lively.textTertiary(b),
                  fontSize: Lively.tMicro,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ]),
          ),
        if (meter != null) const SizedBox(width: Lively.s2),
        // Bounded badge.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Lively.s2, vertical: 2),
          decoration: BoxDecoration(
            color: Lively.appleGreen.withOpacity(0.12),
            borderRadius: BorderRadius.circular(Lively.rCapsule),
          ),
          child: Text(
            'bounded',
            style: TextStyle(
              color: Lively.appleGreen,
              fontSize: Lively.tMicro,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final double size;
  const _Dot({required this.color, this.size = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            blurRadius: 4,
            color: color.withOpacity(0.35),
          ),
        ],
      ),
    );
  }
}

/// Compact token count — same output as `chat_tokens.formatTokens`.
String _formatTokens(num value) {
  if (value <= 0) return '0';
  if (value < 1000) return value.round().toString();
  if (value < 1000000) {
    final k = value / 1000;
    final text = k >= 100 ? k.round().toString() : k.toStringAsFixed(1).replaceAll('.0', '');
    return '${text}k';
  }
  final m = value / 1000000;
  return '${m.toStringAsFixed(1).replaceAll('.0', '')}M';
}

/// Model overlay (M12) — every provider is a separate account, and every
/// account offers several models with different windows and capabilities.
///
/// Switching changes which key is attached server-side. The app never sees
/// a key, so the list carries no credential state.
/// Port of `src/surfaces/ModelOverlay.tsx`.
library;

import 'package:fluent_ui/fluent_ui.dart' as f;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/chat/backend_providers.dart';
import '../../core/services/providers_registry.dart';
import '../../core/theme/lively_tokens.dart';
import 'overlay_surface.dart';

String _formatTokens(int tokens) {
  if (tokens >= 1000000) {
    final m = tokens / 1000000;
    return '${m == m.roundToDouble() ? m.toInt() : m.toStringAsFixed(1)}M';
  }
  if (tokens >= 1000) return '${(tokens / 1000).round()}k';
  return '$tokens';
}

Color _stateColor(ProviderState s) => switch (s) {
      ProviderState.available => Lively.appleGreen,
      ProviderState.rateLimited || ProviderState.degraded => Lively.orange500,
      ProviderState.down => Lively.appleRed,
    };

String _stateLabel(ProviderState s) => switch (s) {
      ProviderState.available => 'available',
      ProviderState.rateLimited => 'rate limited',
      ProviderState.degraded => 'degraded',
      ProviderState.down => 'down',
    };

class ModelOverlay extends ConsumerWidget {
  final String activeProviderId;
  final String activeModelId;
  final void Function(String providerId, String modelId) onSelect;
  final VoidCallback onClose;

  const ModelOverlay({
    super.key,
    required this.activeProviderId,
    required this.activeModelId,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = f.FluentTheme.of(context).brightness;
    final live = ref.watch(backendProvidersProvider).liveProviders;

    return OverlaySurface(
      title: 'Choose a model',
      onClose: onClose,
      maxHeight: 520,
      badge: f.Button(
        onPressed: () => ref.read(backendProvidersProvider.notifier).refresh(),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(f.FluentIcons.refresh, size: 12),
          SizedBox(width: 6),
          Text('Refresh live models'),
        ]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final provider in live) ...[
            _ProviderHeader(provider: provider),
            for (final model in provider.models)
              _ModelRow(
                model: model,
                active: provider.id == activeProviderId && model.id == activeModelId,
                onTap: () => onSelect(provider.id, model.id),
              ),
            const SizedBox(height: Lively.s3),
          ],
          SurfaceCallout(
            tone: 'info',
            icon: f.FluentIcons.shield,
            children: [
              Text(
                'Every provider is a separate account with its own key. Switching changes '
                'which key is attached server-side — the app never sees it.',
                style: TextStyle(color: Lively.textSecondary(b), fontSize: Lively.tFootnote),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProviderHeader extends StatelessWidget {
  final LlmProvider provider;
  const _ProviderHeader({required this.provider});

  @override
  Widget build(BuildContext context) {
    final b = f.FluentTheme.of(context).brightness;
    final color = _stateColor(provider.state);
    return Padding(
      padding: const EdgeInsets.only(bottom: Lively.s2),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: Lively.s2),
          Text(provider.name,
              style: TextStyle(
                  color: Lively.textPrimary(b),
                  fontSize: Lively.tFootnote,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: Lively.s2),
          Text(_stateLabel(provider.state),
              style: TextStyle(color: Lively.textTertiary(b), fontSize: Lively.tMicro)),
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  final ModelOption model;
  final bool active;
  final VoidCallback onTap;
  const _ModelRow({required this.model, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final b = f.FluentTheme.of(context).brightness;
    final fg = active ? Lively.accentText(b) : Lively.textPrimary(b);
    final meta = '${_formatTokens(model.contextLimit)} context · '
        '${_formatTokens(model.maxOutput)} out'
        '${model.vision ? ' · vision' : ''}'
        '${model.tools ? ' · tools' : ''}';

    return Padding(
      padding: const EdgeInsets.only(bottom: Lively.s2),
      child: Material(
        color: active ? Lively.accentMuted(b) : Colors.transparent,
        borderRadius: BorderRadius.circular(Lively.rMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(Lively.rMd),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: Lively.s4, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Lively.rMd),
              border: Border.all(
                color: active ? Colors.transparent : Lively.separator(b),
                width: Lively.bThin,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(model.label,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: fg,
                                    fontSize: Lively.tFootnote,
                                    fontWeight: FontWeight.w600)),
                          ),
                          if (model.isLive) ...[
                            const SizedBox(width: 6),
                            OverlayBadge(label: 'LIVE', color: Lively.appleGreen),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(meta,
                          style: TextStyle(
                              color: Lively.textSecondary(b), fontSize: Lively.tMicro)),
                    ],
                  ),
                ),
                if (active) Icon(f.FluentIcons.check_mark, size: 13, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

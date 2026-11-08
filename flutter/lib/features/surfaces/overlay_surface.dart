/// Overlay shell — the frame every full-surface milestone shares.
///
/// Research, customization, the tool picker and the model picker are all
/// the same surface with different content, so they share one frame.
/// Port of `src/surfaces/Overlay.tsx`.
///
/// The body scrolls inside a bounded height: the shell stacks these frames
/// in a column above the composer, so an unbounded one would overflow it.
library;

import 'package:fluent_ui/fluent_ui.dart' as f;
import 'package:flutter/material.dart';

import '../../core/theme/lively_tokens.dart';

class OverlaySurface extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  final Widget child;
  final Widget? badge;
  final double maxHeight;

  const OverlaySurface({
    super.key,
    required this.title,
    required this.onClose,
    required this.child,
    this.badge,
    this.maxHeight = 460,
  });

  @override
  Widget build(BuildContext context) {
    final b = f.FluentTheme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Lively.s3, Lively.s2, Lively.s3, 0),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          decoration: BoxDecoration(
            color: Lively.surfaceRaised(b),
            borderRadius: BorderRadius.circular(Lively.rLg),
            border: Border.all(color: Lively.separator(b), width: Lively.bHairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Lively.s3, Lively.s2, Lively.s2, Lively.s1),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Lively.textPrimary(b),
                          fontSize: Lively.tSubhead,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: Lively.s2),
                      badge!,
                    ],
                    const Spacer(),
                    IconButton(
                      icon: Icon(f.FluentIcons.chrome_close,
                          size: 14, color: Lively.textSecondary(b)),
                      onPressed: onClose,
                      tooltip: 'Close $title',
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: Lively.bHairline, color: Lively.separator(b)),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(Lively.s3),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small rounded status badge.
class OverlayBadge extends StatelessWidget {
  final String label;
  final Color color;
  const OverlayBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: Lively.tMicro, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// A tinted note with a leading icon. [tone] is 'info' | 'warn' | 'bad'.
class SurfaceCallout extends StatelessWidget {
  final String tone;
  final IconData icon;
  final List<Widget> children;
  const SurfaceCallout({
    super.key,
    required this.tone,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final b = f.FluentTheme.of(context).brightness;
    final color = switch (tone) {
      'bad' => Lively.appleRed,
      'warn' => Lively.orange500,
      _ => Lively.accent(b),
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: Lively.s3),
      padding: const EdgeInsets.all(Lively.s3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Lively.rMd),
        border: Border.all(color: color.withValues(alpha: 0.4), width: Lively.bThin),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: Lively.s2),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ],
      ),
    );
  }
}

/// A raised card used inside overlays.
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;
  const SurfaceCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.only(bottom: Lively.s3),
  });

  @override
  Widget build(BuildContext context) {
    final b = f.FluentTheme.of(context).brightness;
    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.all(Lively.s3),
      decoration: BoxDecoration(
        color: Lively.fill(b, 1),
        borderRadius: BorderRadius.circular(Lively.rLg),
        border: Border.all(color: Lively.separator(b), width: Lively.bHairline),
      ),
      child: child,
    );
  }
}

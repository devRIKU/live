/// Permission card (M6) — the tool call asked for in the message flow.
///
/// The request is inline, not in a modal, because the turn is paused and the
/// user is reading the message that asked for it. Every call is a separate
/// decision: there is no "always allow". Port of
/// `src/surfaces/PermissionCard.tsx`.
library;

import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart' as f;
import 'package:flutter/material.dart' hide Card;

import '../../core/models/models.dart';
import '../../core/theme/lively_tokens.dart';

class PermissionCard extends StatelessWidget {
  final ToolCall call;
  final VoidCallback onAllow;
  final VoidCallback onDeny;

  const PermissionCard({
    super.key,
    required this.call,
    required this.onAllow,
    required this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    final b = f.FluentTheme.of(context).brightness;
    final scope = call.name.startsWith('mcp:') ? 'local mcp' : 'tool';

    return Container(
      padding: const EdgeInsets.all(Lively.s3),
      decoration: BoxDecoration(
        color: Lively.surfaceRaised(b),
        borderRadius: BorderRadius.circular(Lively.rLg),
        border: Border.all(
          color: Lively.orange500.withValues(alpha: 0.55),
          width: Lively.bHairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Head
          Row(
            children: [
              Icon(f.FluentIcons.lightning_bolt,
                  size: 14, color: Lively.orange500),
              const SizedBox(width: Lively.s1),
              Text(
                'Permission required',
                style: TextStyle(
                  color: Lively.textPrimary(b),
                  fontSize: Lively.tFootnote,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _Badge(label: scope),
            ],
          ),
          const SizedBox(height: Lively.s2),
          // Body
          _Labeled('Tool'),
          Text(
            call.name,
            style: TextStyle(
              color: Lively.textPrimary(b),
              fontSize: Lively.tFootnote,
              fontFamily: 'Consolas, "Cascadia Mono", monospace',
            ),
          ),
          if (call.targetPath != null && call.targetPath!.isNotEmpty) ...[
            const SizedBox(height: Lively.s2),
            _Labeled('Target'),
            Text(
              call.targetPath!,
              style: TextStyle(
                color: Lively.textSecondary(b),
                fontSize: Lively.tFootnote,
                fontFamily: 'Consolas, "Cascadia Mono", monospace',
              ),
            ),
          ],
          const SizedBox(height: Lively.s2),
          _Labeled('Arguments'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Lively.s2),
            decoration: BoxDecoration(
              color: Lively.fill(b, 1),
              borderRadius: BorderRadius.circular(Lively.rMd),
            ),
            child: Text(
              const JsonEncoder.withIndent('  ').convert(call.args),
              style: TextStyle(
                color: Lively.textSecondary(b),
                fontSize: Lively.tMicro,
                fontFamily: 'Consolas, "Cascadia Mono", monospace',
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: Lively.s3),
          // Foot
          Row(
            children: [
              Expanded(
                child: Text(
                  "This runs outside the chat. Every call is a separate "
                  "decision — there is no \"always allow\".",
                  style: TextStyle(
                    color: Lively.textTertiary(b),
                    fontSize: Lively.tMicro,
                  ),
                ),
              ),
              const SizedBox(width: Lively.s2),
              OutlinedButton(
                onPressed: onDeny,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Lively.textPrimary(b),
                  side: BorderSide(color: Lively.separator(b), width: Lively.bThin),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Lively.btnRadius),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: Lively.s3, vertical: Lively.s1),
                  minimumSize: const Size(0, Lively.btnHeight),
                ),
                child: const Text('Deny'),
              ),
              const SizedBox(width: Lively.s2),
              OutlinedButton(
                onPressed: onAllow,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Lively.accentText(b),
                  side: BorderSide(color: Lively.accent(b), width: Lively.bThin),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Lively.btnRadius),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: Lively.s3, vertical: Lively.s1),
                  minimumSize: const Size(0, Lively.btnHeight),
                ),
                child: const Text('Allow'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  final String label;
  const _Labeled(this.label);

  @override
  Widget build(BuildContext context) {
    final b = f.FluentTheme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: Lively.textTertiary(b),
          fontSize: Lively.tMicro,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// A small rounded status badge (tone: warn here).
class _Badge extends StatelessWidget {
  final String label;
  const _Badge({required this.label});

  @override
  Widget build(BuildContext context) {
    final b = f.FluentTheme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Lively.orange500.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Lively.orange500,
          fontSize: Lively.tMicro,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

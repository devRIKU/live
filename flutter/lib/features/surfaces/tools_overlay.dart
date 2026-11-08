/// Tools overlay (M11) — the plugin and tool picker.
///
/// Each tool is a switch with a description. A change takes effect on the
/// next message; nothing is enabled behind the user's back.
/// Port of `src/surfaces/ToolsOverlay.tsx`.
library;

import 'package:fluent_ui/fluent_ui.dart' as f;
import 'package:flutter/material.dart';

import '../../core/theme/lively_tokens.dart';
import '../shell/composer.dart' show ComposerTool;
import 'overlay_surface.dart';

IconData _toolIcon(String icon) => switch (icon) {
      'image' => f.FluentIcons.photo_collection,
      'pen' => f.FluentIcons.edit,
      'globe' => f.FluentIcons.globe,
      'code' => f.FluentIcons.code,
      _ => f.FluentIcons.toolbox,
    };

class ToolsOverlay extends StatelessWidget {
  final List<ComposerTool> tools;
  final Set<String> enabled;
  final void Function(String id) onToggle;
  final VoidCallback onOpenTerminal;
  final VoidCallback onOpenConnectors;
  final VoidCallback onClose;

  const ToolsOverlay({
    super.key,
    required this.tools,
    required this.enabled,
    required this.onToggle,
    required this.onOpenTerminal,
    required this.onOpenConnectors,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final b = f.FluentTheme.of(context).brightness;

    return OverlaySurface(
      title: 'Tools',
      onClose: onClose,
      maxHeight: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final tool in tools)
            SurfaceCard(
              child: Row(
                children: [
                  Icon(_toolIcon(tool.icon), size: 16, color: Lively.accent(b)),
                  const SizedBox(width: Lively.s2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tool.label,
                            style: TextStyle(
                                color: Lively.textPrimary(b),
                                fontSize: Lively.tFootnote,
                                fontWeight: FontWeight.w600)),
                        if (tool.hint.isNotEmpty)
                          Text(tool.hint,
                              style: TextStyle(
                                  color: Lively.textSecondary(b),
                                  fontSize: Lively.tFootnote)),
                      ],
                    ),
                  ),
                  f.ToggleSwitch(
                    checked: enabled.contains(tool.id),
                    onChanged: (_) => onToggle(tool.id),
                  ),
                ],
              ),
            ),
          _ActionCard(
            icon: f.FluentIcons.plug_connected,
            title: 'Web connectors',
            body: 'Search, page reader, remote MCP servers and custom REST APIs.',
            action: 'Manage',
            onTap: onOpenConnectors,
          ),
          _ActionCard(
            icon: f.FluentIcons.command_prompt,
            title: 'Code agent',
            body: 'Run the agent in a scoped folder, with Stop and the exit code always visible.',
            action: 'Open terminal',
            onTap: onOpenTerminal,
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback onTap;
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final b = f.FluentTheme.of(context).brightness;
    return SurfaceCard(
      child: Row(
        children: [
          Icon(icon, size: 16, color: Lively.accent(b)),
          const SizedBox(width: Lively.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: Lively.textPrimary(b),
                        fontSize: Lively.tFootnote,
                        fontWeight: FontWeight.w600)),
                Text(body,
                    style: TextStyle(
                        color: Lively.textSecondary(b), fontSize: Lively.tFootnote)),
              ],
            ),
          ),
          const SizedBox(width: Lively.s2),
          f.Button(onPressed: onTap, child: Text(action)),
        ],
      ),
    );
  }
}

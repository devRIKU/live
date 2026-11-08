/// Sidebar — the conversation list and the account row.
/// Port of `src/shell/Sidebar.tsx` to Flutter with Lively tokens.
///
/// Manifestations of the shell's own markup: grouped conversation list,
/// inline rename/delete, an account menu at the bottom.
library;

import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart' as f;
import 'package:flutter/material.dart';

import '../../core/theme/lively_tokens.dart';

class SidebarThread {
  final String id;
  final String title;
  final int updatedAt;
  const SidebarThread({required this.id, required this.title, required this.updatedAt});
}

/// Group threads by the day they were last touched.
String groupOf(int timestamp) {
  final then = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  final startOfYesterday = startOfToday.subtract(const Duration(days: 1));
  if (!then.isBefore(startOfToday)) return 'Today';
  if (!then.isBefore(startOfYesterday)) return 'Yesterday';
  if (!then.isBefore(startOfToday.subtract(const Duration(days: 7)))) {
    return 'Previous 7 days';
  }
  return '${_months[then.month - 1]} ${then.year}';
}

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String timeOf(int timestamp) {
  final then = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final now = DateTime.now();
  final sameDay =
      then.year == now.year && then.month == now.month && then.day == now.day;
  if (sameDay) {
    return '${then.hour.toString().padLeft(2, '0')}:${then.minute.toString().padLeft(2, '0')}';
  }
  return const ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][then.weekday];
}

Brightness _bOf(BuildContext context) => f.FluentTheme.of(context).brightness;

class Sidebar extends StatefulWidget {
  final List<SidebarThread> threads;
  final String? activeThreadId;
  final ValueChanged<String> onSelectThread;
  final VoidCallback onNewThread;
  final ValueChanged<String> onDeleteThread;
  final void Function(String id, String title) onRenameThread;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenShortcuts;
  final VoidCallback onOpenAccount;
  final VoidCallback onResetDemo;
  final String accountName;

  const Sidebar({
    super.key,
    required this.threads,
    required this.activeThreadId,
    required this.onSelectThread,
    required this.onNewThread,
    required this.onDeleteThread,
    required this.onRenameThread,
    required this.onOpenSettings,
    required this.onOpenShortcuts,
    required this.onOpenAccount,
    required this.onResetDemo,
    required this.accountName,
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  String _query = '';
  bool _menuOpen = false;
  bool _resetArmed = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = _bOf(context);
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.threads
        : [for (final t in widget.threads) if (t.title.toLowerCase().contains(q)) t];

    final groups = <({String name, List<SidebarThread> items})>[];
    for (final thread in filtered) {
      final name = groupOf(thread.updatedAt);
      if (groups.isNotEmpty && groups.last.name == name) {
        groups.last.items.add(thread);
      } else {
        groups.add((name: name, items: [thread]));
      }
    }

    final initials = widget.accountName
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join('');

    return ColoredBox(
      color: b == Brightness.dark ? const Color(0xB31C1C1E) : const Color(0xB8F2F2F7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Head ──
          Padding(
            padding: const EdgeInsets.fromLTRB(Lively.s3, Lively.s3, Lively.s3, Lively.s1),
            child: Row(children: [
              const _AppMark(),
              Expanded(
                child: GestureDetector(
                  onTap: widget.onNewThread,
                  child: Text(
                    'Lively',
                    style: TextStyle(
                      color: Lively.textPrimary(b),
                      fontWeight: FontWeight.w600,
                      fontSize: Lively.tSubhead,
                    ),
                  ),
                ),
              ),
              _SideButton(
                icon: f.FluentIcons.add,
                label: 'New chat',
                onTap: widget.onNewThread,
                brightness: b,
              ),
            ]),
          ),

          // ── Search ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Lively.s3, vertical: Lively.s1),
            child: SizedBox(
              height: Lively.btnHeight,
              child: f.TextBox(
                placeholder: 'Search conversations',
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          ),

          // ── Conversation list ──
          Expanded(
            child: groups.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(Lively.s4),
                    child: Text(
                      widget.threads.isEmpty
                          ? 'No conversations yet'
                          : 'Nothing matches that search.',
                      style: TextStyle(
                        color: Lively.textTertiary(b),
                        fontSize: Lively.tFootnote,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: Lively.s4),
                    children: [
                      for (final group in groups) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              Lively.s3, Lively.s4, Lively.s3, Lively.s1),
                          child: Text(
                            group.name,
                            style: TextStyle(
                              color: Lively.textTertiary(b),
                              fontSize: Lively.tMicro,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        for (final thread in group.items)
                          _ConversationRow(
                            thread: thread,
                            selected: thread.id == widget.activeThreadId,
                            brightness: b,
                            onTap: () => widget.onSelectThread(thread.id),
                            onRename: () => _rename(thread),
                            onDelete: () => _confirmDelete(thread),
                          ),
                      ],
                    ],
                  ),
          ),

          // ── Account menu ──
          Padding(
            padding: const EdgeInsets.all(Lively.s2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_menuOpen)
                  _MenuCard(
                    brightness: b,
                    children: [
                      const _MenuLabel('Account'),
                      _MenuItem(
                        icon: f.FluentIcons.contact,
                        label: 'Profile & plan',
                        brightness: b,
                        onTap: () {
                          setState(() => _menuOpen = false);
                          widget.onOpenAccount();
                        },
                      ),
                      _MenuItem(
                        icon: f.FluentIcons.settings,
                        label: 'Settings',
                        brightness: b,
                        onTap: () {
                          setState(() => _menuOpen = false);
                          widget.onOpenSettings();
                        },
                      ),
                      _MenuItem(
                        icon: f.FluentIcons.keyboard_classic,
                        label: 'Keyboard shortcuts',
                        brightness: b,
                        onTap: () {
                          setState(() => _menuOpen = false);
                          widget.onOpenShortcuts();
                        },
                      ),
                      const _MenuSeparator(),
                      _MenuItem(
                        icon: f.FluentIcons.reset,
                        label: _resetArmed ? 'Tap again to reset' : 'Reset demo',
                        danger: true,
                        brightness: b,
                        onTap: () {
                          if (!_resetArmed) {
                            setState(() => _resetArmed = true);
                            _resetTimer?.cancel();
                            _resetTimer = Timer(const Duration(seconds: 4), () {
                              if (mounted) setState(() => _resetArmed = false);
                            });
                            return;
                          }
                          _resetTimer?.cancel();
                          setState(() => _resetArmed = false);
                          widget.onResetDemo();
                        },
                      ),
                    ],
                  ),
                Row(children: [
                  Container(
                    width: Lively.btnHeight,
                    height: Lively.btnHeight,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Lively.accent(b),
                    ),
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: Lively.tFootnote,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: Lively.s2),
                  Expanded(
                    child: Text(
                      widget.accountName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Lively.textPrimary(b),
                        fontSize: Lively.tFootnote,
                      ),
                    ),
                  ),
                  _MiniAction(
                    icon: _menuOpen
                        ? f.FluentIcons.chevron_down
                        : f.FluentIcons.chevron_up,
                    brightness: b,
                    tooltip: 'Account',
                    onTap: () => setState(() => _menuOpen = !_menuOpen),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(SidebarThread thread) async {
    final controller = TextEditingController(text: thread.title);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        final db = _bOf(context);
        return Dialog(
          backgroundColor: Lively.surfaceRaised(db),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Lively.popoverRadius),
            side: BorderSide(color: Lively.separator(db), width: Lively.bHairline),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Lively.s4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Rename conversation',
                    style: TextStyle(
                        color: Lively.textPrimary(db),
                        fontSize: Lively.tHeadline,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: Lively.s3),
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: TextStyle(color: Lively.textPrimary(db), fontSize: Lively.tBody),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Lively.fill(db, 1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Lively.btnRadius),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
                ),
                const SizedBox(height: Lively.s4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: Text('Cancel',
                          style: TextStyle(color: Lively.textSecondary(db))),
                    ),
                    const SizedBox(width: Lively.s2),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Lively.accent(db),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.of(context).pop(controller.text.trim()),
                      child: const Text('Rename'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (result != null && result.isNotEmpty && mounted) {
      widget.onRenameThread(thread.id, result);
    }
  }

  Future<void> _confirmDelete(SidebarThread thread) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final db = _bOf(context);
        return Dialog(
          backgroundColor: Lively.surfaceRaised(db),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Lively.popoverRadius),
            side: BorderSide(color: Lively.separator(db), width: Lively.bHairline),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Lively.s4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Delete “${thread.title}”?',
                    style: TextStyle(
                        color: Lively.textPrimary(db),
                        fontSize: Lively.tHeadline,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: Lively.s2),
                Text(
                  'This conversation will be removed permanently.',
                  style: TextStyle(
                      color: Lively.textSecondary(db), fontSize: Lively.tFootnote),
                ),
                const SizedBox(height: Lively.s4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text('Cancel',
                          style: TextStyle(color: Lively.textSecondary(db))),
                    ),
                    const SizedBox(width: Lively.s2),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Lively.appleRed.withOpacity(0.15),
                        foregroundColor: Lively.appleRed,
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (confirmed == true && mounted) widget.onDeleteThread(thread.id);
  }
}

class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    final b = _bOf(context);
    return Padding(
      padding: const EdgeInsets.only(right: Lively.s2),
      child: SizedBox(
        width: 18,
        height: 18,
        child: CustomPaint(painter: _AppMarkPainter(Lively.textPrimary(b))),
      ),
    );
  }
}

/// Mistral-style pixel emblem: chunky pixels, one accent pixel.
class _AppMarkPainter extends CustomPainter {
  final Color color;
  _AppMarkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 5;
    final inset = cell * 0.07;
    final radius = Radius.circular(cell * 0.22);

    void pixel(int x, int y, Paint paint) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x * cell + inset,
            y * cell + inset,
            cell - inset * 2,
            cell - inset * 2,
          ),
          radius,
        ),
        paint,
      );
    }

    final main = Paint()..color = color;
    const pixels = [(0, 2), (1, 2), (2, 1), (2, 2), (3, 1), (1, 3)];
    for (final (x, y) in pixels) {
      pixel(x, y, main);
    }
    // Accent pixel — the flow spectrum orange.
    pixel(3, 3, Paint()..color = Lively.orange500);
  }

  @override
  bool shouldRepaint(covariant _AppMarkPainter old) => old.color != color;
}

class _SideButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Brightness brightness;
  final VoidCallback onTap;

  const _SideButton({
    required this.icon,
    required this.label,
    required this.brightness,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Lively.s2, vertical: Lively.s1),
          decoration: BoxDecoration(
            color: Lively.fill(b, 1),
            borderRadius: BorderRadius.circular(Lively.rMd),
          ),
          child: Icon(icon, size: 14, color: Lively.textSecondary(b)),
        ),
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  final SidebarThread thread;
  final bool selected;
  final Brightness brightness;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _ConversationRow({
    required this.thread,
    required this.selected,
    required this.brightness,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Lively.s1, vertical: 1),
      child: Material(
        color: selected ? Lively.fill(b, 2) : Colors.transparent,
        borderRadius: BorderRadius.circular(Lively.rMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(Lively.rMd),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                Lively.s2, Lively.s1, Lively.s1, Lively.s1),
            child: Row(children: [
              Expanded(
                child: Text(
                  thread.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Lively.textPrimary(b) : Lively.textSecondary(b),
                    fontSize: Lively.tCallout,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              Text(
                timeOf(thread.updatedAt),
                style: TextStyle(
                  color: Lively.textTertiary(b),
                  fontSize: Lively.tMicro,
                ),
              ),
              _MiniAction(
                icon: f.FluentIcons.edit,
                brightness: b,
                tooltip: 'Rename',
                onTap: onRename,
              ),
              _MiniAction(
                icon: f.FluentIcons.delete,
                brightness: b,
                tooltip: 'Delete',
                onTap: onDelete,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final Brightness brightness;
  final String tooltip;
  final VoidCallback onTap;

  const _MiniAction({
    required this.icon,
    required this.brightness,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: GestureDetector(
          onTap: onTap,
          child: Icon(icon, size: 12, color: Lively.textTertiary(b)),
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final Brightness brightness;
  final List<Widget> children;

  const _MenuCard({required this.brightness, required this.children});

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    return Container(
      margin: const EdgeInsets.only(bottom: Lively.s2),
      padding: const EdgeInsets.all(Lively.s1),
      decoration: BoxDecoration(
        color: Lively.surfaceRaised(b),
        borderRadius: BorderRadius.circular(Lively.popoverRadius),
        border: Border.all(color: Lively.separator(b), width: Lively.bHairline),
        boxShadow: const [
          BoxShadow(blurRadius: 34, offset: Offset(0, 12), color: Color(0x2E000000)),
          BoxShadow(blurRadius: 8, offset: Offset(0, 2), color: Color(0x14000000)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _MenuLabel extends StatelessWidget {
  final String text;
  const _MenuLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final b = _bOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Lively.s3, vertical: Lively.s1),
      child: Text(
        text,
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

class _MenuSeparator extends StatelessWidget {
  const _MenuSeparator();

  @override
  Widget build(BuildContext context) {
    final b = _bOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Lively.s1),
      child: Divider(height: 1, color: Lively.separator(b), thickness: Lively.bHairline),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  final Brightness brightness;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.brightness,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    final color = danger ? Lively.appleRed : Lively.textPrimary(b);
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Lively.s3, vertical: Lively.s2),
        child: Row(children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: Lively.s3),
          Expanded(
            child: Text(label, style: TextStyle(color: color, fontSize: Lively.tCallout)),
          ),
        ]),
      ),
    );
  }
}

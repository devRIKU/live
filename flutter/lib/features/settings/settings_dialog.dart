/// Settings (M5) — a Fluent dialog, not a sidebar page.
///
/// Port of `src/app/SettingsDialog.tsx`. Settings are a detour, not a place
/// you live: every control writes to storage and takes effect immediately —
/// there is no Save button for a switch, and the Save button on a text field
/// confirms what it did.
///
/// All values are read from and persisted through [SettingsController]
/// (Riverpod), which backs onto a [StorageAdapter] key-value store. Brightness
/// is taken from [FluentTheme] so the `Lively` tokens resolve for the active
/// light/dark state.
library;

import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
// `widgets.dart` exports dart:ui's `TextBox` (a text-layout rect); fluent_ui's
// text input of the same name is the one used here.
import 'package:flutter/widgets.dart' hide TextBox;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/services/chat/model_params.dart' show paramBounds;
import '../../core/services/providers_registry.dart';
import '../../core/services/storage/export_import.dart';
import '../../core/state/settings_controller.dart';
import '../../core/theme/lively_tokens.dart';

enum SettingsSection { general, profile, providers, storage, memory, shortcuts }

const _sections = <SettingsSection, String>{
  SettingsSection.general: 'General',
  SettingsSection.profile: 'Profile',
  SettingsSection.providers: 'Providers',
  SettingsSection.storage: 'Storage',
  SettingsSection.memory: 'Memory',
  SettingsSection.shortcuts: 'Shortcuts',
};

const _shortcuts = <(String, String)>[
  ('Enter', 'Send the message'),
  ('Shift + Enter', 'New line'),
  ('Esc', 'Close a popover or this dialog'),
  ('↑ / ↓', 'Move through the conversation'),
  ('Ctrl + K', 'Search conversations'),
];

Brightness _b(BuildContext c) => FluentTheme.of(c).brightness;

String _msg(Object e) => e is Exception
    ? e.toString().replaceFirst('Exception: ', '')
    : e.toString();

class _KeyError {
  final String id;
  final String message;
  const _KeyError(this.id, this.message);
}

// ─── Dialog ───────────────────────────────────────────────────────────────

class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({
    super.key,
    required this.onClose,
    this.onCustomize,
    this.onToast,
  });

  final VoidCallback onClose;

  /// Open the assistant-customization surface (voice, instructions, memory).
  final VoidCallback? onCustomize;

  final void Function(String message)? onToast;

  /// Show the dialog modally.
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onClose,
    VoidCallback? onCustomize,
    void Function(String message)? onToast,
  }) {
    return showDialog(
      context: context,
      builder: (_) => SettingsDialog(
        onClose: onClose,
        onCustomize: onCustomize,
        onToast: onToast,
      ),
    );
  }

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  SettingsSection _section = SettingsSection.general;

  // Transient provider-key UI state.
  Map<String, bool> _present = {};
  final Map<String, TextEditingController> _drafts = {};
  String? _busy;
  _KeyError? _keyError;

  // Status callout (export/import + profile save confirmations).
  String? _status;

  // Text fields.
  late final TextEditingController _nameCtrl;
  late final TextEditingController _maxTokensCtrl;
  late final FocusNode _nameFocus;
  late final FocusNode _maxTokensFocus;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _maxTokensCtrl = TextEditingController();
    _nameFocus = FocusNode();
    _maxTokensFocus = FocusNode();
    // Keys are probed after the first frame (async secret lookup).
    Future.microtask(_refreshKeys);
  }

  @override
  void dispose() {
    for (final c in _drafts.values) {
      c.dispose();
    }
    _nameCtrl.dispose();
    _maxTokensCtrl.dispose();
    _nameFocus.dispose();
    _maxTokensFocus.dispose();
    super.dispose();
  }

  SettingsController get _controller =>
      ref.read(settingsControllerProvider.notifier);

  // ── Provider keys ────────────────────────────────────────────────────────

  Future<void> _refreshKeys() async {
    final results = <String, bool>{};
    for (final p in providers) {
      try {
        results[p.id] = await _controller.secrets.hasSecret(p.id);
      } catch (_) {
        results[p.id] = false;
      }
    }
    if (mounted) setState(() => _present = results);
  }

  TextEditingController _draftFor(String id) =>
      _drafts[id] ??= TextEditingController();

  Future<void> _saveKey(LlmProvider provider) async {
    final value = (_drafts[provider.id]?.text ?? '').trim();
    if (value.isEmpty) {
      setState(() => _keyError = _KeyError(provider.id, 'Enter an API key first.'));
      return;
    }
    setState(() {
      _busy = provider.id;
      _keyError = null;
    });
    try {
      await _controller.secrets.setSecret(provider.id, value);
      setState(() => _drafts[provider.id]?.clear());
      await _refreshKeys();
      widget.onToast?.call('API key saved for ${provider.name}');
    } catch (e) {
      setState(() => _keyError = _KeyError(provider.id, _msg(e)));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _removeKey(LlmProvider provider) async {
    setState(() {
      _busy = provider.id;
      _keyError = null;
    });
    try {
      await _controller.secrets.deleteSecret(provider.id);
      await _refreshKeys();
      widget.onToast?.call('API key removed for ${provider.name}');
    } catch (e) {
      setState(() => _keyError = _KeyError(provider.id, _msg(e)));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  // ── Export / import ──────────────────────────────────────────────────────

  Future<void> _handleExport() async {
    try {
      await exportData(_controller.storage);
      setState(() => _status = 'All conversations exported.');
      widget.onToast?.call('All conversations exported.');
    } catch (e) {
      setState(() => _status = 'Export failed: ${_msg(e)}');
    }
  }

  Future<void> _handleImport() async {
    final path = _importPathCtrl.text.trim();
    if (path.isEmpty) {
      setState(() => _status = 'Enter the path of a .json export first.');
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      setState(() => _status = 'Import failed: no file at "$path".');
      return;
    }
    try {
      final result = await importData(_controller.storage, file);
      setState(() =>
          _status = 'Imported ${result.imported} items, skipped ${result.skipped}.');
      widget.onToast?.call('Imported ${result.imported} items.');
      await _controller.refreshFacts();
    } catch (e) {
      setState(() => _status = _msg(e));
    }
  }

  final _importPathCtrl = TextEditingController();

  // ── Memory ───────────────────────────────────────────────────────────────

  Future<void> _deleteFact(String id) async {
    try {
      await _controller.deleteFact(id);
    } catch (_) {
      setState(() => _status = 'Could not delete that fact.');
    }
  }

  Future<void> _clearFacts() async {
    try {
      await _controller.clearFacts();
    } catch (_) {
      setState(() => _status = 'Could not clear memory.');
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(settingsControllerProvider);

    // Keep text fields in sync with controller state unless the user is
    // typing in them.
    ref.listen(settingsControllerProvider.select((s) => s.accountName),
        (prev, next) {
      if (!_nameFocus.hasFocus && _nameCtrl.text != next) _nameCtrl.text = next;
    });
    ref.listen(settingsControllerProvider.select((s) => s.params.maxTokens),
        (prev, next) {
      if (!_maxTokensFocus.hasFocus && _maxTokensCtrl.text != '$next') {
        _maxTokensCtrl.text = '$next';
      }
    });

    // Seed the fields once on first load.
    if (!_nameFocus.hasFocus && _nameCtrl.text.isEmpty && state.loaded) {
      _nameCtrl.text = state.accountName;
    }
    if (!_maxTokensFocus.hasFocus && _maxTokensCtrl.text.isEmpty && state.loaded) {
      _maxTokensCtrl.text = '${state.params.maxTokens}';
    }

    final b = _b(context);

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
      title: const Text('Settings'),
      actions: [
        Button(onPressed: widget.onClose, child: const Text('Close')),
      ],
      content: SizedBox(
        height: 440,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildNav(b),
            Container(width: Lively.bThin, color: Lively.separator(b)),
            Expanded(child: _buildMain(b, state)),
          ],
        ),
      ),
    );
  }

  Widget _buildNav(Brightness b) {
    return Container(
      width: 178,
      color: Lively.surfaceSunken(b),
      padding: const EdgeInsets.symmetric(vertical: Lively.s3, horizontal: Lively.s2),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in _sections.entries)
              _navItem(b, s.key, s.value),
          ],
        ),
      ),
    );
  }

  Widget _navItem(Brightness b, SettingsSection section, String label) {
    final selected = _section == section;
    return _Hover(
      onTap: () => setState(() {
        _section = section;
        _status = null;
      }),
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: (selected || hovered) ? Lively.fill(b, 1) : null,
          borderRadius: BorderRadius.circular(Lively.rSm),
        ),
        child: Row(
          children: [
            if (selected)
              Container(
                width: 2,
                height: 14,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Lively.accent(b),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            Text(
              label,
              style: TextStyle(
                fontSize: Lively.tSubhead,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected || hovered
                    ? Lively.textPrimary(b)
                    : Lively.textSecondary(b),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMain(Brightness b, SettingsState state) {
    final children = <Widget>[
      if (_status != null) ...[
        InfoBar(
          severity: InfoBarSeverity.info,
          title: Text(
            _status!,
            style: TextStyle(
              fontSize: Lively.tMicro,
              color: Lively.textSecondary(b),
            ),
          ),
        ),
        const SizedBox(height: Lively.s4),
      ],
      switch (_section) {
        SettingsSection.general => _general(b, state),
        SettingsSection.profile => _profile(b, state),
        SettingsSection.providers => _providers(b),
        SettingsSection.storage => _storage(b),
        SettingsSection.memory => _memory(b, state),
        SettingsSection.shortcuts => _shortcutsView(b),
      },
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(Lively.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  // ── General ──────────────────────────────────────────────────────────────

  Widget _general(Brightness b, SettingsState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionBlock(b, 'Appearance', [
          _setRow(
            b,
            title: 'Theme',
            note: 'One palette with two states. “System” follows the device.',
            control: _Segmented<LivelyTheme>(
              values: LivelyTheme.values,
              labels: [for (final t in LivelyTheme.values) t.label],
              selected: state.theme,
              onChanged: (t) => _controller.setTheme(t),
            ),
          ),
        ]),
        _sectionBlock(b, 'Assistant', [
          _setRow(
            b,
            title: 'Customize Lively',
            note:
                'A starting voice, custom instructions, and the memory the assistant keeps.',
            control: Button(
              onPressed: widget.onCustomize,
              child: const Text('Customize'),
            ),
          ),
        ]),
        _sectionBlock(b, 'Generation · ${_controller.modelLabel}', [
          _paramRow(
            b,
            label: 'Temperature',
            note:
                'Lower is focused and repeatable; higher is exploratory. 0.7 is a good default.',
            value: state.params.temperature,
            display: state.params.temperature.toStringAsFixed(2),
            min: paramBounds.temperature.min,
            max: paramBounds.temperature.max,
            divisions: 40, // 0 → 2 in 0.05 steps
            onChange: _controller.setTemperature,
          ),
          _paramRow(
            b,
            label: 'Top P',
            note: 'Nucleus sampling. Leave at 1 unless the model recommends otherwise.',
            value: state.params.topP,
            display: state.params.topP.toStringAsFixed(2),
            min: paramBounds.topP.min,
            max: paramBounds.topP.max,
            divisions: 100, // 0 → 1 in 0.01 steps
            onChange: _controller.setTopP,
          ),
          _setRow(
            b,
            last: true,
            title: 'Max output tokens',
            note:
                'Cap on the reply length. The model may stop earlier; the context meter reserves this much room.',
            control: SizedBox(
              width: 120,
              child: TextBox(
                controller: _maxTokensCtrl,
                focusNode: _maxTokensFocus,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                placeholder: '2048',
                onChanged: (v) {
                  final n = int.tryParse(v.trim());
                  if (n != null) _controller.setMaxTokens(n);
                },
              ),
            ),
          ),
        ]),
      ],
    );
  }

  // ── Profile ──────────────────────────────────────────────────────────────

  Widget _profile(Brightness b, SettingsState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionBlock(b, 'Account', [
          _accountPanel(b, state),
          const SizedBox(height: Lively.s4),
          _setRow(
            b,
            last: true,
            title: 'Display name',
            note: 'The sidebar avatar is derived from this.',
            control: const SizedBox.shrink(),
          ),
          const SizedBox(height: Lively.s2),
          Row(
            children: [
              Expanded(
                child: TextBox(
                  controller: _nameCtrl,
                  focusNode: _nameFocus,
                  placeholder: 'Your name',
                ),
              ),
              const SizedBox(width: Lively.s2),
              Button(
                onPressed: () {
                  _controller.setAccountName(
                      _nameCtrl.text.trim().isEmpty
                          ? state.accountName
                          : _nameCtrl.text);
                  setState(() => _status = 'Profile updated.');
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ]),
      ],
    );
  }

  Widget _accountPanel(Brightness b, SettingsState state) {
    final initials = _initials(state.accountName);
    return Container(
      padding: const EdgeInsets.all(Lively.s3),
      decoration: BoxDecoration(
        color: Lively.surfaceSunken(b),
        borderRadius: BorderRadius.circular(Lively.rLg),
        border: Border.all(color: Lively.separator(b)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Lively.accentMuted(b),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Lively.accentText(b),
                  ),
                ),
              ),
              const SizedBox(width: Lively.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.accountName,
                      style: TextStyle(
                        fontSize: Lively.tFootnote,
                        fontWeight: FontWeight.w600,
                        color: Lively.textPrimary(b),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Free plan · 0 conversations this week',
                      style: TextStyle(
                        fontSize: Lively.tMicro,
                        color: Lively.textTertiary(b),
                      ),
                    ),
                  ],
                ),
              ),
              _badge(b, 'Active', _BadgeTone.ok),
            ],
          ),
          const SizedBox(height: Lively.s3),
          Row(
            children: [
              Expanded(
                child: Button(
                  onPressed: () =>
                      widget.onToast?.call('This build has no plan to manage.'),
                  child: const Text('Manage plan'),
                ),
              ),
              const SizedBox(width: Lively.s2),
              Expanded(
                child: Button(
                  onPressed: () => widget.onToast?.call(
                      'Use the Display name field below to edit your profile.'),
                  child: const Text('Profile'),
                ),
              ),
              const SizedBox(width: Lively.s2),
              Expanded(
                child: Button(
                  onPressed: () => widget.onToast
                      ?.call('This build has no accounts to sign out of.'),
                  child: const Text('Sign out'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Providers ────────────────────────────────────────────────────────────

  Widget _providers(Brightness b) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionBlock(b, 'Credentials', [
          for (final p in providers) ...[
            _keyRow(b, p),
            if (p != providers.last)
              Container(height: 1, color: Lively.separator(b)),
          ],
          const SizedBox(height: Lively.s3),
          InfoBar(
            severity: InfoBarSeverity.info,
            title: Text(
              'Saved keys are kept in the OS secure store — never in app files or '
              'exports — and take priority over environment variables.',
              style: TextStyle(
                fontSize: Lively.tMicro,
                color: Lively.textSecondary(b),
              ),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _keyRow(Brightness b, LlmProvider p) {
    final configured = _present[p.id] ?? false;
    final busy = _busy == p.id;
    final error = _keyError?.id == p.id ? _keyError!.message : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Lively.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: TextStyle(
                        fontSize: Lively.tFootnote,
                        fontWeight: FontWeight.w500,
                        color: Lively.textPrimary(b),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      p.envKey.isEmpty ? 'Local engine' : p.envKey,
                      style: TextStyle(
                        fontSize: Lively.tMicro,
                        color: Lively.textTertiary(b),
                      ),
                    ),
                  ],
                ),
              ),
              if (p.id == 'prototype')
                _badge(b, 'active', _BadgeTone.ok)
              else if (configured)
                _badge(b, 'configured', _BadgeTone.ok)
              else
                _badge(b, 'needs key', _BadgeTone.warn),
            ],
          ),
          if (p.envKey.isNotEmpty) ...[
            const SizedBox(height: Lively.s2),
            TextBox(
              controller: _draftFor(p.id),
              obscureText: true,
              placeholder: configured ? '••••••••' : 'paste API key',
              onChanged: (_) {
                if (_keyError?.id == p.id) setState(() => _keyError = null);
              },
            ),
            const SizedBox(height: Lively.s2),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Button(
                  onPressed: busy ? null : () => _saveKey(p),
                  child: const Text('Save'),
                ),
                if (configured) ...[
                  const SizedBox(width: Lively.s2),
                  Button(
                    onPressed: busy ? null : () => _removeKey(p),
                    child: Text(
                      'Remove',
                      style: TextStyle(color: Lively.appleRed),
                    ),
                  ),
                ],
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: Lively.s2),
              child: Text(
                'No key required',
                style: TextStyle(
                  fontSize: Lively.tFootnote,
                  color: Lively.textTertiary(b),
                ),
              ),
            ),
          if (error != null) ...[
            const SizedBox(height: Lively.s2),
            InfoBar(
              severity: InfoBarSeverity.warning,
              title: Text(
                error,
                style: TextStyle(
                  fontSize: Lively.tMicro,
                  color: Lively.textSecondary(b),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Storage ──────────────────────────────────────────────────────────────

  Widget _storage(Brightness b) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionBlock(b, 'Conversations', [
          _setRow(
            b,
            title: 'Export and import',
            note:
                'The browser and desktop builds store conversations in different places. This is the bridge between them.',
            control: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Button(
                  onPressed: _handleExport,
                  child: const Text('Export'),
                ),
                const SizedBox(width: Lively.s2),
                Button(
                  onPressed: _handleImport,
                  child: const Text('Import'),
                ),
              ],
            ),
          ),
          const SizedBox(height: Lively.s3),
          TextBox(
            controller: _importPathCtrl,
            placeholder: 'Path to openall-export-….json',
          ),
        ]),
      ],
    );
  }

  // ── Memory ───────────────────────────────────────────────────────────────

  Widget _memory(Brightness b, SettingsState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionBlock(b, 'Memory', [
          _memoryCard(b, state.facts),
        ]),
      ],
    );
  }

  Widget _memoryCard(Brightness b, List<Fact> facts) {
    return Container(
      padding: const EdgeInsets.all(Lively.s3),
      decoration: BoxDecoration(
        color: Lively.surfaceSunken(b),
        borderRadius: BorderRadius.circular(Lively.rLg),
        border: Border.all(color: Lively.separator(b)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Memory facts',
                  style: TextStyle(
                    fontSize: Lively.tFootnote,
                    fontWeight: FontWeight.w600,
                    color: Lively.textPrimary(b),
                  ),
                ),
              ),
              _badge(b, '${facts.length}', _BadgeTone.neutral),
            ],
          ),
          const SizedBox(height: Lively.s3),
          if (facts.isEmpty)
            Text(
              'Nothing remembered yet. Facts the assistant proposes are never stored until you approve them.',
              style: TextStyle(
                fontSize: Lively.tFootnote,
                color: Lively.textSecondary(b),
              ),
            )
          else
            for (final f in facts) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        f.fact,
                        style: TextStyle(
                          fontSize: Lively.tFootnote,
                          color: Lively.textPrimary(b),
                        ),
                      ),
                    ),
                    const SizedBox(width: Lively.s2),
                    Text(
                      '${f.category} · ${_date(f.createdAt)}',
                      style: TextStyle(
                        fontSize: Lively.tMicro,
                        color: Lively.textTertiary(b),
                      ),
                    ),
                    const SizedBox(width: Lively.s2),
                    _Hover(
                      onTap: () => _deleteFact(f.id),
                      builder: (context, h) => Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          '✕',
                          style: TextStyle(
                            fontSize: Lively.tMicro,
                            color: Lively.textTertiary(b),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: Lively.separator(b)),
            ],
          const SizedBox(height: Lively.s3),
          Row(
            children: [
              Button(
                onPressed: widget.onCustomize,
                child: const Text('Manage memory'),
              ),
              if (facts.isNotEmpty) ...[
                const SizedBox(width: Lively.s2),
                Button(
                  onPressed: _clearFacts,
                  child: Text('Clear all', style: TextStyle(color: Lively.appleRed)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Shortcuts ────────────────────────────────────────────────────────────

  Widget _shortcutsView(Brightness b) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionBlock(b, 'Keyboard', [
          for (final (keys, desc) in _shortcuts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 2, horizontal: 7),
                    decoration: BoxDecoration(
                      color: Lively.fill(b, 2),
                      borderRadius: BorderRadius.circular(Lively.rXs),
                      border: Border.all(color: Lively.separator(b)),
                    ),
                    child: Text(
                      keys,
                      style: TextStyle(
                        fontSize: Lively.tMicro,
                        color: Lively.textPrimary(b),
                      ),
                    ),
                  ),
                  const SizedBox(width: Lively.s3),
                  Expanded(
                    child: Text(
                      desc,
                      style: TextStyle(
                        fontSize: Lively.tFootnote,
                        color: Lively.textSecondary(b),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ]),
      ],
    );
  }

  // ── Shared building blocks ───────────────────────────────────────────────

  /// An uppercase section heading (`.settings-h`).
  Widget _sectionHeading(Brightness b, String text) => Padding(
        padding: const EdgeInsets.only(bottom: Lively.s3),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: Lively.tMicro,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: Lively.textTertiary(b),
          ),
        ),
      );

  /// A titled block of rows with a hairline separator above it (except the
  /// first), matching `.settings-section + .settings-section`.
  Widget _sectionBlock(Brightness b, String heading, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(top: Lively.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 1, color: Lively.separator(b)),
          const SizedBox(height: Lively.s5),
          _sectionHeading(b, heading),
          ...children,
        ],
      ),
    );
  }

  /// A label/note on the left, control on the right (`.set-row`).
  Widget _setRow(
    Brightness b, {
    required String title,
    required String note,
    required Widget control,
    bool last = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: last
          ? null
          : BoxDecoration(border: Border.all(color: Lively.separator(b), width: 0)),
      child: Container(
        decoration: last
            ? null
            : BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Lively.separator(b)),
                ),
              ),
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: Lively.tSubhead,
                      fontWeight: FontWeight.w500,
                      color: Lively.textPrimary(b),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    note,
                    style: TextStyle(
                      fontSize: Lively.tMicro,
                      color: Lively.textSecondary(b),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Lively.s4),
            control,
          ],
        ),
      ),
    );
  }

  /// A slider row for a sampling parameter (`.param-control`).
  Widget _paramRow(
    Brightness b, {
    required String label,
    required String note,
    required double value,
    required String display,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChange,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Lively.separator(b))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: Lively.tSubhead,
                    fontWeight: FontWeight.w500,
                    color: Lively.textPrimary(b),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  note,
                  style: TextStyle(
                    fontSize: Lively.tMicro,
                    color: Lively.textSecondary(b),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Lively.s4),
          SizedBox(
            width: 150,
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChange,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 40,
            child: Text(
              display,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: Lively.tMicro,
                color: Lively.textSecondary(b),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Small pieces ─────────────────────────────────────────────────────────

  String _initials(String name) {
    final words = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return words.isEmpty ? '?' : words;
  }

  String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }
}

// ─── Segmented control (`.seg`) ───────────────────────────────────────────

class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.values,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final b = _b(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Lively.fill(b, 1),
        borderRadius: BorderRadius.circular(Lively.rMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            _segOpt(b, i),
          ],
        ],
      ),
    );
  }

  Widget _segOpt(Brightness b, int i) {
    final v = values[i];
    final isSel = v == selected;
    return _Hover(
      onTap: () => onChanged(v),
      builder: (context, hovered) => AnimatedContainer(
        duration: Lively.dBase,
        curve: Lively.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? Lively.surface(b) : null,
          borderRadius: BorderRadius.circular(Lively.rSm),
          boxShadow: isSel
              ? [
                  BoxShadow(
                    color: const Color(0x1F000000),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          labels[i],
          style: TextStyle(
            fontSize: Lively.tFootnote,
            fontWeight: FontWeight.w500,
            color: isSel || hovered
                ? Lively.textPrimary(b)
                : Lively.textSecondary(b),
          ),
        ),
      ),
    );
  }
}

// ─── Badge (`.ms-badge`) ──────────────────────────────────────────────────

enum _BadgeTone { ok, warn, neutral }

class _badge extends StatelessWidget {
  const _badge(this.b, this.text, this.tone);
  final Brightness b;
  final String text;
  final _BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final (color) = switch (tone) {
      _BadgeTone.ok => Lively.appleGreen,
      _BadgeTone.warn => Lively.orange500,
      _BadgeTone.neutral => Lively.textSecondary(b),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Lively.rCapsule),
        border: Border.all(color: color.withOpacity(0.34)),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: Lively.tMicro,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }
}

// ─── Hover wrapper (replaces CSS `:hover` transitions) ────────────────────

class _Hover extends StatefulWidget {
  const _Hover({required this.builder, this.onTap});
  final Widget Function(BuildContext, bool hovered) builder;
  final VoidCallback? onTap;

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: widget.builder(context, _hovered),
      ),
    );
  }
}

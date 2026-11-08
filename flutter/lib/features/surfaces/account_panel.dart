/// Account panel (M13) — the profile row's own surface.
///
/// The avatar is derived from the display name and updates live. The actions
/// that belong to the account live here, not in the chat.
/// Port of `src/surfaces/AccountPanel.tsx`.
library;

import 'package:fluent_ui/fluent_ui.dart' as f;
import 'package:flutter/material.dart';

import '../../core/theme/lively_tokens.dart';

class AccountPanel extends StatelessWidget {
  final String accountName;
  final String planLabel;
  final int conversationCount;
  final VoidCallback onManagePlan;
  final VoidCallback onEditProfile;
  final VoidCallback onSignOut;

  const AccountPanel({
    super.key,
    required this.accountName,
    required this.planLabel,
    required this.conversationCount,
    required this.onManagePlan,
    required this.onEditProfile,
    required this.onSignOut,
  });

  String get _initials {
    final parts = accountName
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join('');
    return parts.isEmpty ? '?' : parts;
  }

  @override
  Widget build(BuildContext context) {
    final b = _bOf(context);

    return Container(
      padding: const EdgeInsets.all(Lively.s3),
      decoration: BoxDecoration(
        color: Lively.surfaceRaised(b),
        borderRadius: BorderRadius.circular(Lively.rLg),
        border: Border.all(color: Lively.separator(b), width: Lively.bHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _Avatar(initials: _initials, brightness: b),
              const SizedBox(width: Lively.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(accountName,
                        style: TextStyle(
                            color: Lively.textPrimary(b),
                            fontSize: Lively.tFootnote,
                            fontWeight: FontWeight.w600)),
                    Text(
                      '$planLabel · $conversationCount conversation${conversationCount == 1 ? '' : 's'} this week',
                      style: TextStyle(
                          color: Lively.textTertiary(b), fontSize: Lively.tMicro),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Lively.appleGreen.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Active',
                  style: TextStyle(
                      color: Lively.appleGreen,
                      fontSize: Lively.tMicro,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: Lively.s3),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onManagePlan,
                  icon: Icon(f.FluentIcons.permissions, size: 13),
                  label: const Text('Manage plan'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Lively.textPrimary(b),
                    side: BorderSide(color: Lively.separator(b), width: Lively.bThin),
                    minimumSize: const Size(0, Lively.btnHeight),
                    padding: const EdgeInsets.symmetric(horizontal: Lively.s2),
                  ),
                ),
              ),
              const SizedBox(width: Lively.s2),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEditProfile,
                  icon: Icon(f.FluentIcons.edit, size: 13),
                  label: const Text('Profile'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Lively.textPrimary(b),
                    side: BorderSide(color: Lively.separator(b), width: Lively.bThin),
                    minimumSize: const Size(0, Lively.btnHeight),
                    padding: const EdgeInsets.symmetric(horizontal: Lively.s2),
                  ),
                ),
              ),
              const SizedBox(width: Lively.s2),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSignOut,
                  icon: Icon(f.FluentIcons.chrome_close, size: 13),
                  label: const Text('Sign out'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Lively.appleRed,
                    side: BorderSide(color: Lively.appleRed.withValues(alpha: 0.4), width: Lively.bThin),
                    minimumSize: const Size(0, Lively.btnHeight),
                    padding: const EdgeInsets.symmetric(horizontal: Lively.s2),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Brightness _bOf(BuildContext context) => f.FluentTheme.of(context).brightness;
}

class _Avatar extends StatelessWidget {
  final String initials;
  final Brightness brightness;

  const _Avatar({required this.initials, required this.brightness});

  @override
  Widget build(BuildContext context) {
    final b = brightness;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Lively.accentMuted(b),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Lively.accentText(b),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
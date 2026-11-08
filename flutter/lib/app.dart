import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/router/app_router.dart';
import 'core/state/theme_controller.dart';
import 'core/theme/fluent_theme.dart';

class LivelyApp extends ConsumerWidget {
  const LivelyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeControllerProvider);
    return FluentApp.router(
      title: 'Lively OpenAll',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: buildFluentTheme(Brightness.light),
      darkTheme: buildFluentTheme(Brightness.dark),
      routerConfig: appRouter,
      locale: const Locale('en', 'US'),
      // Material widgets (genUI components, markdown, dialogs) read the
      // material `Theme.of`; mirror the active Fluent brightness so they
      // resolve Lively tokens for the same light/dark state.
      builder: (context, child) => m.Builder(builder: (inner) {
        final brightness = FluentTheme.of(inner).brightness;
        return m.Theme(
          data: m.ThemeData(
            brightness: brightness,
            useMaterial3: true,
            colorScheme: brightness == Brightness.dark
                ? m.ColorScheme.dark()
                : m.ColorScheme.light(),
            splashFactory: m.NoSplash.splashFactory,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      }),
    );
  }
}

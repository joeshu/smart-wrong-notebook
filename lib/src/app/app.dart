import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/app/theme/app_theme.dart';

class SmartWrongNotebookApp extends ConsumerWidget {
  const SmartWrongNotebookApp({required this.routerConfig, super.key});

  final GoRouter routerConfig;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final visualStyle = ref.watch(appVisualStyleProvider);

    return MaterialApp.router(
      title: 'AI错题本',
      theme: buildLightTheme(style: visualStyle),
      darkTheme: buildDarkTheme(style: visualStyle),
      themeMode: themeMode,
      routerConfig: routerConfig,
      debugShowCheckedModeBanner: false,
    );
  }
}

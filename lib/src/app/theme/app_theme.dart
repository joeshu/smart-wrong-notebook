import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/app/theme/app_visual_style.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_typography.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

/// 构建浅色主题。
///
/// 基于 FlexScheme.indigo 并叠加统一组件默认样式与字体层级，
/// 确保 Material 3 组件（按钮、卡片、输入框、Chip、导航栏）与自定义组件视觉一致。
ThemeData buildLightTheme({AppVisualStyle style = AppVisualStyle.academic}) {
  final visual = AppVisualTokens.forStyle(style, dark: false);
  final scheme = ColorScheme.fromSeed(
    seedColor: style.seedColor,
    brightness: Brightness.light,
  ).copyWith(surface: style.scaffold(false));
  final base = FlexThemeData.light(
    scheme: FlexScheme.indigo,
    useMaterial3: true,
    surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
    scaffoldBackground: style.scaffold(false),
    appBarBackground: style.scaffold(false),
    appBarElevation: AppElevation.flat,
    subThemesData: const FlexSubThemesData(
      blendOnLevel: 10,
      blendOnColors: false,
      useM2StyleDividerInM3: true,
      inputDecoratorBorderType: FlexInputBorderType.outline,
      inputDecoratorRadius: AppRadius.medium,
      chipRadius: AppRadius.xlarge,
      navigationBarIndicatorRadius: AppRadius.medium,
      navigationBarSelectedLabelSchemeColor: SchemeColor.primary,
      navigationBarIndicatorSchemeColor: SchemeColor.primary,
      cardRadius: AppRadius.large,
      elevatedButtonRadius: AppRadius.pill,
      filledButtonRadius: AppRadius.pill,
      outlinedButtonRadius: AppRadius.pill,
      textButtonRadius: AppRadius.pill,
      popupMenuRadius: AppRadius.medium,
      dialogRadius: AppRadius.large,
      bottomSheetRadius: AppRadius.xlarge,
    ),
  );

  final textTheme = _buildTextTheme(base.textTheme, style);

  return base.copyWith(
    colorScheme: scheme,
    extensions: <ThemeExtension<dynamic>>[visual],
    scaffoldBackgroundColor: style.scaffold(false),
    cardTheme: base.cardTheme.copyWith(
      elevation: AppElevation.flat,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(visual.cardRadius),
      ),
    ),
    elevatedButtonTheme: _elevatedButtonTheme(scheme, visual.controlRadius),
    filledButtonTheme: _filledButtonTheme(scheme, visual.controlRadius),
    outlinedButtonTheme: _outlinedButtonTheme(scheme, visual.controlRadius),
    textButtonTheme: _textButtonTheme(scheme, visual.controlRadius),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xlarge)),
    ),
    iconTheme: IconThemeData(
      color: scheme.onSurfaceVariant,
      size: AppControlSize.icon,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      elevation: AppElevation.flat,
      indicatorColor: scheme.primaryContainer,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.medium)),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: scheme.primary, size: AppControlSize.icon);
        }
        return IconThemeData(color: scheme.onSurfaceVariant, size: AppControlSize.icon);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        );
      }),
    ),
    textTheme: textTheme,
    appBarTheme: _appBarTheme(
      base.appBarTheme,
      textTheme,
      scheme,
      style,
    ),
  );
}

/// 构建深色主题。
ThemeData buildDarkTheme({AppVisualStyle style = AppVisualStyle.academic}) {
  final visual = AppVisualTokens.forStyle(style, dark: true);
  final scheme = ColorScheme.fromSeed(
    seedColor: style.seedColor,
    brightness: Brightness.dark,
  ).copyWith(surface: style.scaffold(true));
  final base = FlexThemeData.dark(
    scheme: FlexScheme.indigo,
    useMaterial3: true,
    surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
    scaffoldBackground: style.scaffold(true),
    appBarBackground: style.scaffold(true),
    appBarElevation: AppElevation.flat,
    subThemesData: const FlexSubThemesData(
      blendOnLevel: 20,
      useM2StyleDividerInM3: true,
      inputDecoratorBorderType: FlexInputBorderType.outline,
      inputDecoratorRadius: AppRadius.medium,
      chipRadius: AppRadius.xlarge,
      navigationBarIndicatorRadius: AppRadius.medium,
      navigationBarSelectedLabelSchemeColor: SchemeColor.primary,
      navigationBarIndicatorSchemeColor: SchemeColor.primary,
      cardRadius: AppRadius.large,
      elevatedButtonRadius: AppRadius.pill,
      filledButtonRadius: AppRadius.pill,
      outlinedButtonRadius: AppRadius.pill,
      textButtonRadius: AppRadius.pill,
      popupMenuRadius: AppRadius.medium,
      dialogRadius: AppRadius.large,
      bottomSheetRadius: AppRadius.xlarge,
    ),
  );

  final textTheme = _buildTextTheme(base.textTheme, style);

  return base.copyWith(
    colorScheme: scheme,
    extensions: <ThemeExtension<dynamic>>[visual],
    scaffoldBackgroundColor: style.scaffold(true),
    cardTheme: base.cardTheme.copyWith(
      elevation: AppElevation.flat,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(visual.cardRadius),
      ),
    ),
    elevatedButtonTheme: _elevatedButtonTheme(scheme, visual.controlRadius),
    filledButtonTheme: _filledButtonTheme(scheme, visual.controlRadius),
    outlinedButtonTheme: _outlinedButtonTheme(scheme, visual.controlRadius),
    textButtonTheme: _textButtonTheme(scheme, visual.controlRadius),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xlarge)),
    ),
    iconTheme: IconThemeData(
      color: scheme.onSurfaceVariant,
      size: AppControlSize.icon,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      elevation: AppElevation.flat,
      indicatorColor: scheme.primaryContainer.withValues(alpha: 0.5),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.medium)),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: scheme.primary, size: AppControlSize.icon);
        }
        return IconThemeData(color: scheme.onSurfaceVariant, size: AppControlSize.icon);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        );
      }),
    ),
    textTheme: textTheme,
    appBarTheme: _appBarTheme(
      base.appBarTheme,
      textTheme,
      scheme,
      style,
    ),
  );
}

AppBarThemeData _appBarTheme(
  AppBarThemeData base,
  TextTheme textTheme,
  ColorScheme scheme,
  AppVisualStyle style,
) {
  final dividerAlpha = scheme.brightness == Brightness.dark ? .28 : .16;
  return base.copyWith(
    centerTitle: style != AppVisualStyle.paper,
    toolbarHeight: switch (style) {
      AppVisualStyle.academic => 56,
      AppVisualStyle.paper => 60,
      AppVisualStyle.aurora => 58,
      AppVisualStyle.forest => 58,
    },
    elevation: 0,
    scrolledUnderElevation: style == AppVisualStyle.aurora ? 2 : 0,
    surfaceTintColor: style == AppVisualStyle.aurora
        ? scheme.primary.withValues(alpha: .08)
        : Colors.transparent,
    backgroundColor: scheme.surface.withValues(
      alpha: style == AppVisualStyle.aurora ? .96 : 1,
    ),
    shape: style == AppVisualStyle.paper
        ? Border(
            bottom: BorderSide(
              color: scheme.primary.withValues(alpha: dividerAlpha),
            ),
          )
        : null,
    titleTextStyle: textTheme.titleLarge?.copyWith(
      fontWeight: switch (style) {
        AppVisualStyle.academic => FontWeight.w800,
        AppVisualStyle.paper => FontWeight.w600,
        AppVisualStyle.aurora => FontWeight.w800,
        AppVisualStyle.forest => FontWeight.w700,
      },
      letterSpacing: style == AppVisualStyle.paper ? .4 : -.2,
      color: scheme.onSurface,
    ),
    iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
  );
}

TextTheme _buildTextTheme(
  TextTheme base,
  AppVisualStyle style,
) {
  final themed = base.copyWith(
    displayLarge: base.displayLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
    displayMedium: base.displayMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
    displaySmall: base.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
    headlineLarge: base.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
    headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
    headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
    titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 20),
    titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 16),
    titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
    bodyLarge: base.bodyLarge?.copyWith(fontWeight: FontWeight.w400, fontSize: 16),
    bodyMedium: base.bodyMedium?.copyWith(fontWeight: FontWeight.w400, fontSize: 14),
    bodySmall: base.bodySmall?.copyWith(fontWeight: FontWeight.w400, fontSize: 12),
    labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
    labelMedium: base.labelMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 12),
    labelSmall: base.labelSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 11),
  );
  // 全局主题禁止依赖运行时字体下载，确保离线启动与测试稳定。
  // 纸墨书房优先使用系统宋体；设备缺少该字体时由 Flutter 自动回退。
  return style == AppVisualStyle.paper
      ? themed.apply(fontFamily: 'Songti SC')
      : themed;
}

ElevatedButtonThemeData _elevatedButtonTheme(
  ColorScheme scheme,
  double radius,
) {
  return ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      minimumSize: const Size(0, AppControlSize.standard),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.xl,
        vertical: AppSpace.md,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      elevation: AppElevation.flat,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
}

FilledButtonThemeData _filledButtonTheme(
  ColorScheme scheme,
  double radius,
) {
  return FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, AppControlSize.standard),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.xl,
        vertical: AppSpace.md,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
}

OutlinedButtonThemeData _outlinedButtonTheme(
  ColorScheme scheme,
  double radius,
) {
  return OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, AppControlSize.standard),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.xl,
        vertical: AppSpace.md,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      side: BorderSide(color: scheme.outlineVariant),
      foregroundColor: scheme.primary,
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
}

TextButtonThemeData _textButtonTheme(
  ColorScheme scheme,
  double radius,
) {
  return TextButtonThemeData(
    style: TextButton.styleFrom(
      minimumSize: const Size(0, AppControlSize.compact),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      foregroundColor: scheme.primary,
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
}

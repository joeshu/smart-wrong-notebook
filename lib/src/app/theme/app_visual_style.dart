import 'package:flutter/material.dart';

enum AppVisualStyle { academic, paper, aurora, forest }

extension AppVisualStyleX on AppVisualStyle {
  String get label => switch (this) {
        AppVisualStyle.academic => '智识蓝',
        AppVisualStyle.paper => '纸墨书房',
        AppVisualStyle.aurora => '极光专注',
        AppVisualStyle.forest => '森系护眼',
      };

  String get description => switch (this) {
        AppVisualStyle.academic => '理性清晰，突出信息层级',
        AppVisualStyle.paper => '暖纸低饱和，适合长时间阅读',
        AppVisualStyle.aurora => '紫蓝高对比，强化 AI 与专注感',
        AppVisualStyle.forest => '自然柔和，降低复习视觉压力',
      };

  Color get seedColor => switch (this) {
        AppVisualStyle.academic => const Color(0xFF4056C7),
        AppVisualStyle.paper => const Color(0xFF8A5A35),
        AppVisualStyle.aurora => const Color(0xFF7357D9),
        AppVisualStyle.forest => const Color(0xFF25735A),
      };

  Color scaffold(bool dark) => switch ((this, dark)) {
        (AppVisualStyle.academic, false) => const Color(0xFFF6F7FC),
        (AppVisualStyle.academic, true) => const Color(0xFF11131A),
        (AppVisualStyle.paper, false) => const Color(0xFFF7F1E6),
        (AppVisualStyle.paper, true) => const Color(0xFF1C1814),
        (AppVisualStyle.aurora, false) => const Color(0xFFF6F3FF),
        (AppVisualStyle.aurora, true) => const Color(0xFF13101D),
        (AppVisualStyle.forest, false) => const Color(0xFFF1F7F3),
        (AppVisualStyle.forest, true) => const Color(0xFF101915),
      };

  double get cardRadius => switch (this) {
        AppVisualStyle.academic => 18,
        AppVisualStyle.paper => 10,
        AppVisualStyle.aurora => 24,
        AppVisualStyle.forest => 16,
      };

  double get controlRadius => switch (this) {
        AppVisualStyle.academic => 14,
        AppVisualStyle.paper => 8,
        AppVisualStyle.aurora => 18,
        AppVisualStyle.forest => 12,
      };
}

@immutable
class AppVisualTokens extends ThemeExtension<AppVisualTokens> {
  const AppVisualTokens({
    required this.style,
    required this.heroGradient,
    required this.cardRadius,
    required this.controlRadius,
    required this.cardBorderAlpha,
    required this.shadowAlpha,
  });

  final AppVisualStyle style;
  final Gradient heroGradient;
  final double cardRadius;
  final double controlRadius;
  final double cardBorderAlpha;
  final double shadowAlpha;

  factory AppVisualTokens.forStyle(AppVisualStyle style, {required bool dark}) {
    final gradient = switch ((style, dark)) {
      (AppVisualStyle.academic, false) => const LinearGradient(
          colors: <Color>[Color(0xFF4056C7), Color(0xFF6274DE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      (AppVisualStyle.academic, true) => const LinearGradient(
          colors: <Color>[Color(0xFF29377F), Color(0xFF4B5FC2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      (AppVisualStyle.paper, false) => const LinearGradient(
          colors: <Color>[Color(0xFF6F4930), Color(0xFFA8784F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      (AppVisualStyle.paper, true) => const LinearGradient(
          colors: <Color>[Color(0xFF3D2B20), Color(0xFF765239)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      (AppVisualStyle.aurora, false) => const LinearGradient(
          colors: <Color>[Color(0xFF6547D4), Color(0xFF3D7BE6), Color(0xFF20A4B8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      (AppVisualStyle.aurora, true) => const LinearGradient(
          colors: <Color>[Color(0xFF402B91), Color(0xFF2858A7), Color(0xFF176B77)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      (AppVisualStyle.forest, false) => const LinearGradient(
          colors: <Color>[Color(0xFF236A52), Color(0xFF3E8B6D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      (AppVisualStyle.forest, true) => const LinearGradient(
          colors: <Color>[Color(0xFF174536), Color(0xFF286C54)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
    };
    return AppVisualTokens(
      style: style,
      heroGradient: gradient,
      cardRadius: style.cardRadius,
      controlRadius: style.controlRadius,
      cardBorderAlpha: style == AppVisualStyle.aurora ? .42 : .66,
      shadowAlpha: dark
          ? 0
          : switch (style) {
              AppVisualStyle.paper => .05,
              AppVisualStyle.aurora => .12,
              _ => .08,
            },
    );
  }

  static AppVisualTokens of(BuildContext context) =>
      Theme.of(context).extension<AppVisualTokens>() ??
      AppVisualTokens.forStyle(
        AppVisualStyle.academic,
        dark: Theme.of(context).brightness == Brightness.dark,
      );

  @override
  AppVisualTokens copyWith({
    AppVisualStyle? style,
    Gradient? heroGradient,
    double? cardRadius,
    double? controlRadius,
    double? cardBorderAlpha,
    double? shadowAlpha,
  }) =>
      AppVisualTokens(
        style: style ?? this.style,
        heroGradient: heroGradient ?? this.heroGradient,
        cardRadius: cardRadius ?? this.cardRadius,
        controlRadius: controlRadius ?? this.controlRadius,
        cardBorderAlpha: cardBorderAlpha ?? this.cardBorderAlpha,
        shadowAlpha: shadowAlpha ?? this.shadowAlpha,
      );

  @override
  AppVisualTokens lerp(covariant AppVisualTokens? other, double t) {
    if (other == null) return this;
    return AppVisualTokens(
      style: t < .5 ? style : other.style,
      heroGradient: Gradient.lerp(heroGradient, other.heroGradient, t)!,
      cardRadius: _lerp(cardRadius, other.cardRadius, t),
      controlRadius: _lerp(controlRadius, other.controlRadius, t),
      cardBorderAlpha: _lerp(cardBorderAlpha, other.cardBorderAlpha, t),
      shadowAlpha: _lerp(shadowAlpha, other.shadowAlpha, t),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

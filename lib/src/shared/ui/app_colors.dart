import 'package:flutter/material.dart';

/// 语义化颜色常量，避免在多个文件中硬编码十六进制色值。
/// 使用时应结合当前主题判断是否需要降饱和或替换为背景色。
abstract final class AppColors {
  // ---------- Brand / Primary ----------
  static const Color primary = Color(0xFF6366F1);
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color primaryLighter = Color(0xFFA5B4FC);
  static const Color primaryDark = Color(0xFF4338CA);
  static const Color primaryDarker = Color(0xFF3730A3);
  static const Color primaryContainerLight = Color(0xFFEEF2FF);
  static const Color primaryContainerDark = Color(0xFF312E81);

  // ---------- Secondary / Violet ----------
  static const Color secondary = Color(0xFF8B5CF6);
  static const Color secondaryLight = Color(0xFFA78BFA);
  static const Color secondaryContainerLight = Color(0xFFF5F3FF);
  static const Color secondaryContainerDark = Color(0xFF4C1D95);

  // ---------- Semantic: Success ----------
  static const Color success = Color(0xFF10B981);
  static const Color successLight = Color(0xFF34D399);
  static const Color successContainerLight = Color(0xFFF0FDF4);
  static const Color successDark = Color(0xFF059669);

  // ---------- Semantic: Warning ----------
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFBBF24);
  static const Color warningContainerLight = Color(0xFFFFFBEB);
  static const Color warningDark = Color(0xFFD97706);

  // ---------- Semantic: Danger ----------
  static const Color danger = Color(0xFFF43F5E);
  static const Color dangerLight = Color(0xFFFB7185);
  static const Color dangerContainerLight = Color(0xFFFFF1F2);
  static const Color dangerDark = Color(0xFFE11D48);

  // ---------- Semantic: Info ----------
  static const Color info = Color(0xFF3B82F6);
  static const Color infoLight = Color(0xFF60A5FA);
  static const Color infoContainerLight = Color(0xFFEFF6FF);
  static const Color infoDark = Color(0xFF2563EB);

  // ---------- Accent palette ----------
  static const Color accentTeal = Color(0xFF0D9488);
  static const Color accentTealLight = Color(0xFF14B8A6);
  static const Color accentTealContainerLight = Color(0xFFF0FDFA);
  static const Color accentAmber = Color(0xFFD97706);
  static const Color accentAmberContainerLight = Color(0xFFFFFBEB);
  static const Color accentPurple = Color(0xFF7C3AED);
  static const Color accentPurpleContainerLight = Color(0xFFF5F3FF);

  // ---------- Neutral / Slate ----------
  static const Color slate = Color(0xFF64748B);
  static const Color slateLight = Color(0xFF94A3B8);
  static const Color slateDark = Color(0xFF475569);
  static const Color slateContainerLight = Color(0xFFF8FAFC);
  static const Color slateContainerDark = Color(0xFF1E293B);

  // ---------- Surface ----------
  static const Color surfaceLight = Color(0xFFF8FAFC);
  static const Color surfaceDark = Color(0xFF0F172A);

  // ---------- Mastery levels ----------
  static const Color mastered = Color(0xFF10B981);
  static const Color reviewing = Color(0xFFF59E0B);
  static const Color newQuestion = Color(0xFF94A3B8);

  /// 返回对应语义色在深色模式下的容器背景（默认使用带透明度的同色）。
  static Color semanticContainer(
    Color semantic, {
    bool isDark = false,
    double lightAlpha = 0.08,
    double darkAlpha = 0.14,
  }) {
    return isDark
        ? semantic.withValues(alpha: darkAlpha)
        : semantic.withValues(alpha: lightAlpha);
  }

  /// 返回对应语义色在边框场景下的颜色。
  static Color semanticBorder(
    Color semantic, {
    bool isDark = false,
    double lightAlpha = 0.2,
    double darkAlpha = 0.3,
  }) {
    return isDark
        ? semantic.withValues(alpha: darkAlpha)
        : semantic.withValues(alpha: lightAlpha);
  }

  /// 返回语义文字色：浅色模式下使用语义色本身；深色模式下可指定，否则使用语义色。
  static Color semanticText(
    Color semantic, {
    bool isDark = false,
    Color? darkColor,
  }) {
    return isDark ? (darkColor ?? semantic) : semantic;
  }
}

/// 品牌与装饰渐变。
abstract final class AppGradients {
  static const LinearGradient primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[AppColors.primary, AppColors.secondary],
  );

  static const LinearGradient primaryHorizontal = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: <Color>[AppColors.primary, AppColors.secondary],
  );

  static LinearGradient hero(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF1E1B4B), Color(0xFF312E81)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF6366F1), Color(0xFF8B5CF6)],
          );
  }

  static LinearGradient surfaceSoft(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFF0F172A), Color(0xFF1E293B)],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
          );
  }
}

/// 统一阴影规范。
abstract final class AppShadows {
  static List<BoxShadow> get sm => <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get md => <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get lg => <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get float => <BoxShadow>[
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.28),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> none = const <BoxShadow>[];
}

import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/app/theme/app_visual_style.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

/// 按钮风格变体。
enum AppButtonVariant { primary, secondary, outline, ghost }

/// 按钮尺寸。
enum AppButtonSize { small, medium, large }

/// 统一按钮组件。
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
    this.isExpanded = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Color backgroundColor;
    Color foregroundColor;
    Color? borderColor;
    switch (variant) {
      case AppButtonVariant.primary:
        backgroundColor = colorScheme.primary;
        foregroundColor = colorScheme.onPrimary;
        break;
      case AppButtonVariant.secondary:
        backgroundColor = colorScheme.secondaryContainer;
        foregroundColor = colorScheme.onSecondaryContainer;
        break;
      case AppButtonVariant.outline:
        backgroundColor = Colors.transparent;
        foregroundColor = colorScheme.primary;
        borderColor = colorScheme.outline;
        break;
      case AppButtonVariant.ghost:
        backgroundColor = Colors.transparent;
        foregroundColor = colorScheme.onSurfaceVariant;
        break;
    }

    final double height;
    final EdgeInsetsGeometry padding;
    final double iconSize;
    final double fontSize;
    switch (size) {
      case AppButtonSize.small:
        height = 36;
        padding = const EdgeInsets.symmetric(horizontal: AppSpace.md);
        iconSize = 16;
        fontSize = 13;
      case AppButtonSize.medium:
        height = 44;
        padding = const EdgeInsets.symmetric(horizontal: AppSpace.lg);
        iconSize = 18;
        fontSize = 14;
      case AppButtonSize.large:
        height = 52;
        padding = const EdgeInsets.symmetric(horizontal: AppSpace.xl);
        iconSize = 20;
        fontSize = 15;
    }

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: iconSize, color: foregroundColor),
          const SizedBox(width: AppSpace.sm),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: foregroundColor,
          ),
        ),
      ],
    );

    final button = Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(height / 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(height / 2),
        child: Container(
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(height / 2),
            border: borderColor != null ? Border.all(color: borderColor) : null,
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );

    return isExpanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// 渐变主按钮，用于最重要的 CTA（如首页拍照录题）。
class AppGradientButton extends StatelessWidget {
  const AppGradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.isExpanded = true,
    this.gradient,
    this.shadows,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool isExpanded;
  final Gradient? gradient;
  final List<BoxShadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final button = Container(
      height: 46,
      decoration: BoxDecoration(
        gradient: gradient ?? AppVisualTokens.of(context).heroGradient,
        borderRadius: BorderRadius.circular(23),
        boxShadow: shadows ?? AppShadows.float,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(23),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(23),
          splashColor: Colors.white.withValues(alpha: 0.16),
          highlightColor: Colors.white.withValues(alpha: 0.08),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 22, color: Colors.white),
                  const SizedBox(width: AppSpace.sm),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return isExpanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// 首页 Hero 品牌区卡片。
class AppHeroCard extends StatelessWidget {
  const AppHeroCard({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.secondaryAction,
    this.header,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final Widget? secondaryAction;
  final Widget? header;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.md),
      decoration: BoxDecoration(
        gradient: AppVisualTokens.of(context).heroGradient,
        borderRadius: BorderRadius.circular(
          AppVisualTokens.of(context).cardRadius,
        ),
        boxShadow: isDark ? AppShadows.none : AppShadows.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (header != null) ...<Widget>[
            header!,
            const SizedBox(height: AppSpace.sm),
          ],
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.88),
                height: 1.4,
              ),
            ),
          ],
          if (action != null) ...<Widget>[
            const SizedBox(height: AppSpace.md),
            action!,
          ],
          if (secondaryAction != null) ...<Widget>[
            const SizedBox(height: AppSpace.sm),
            secondaryAction!,
          ],
          if (footer != null) ...<Widget>[
            const SizedBox(height: AppSpace.md),
            footer!,
          ],
        ],
      ),
    );
  }
}

/// 统计数字卡片。
class AppStatCard extends StatelessWidget {
  const AppStatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.accentColor = AppColors.primary,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm + 2),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceContainerHighest : colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: isDark ? AppShadows.none : AppShadows.sm,
      ),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.semanticContainer(accentColor, isDark: isDark),
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: Icon(icon, size: 15, color: accentColor),
            ),
            const SizedBox(width: AppSpace.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                    height: 1.1,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }
}

/// 筛选 Chip，用于错题本科目/状态筛选。
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    this.icon,
    this.isSelected = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final foregroundColor = isSelected
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;
    final backgroundColor = isSelected
        ? colorScheme.primary
        : (isDark ? colorScheme.surfaceContainerHighest : colorScheme.surface);
    final borderColor = isSelected
        ? colorScheme.primary
        : colorScheme.outlineVariant.withValues(alpha: 0.8);

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 14, color: foregroundColor),
                const SizedBox(width: AppSpace.xs),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: foregroundColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 主题选择卡片。
class AppThemeCard extends StatelessWidget {
  const AppThemeCard({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isSelected
          ? Colors.transparent
          : (isDark ? colorScheme.surfaceContainerHighest : colorScheme.surface),
      borderRadius: BorderRadius.circular(AppRadius.large),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.large),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
          decoration: BoxDecoration(
            gradient: isSelected ? AppGradients.primary : null,
            borderRadius: BorderRadius.circular(AppRadius.large),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withValues(alpha: 0.8),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 24,
                color: isSelected ? Colors.white : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? Colors.white : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 行动卡片，用于首页“今日行动”类入口。
class AppActionCard extends StatelessWidget {
  const AppActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.accentColor = AppColors.primary,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm + 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    accentColor,
                    accentColor.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(AppRadius.small),
                boxShadow: isDark ? AppShadows.none : <BoxShadow>[
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.22),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, size: 18, color: Colors.white),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: AppSpace.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

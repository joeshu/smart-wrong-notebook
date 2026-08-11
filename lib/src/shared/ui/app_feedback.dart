import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';

/// 统一的轻提示（Toast）与触感反馈。
///
/// 大厂级产品对“操作反馈”有一致的语言：成功用绿色短提示 + 轻触感，
/// 失败用红色并给出可操作的文案。散落的 `ScaffoldMessenger.showSnackBar`
/// 难以保证一致，故在此收敛。
///
/// 用法：
/// ```dart
/// AppToast.success(context, '版面识别设置已保存');
/// AppToast.error(context, '导出失败，请重试');
/// AppHaptics.light();
/// ```
abstract final class AppToast {
  static void show(
    BuildContext context,
    String message, {
    bool success = false,
    bool error = false,
    Duration duration = const Duration(seconds: 2),
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final Color tint;
    if (success) {
      tint = isDark ? AppColors.successLight : AppColors.successDark;
    } else if (error) {
      tint = isDark ? AppColors.dangerLight : AppColors.dangerDark;
    } else {
      tint = scheme.primary;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          backgroundColor: isDark ? AppColors.slateContainerDark : Colors.white,
          elevation: 6,
          duration: duration,
          content: Row(
            children: <Widget>[
              Icon(
                success
                    ? CupertinoIcons.check_mark_circled_solid
                    : error
                        ? CupertinoIcons.exclamationmark_circle
                        : CupertinoIcons.info,
                color: tint,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : AppColors.slateDark,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  static void success(BuildContext context, String message) =>
      show(context, message, success: true);

  static void error(BuildContext context, String message) =>
      show(context, message, error: true);
}

/// 触感反馈封装，避免在各处重复书写 `HapticFeedback` 调用。
abstract final class AppHaptics {
  static void light() => HapticFeedback.lightImpact();
  static void medium() => HapticFeedback.mediumImpact();
  static void heavy() => HapticFeedback.heavyImpact();
  static void selection() => HapticFeedback.selectionClick();
  static void success() {
    HapticFeedback.lightImpact();
  }
}

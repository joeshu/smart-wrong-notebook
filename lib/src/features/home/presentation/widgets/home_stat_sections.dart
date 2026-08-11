import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:smart_wrong_notebook/src/app/theme/app_visual_style.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_components.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_motion.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_typography.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_layout.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

/// 首页数据概览指标条：连续学习天数 / 今日待复习 / 累计错题。
/// 作为主视觉锚点，把用户最关心的三个数字集中呈现。
class HomeStatStrip extends StatelessWidget {
  const HomeStatStrip({
    required this.streakDays,
    required this.dueCount,
    required this.totalCount,
  });

  final int streakDays;
  final int dueCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final style = AppVisualTokens.of(context).style;
    final items = switch (style) {
      AppVisualStyle.academic => <({IconData icon, String label, String helper, AppTagTone tone})>[
          (icon: CupertinoIcons.flame, label: '连续学习', helper: '维持节奏', tone: AppTagTone.warning),
          (icon: CupertinoIcons.calendar, label: '今日待复习', helper: '按清单推进', tone: AppTagTone.primary),
          (icon: CupertinoIcons.doc_text, label: '累计错题', helper: '长期样本', tone: AppTagTone.secondary),
        ],
      AppVisualStyle.paper => <({IconData icon, String label, String helper, AppTagTone tone})>[
          (icon: CupertinoIcons.book, label: '学习页数', helper: '今天已续写', tone: AppTagTone.warning),
          (icon: CupertinoIcons.tray, label: '待整理', helper: '先读后批注', tone: AppTagTone.primary),
          (icon: CupertinoIcons.archivebox, label: '已归档', helper: '错题库存', tone: AppTagTone.secondary),
        ],
      AppVisualStyle.aurora => <({IconData icon, String label, String helper, AppTagTone tone})>[
          (icon: CupertinoIcons.bolt, label: '连续激活', helper: '学习能量', tone: AppTagTone.warning),
          (icon: CupertinoIcons.scope, label: '待聚焦', helper: '优先处理', tone: AppTagTone.primary),
          (icon: CupertinoIcons.square_stack_3d_up, label: '训练样本', helper: '分析总量', tone: AppTagTone.secondary),
        ],
      AppVisualStyle.forest => <({IconData icon, String label, String helper, AppTagTone tone})>[
          (icon: CupertinoIcons.tree, label: '稳定坚持', helper: '今天也前进', tone: AppTagTone.warning),
          (icon: CupertinoIcons.time, label: '待温习', helper: '先看最重要', tone: AppTagTone.primary),
          (icon: CupertinoIcons.layers_alt, label: '积累题量', helper: '慢慢长成', tone: AppTagTone.secondary),
        ],
    };
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.md, horizontal: AppSpace.sm),
      child: Row(
        children: <Widget>[
          StatMetric(
            icon: items[0].icon,
            value: '$streakDays',
            unit: '天',
            label: items[0].label,
            helper: items[0].helper,
            tone: items[0].tone,
            delay: AppMotion.staggerStep,
          ),
          _vDivider(context),
          StatMetric(
            icon: items[1].icon,
            value: '$dueCount',
            unit: '题',
            label: items[1].label,
            helper: items[1].helper,
            tone: items[1].tone,
            delay: AppMotion.staggerStep * 2,
          ),
          _vDivider(context),
          StatMetric(
            icon: items[2].icon,
            value: '$totalCount',
            unit: '题',
            label: items[2].label,
            helper: items[2].helper,
            tone: items[2].tone,
            delay: AppMotion.staggerStep * 3,
          ),
        ],
      ),
    );
  }

  Widget _vDivider(BuildContext context) => Container(
        width: 1,
        height: 36,
        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
      );
}

class StatMetric extends StatelessWidget {
  const StatMetric({
    required this.icon,
    required this.value,
    required this.unit,
    required this.label,
    required this.helper,
    required this.tone,
    this.delay = Duration.zero,
  });

  final IconData icon;
  final String value;
  final String unit;
  final String label;
  final String helper;
  final AppTagTone tone;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final resolvedTone = switch (tone) {
      AppTagTone.primary => (
          foreground: scheme.primary,
          background: scheme.primaryContainer,
        ),
      AppTagTone.secondary => (
          foreground: scheme.secondary,
          background: scheme.secondaryContainer,
        ),
      AppTagTone.tertiary => (
          foreground: scheme.tertiary,
          background: scheme.tertiaryContainer,
        ),
      AppTagTone.warning => (
          foreground: const Color(0xFFB45309),
          background: const Color(0xFFFFEDD5),
        ),
      AppTagTone.success => (
          foreground: const Color(0xFF15803D),
          background: const Color(0xFFDCFCE7),
        ),
      AppTagTone.danger => (
          foreground: scheme.error,
          background: scheme.errorContainer,
        ),
      AppTagTone.neutral => (
          foreground: scheme.onSurfaceVariant,
          background: scheme.surfaceContainerHighest,
        ),
    };
    final color = resolvedTone.foreground;
    final content = Column(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: resolvedTone.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                value,
                style: AppTextStyle.apply(AppTextStyle.headline).copyWith(
                  color: isDark ? Colors.white : AppColors.slateDark,
                ),
              ),
              const SizedBox(width: 2),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  unit,
                  style: AppTextStyle.apply(AppTextStyle.caption).copyWith(
                    color: isDark ? Colors.white : AppColors.slate,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(label, style: AppTextStyle.apply(AppTextStyle.caption).copyWith(
            color: isDark ? Colors.white : AppColors.slate,
          )),
          const SizedBox(height: 2),
          Text(helper, textAlign: TextAlign.center, style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          )),
        ],
      );
    final child = Expanded(child: content);
    if (AppMotion.isTest) return child;
    return child.animate().fadeIn(
      duration: AppMotion.fast,
      delay: delay,
      curve: AppMotion.standard,
    );
  }
}

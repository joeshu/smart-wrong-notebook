import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/app/theme/app_visual_style.dart';
import 'package:smart_wrong_notebook/src/app/providers/review_providers.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/core/constants/app_strings.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_components.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_layout.dart';

/// Phase 8-1：统一今日行动面板。
///
/// 三张行动卡按优先级从上到下排列：
///   1. 待复习（dueCount > 0 时显示）
///   2. 继续未完成识别（pendingRecognition > 0 时显示）
///   3. 添加新错题（始终显示）
/// 全部空时显示空状态引导。
class UnifiedActionPanel extends StatelessWidget {
  const UnifiedActionPanel({
    required this.plan,
    required this.pendingRecognition,
    required this.hasPendingBatch,
    required this.topMistakeCategory,
    required this.onOpenReview,
    required this.onOpenRecognize,
    required this.onCapture,
  });

  final TodayReviewPlan plan;
  final int pendingRecognition;
  final bool hasPendingBatch;
  final MistakeCategory? topMistakeCategory;
  final VoidCallback onOpenReview;
  final VoidCallback onOpenRecognize;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final hasDue = plan.dueCount > 0;
    final hasPending = pendingRecognition > 0;
    final recommendation = hasDue
        ? (
            icon: CupertinoIcons.play_circle_fill,
            title: '先复习 ${plan.dueCount} 道到期错题',
            reason: topMistakeCategory == null
                ? '这些题已经到达复习时间，先处理能降低再次遗忘的概率。'
                : '${topMistakeCategory!.label}是当前高频错因，今天优先回看相关到期题。',
            meta: '预计 ${plan.estimatedMinutes} 分钟 · 完成后更新掌握状态',
            action: '开始复习',
            onTap: onOpenReview,
          )
        : hasPending
            ? (
                icon: hasPendingBatch
                    ? CupertinoIcons.rectangle_stack
                    : CupertinoIcons.text_badge_checkmark,
                title: '先确认 $pendingRecognition 项识别内容',
                reason: '先把题干和低置信字段核对清楚，再让 AI 分析，避免错误结论进入错题本。',
                meta: '约 ${pendingRecognition * 2} 分钟 · 完成后自动进入分析',
                action: '继续确认',
                onTap: onOpenRecognize,
              )
            : (
                icon: CupertinoIcons.camera_fill,
                title: '记录今天遇到的第一道错题',
                reason: topMistakeCategory == null
                    ? '当前没有到期任务，随手记录一道新错题就能开始建立学习档案。'
                    : '近期${topMistakeCategory!.label}较多，遇到同类题时及时记录更容易发现规律。',
                meta: '约 2 分钟 · 拍照后自动识别与整理',
                action: '拍一道题',
                onTap: onCapture,
              );

    final secondary = <Widget>[
      if (hasDue && hasPending)
        ActionTile(
          icon: hasPendingBatch
              ? CupertinoIcons.rectangle_stack
              : CupertinoIcons.text_badge_checkmark,
          color: Theme.of(context).colorScheme.secondary,
          title: '稍后确认识别内容',
          subtitle: '$pendingRecognition 项待处理',
          trailing: '去处理',
          onTap: onOpenRecognize,
        ),
      if (hasDue || hasPending)
        ActionTile(
          icon: CupertinoIcons.add_circled_solid,
          color: Theme.of(context).colorScheme.tertiary,
          title: AppStrings.homeCapture,
          subtitle: '遇到新错题时随时补充档案',
          trailing: AppStrings.homeCapture,
          onTap: onCapture,
        ),
    ];

    final primaryAction = FilledButton.icon(
      onPressed: recommendation.onTap,
      icon: Icon(recommendation.icon, size: 18),
      label: Text(recommendation.action),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, AppControlSize.standard),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '今天最值得做什么',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 3),
        Text(
          '根据到期复习、待确认内容和近期错因自动排序。',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        BestNextActionCard(
          icon: recommendation.icon,
          title: recommendation.title,
          reason: recommendation.reason,
          meta: recommendation.meta,
          action: recommendation.action,
          streakDays: plan.streakDays,
          onTap: recommendation.onTap,
          primaryAction: primaryAction,
        ),
        if (secondary.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpace.sm),
          Text(
            '其他可做',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 520 || secondary.length == 1) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: secondary
                      .expand((item) => <Widget>[item, const SizedBox(height: AppSpace.sm)])
                      .toList()
                    ..removeLast(),
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (var index = 0; index < secondary.length; index++) ...<Widget>[
                    if (index > 0) const SizedBox(width: AppSpace.sm),
                    Expanded(child: secondary[index]),
                  ],
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

class BestNextActionCard extends StatelessWidget {
  const BestNextActionCard({
    required this.icon,
    required this.title,
    required this.reason,
    required this.meta,
    required this.action,
    required this.streakDays,
    required this.onTap,
    this.primaryAction,
  });

  final IconData icon;
  final String title;
  final String reason;
  final String meta;
  final String action;
  final int streakDays;
  final VoidCallback onTap;
  final Widget? primaryAction;

  @override
  Widget build(BuildContext context) {
    final visual = AppVisualTokens.of(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(visual.cardRadius),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 520;
                final header = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: visual.heroGradient,
                        borderRadius: BorderRadius.circular(visual.controlRadius),
                      ),
                      child: Icon(icon, color: Colors.white, size: 23),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Wrap(
                            spacing: AppSpace.xs,
                            runSpacing: AppSpace.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: <Widget>[
                              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                              if (streakDays > 0)
                                AppTag(label: '连续 $streakDays 天', useThemeTone: true, themeTone: AppTagTone.warning, fontSize: 11),
                            ],
                          ),
                          const SizedBox(height: AppSpace.xs),
                          Text(reason, style: TextStyle(fontSize: 13, height: 1.45, color: Theme.of(context).colorScheme.onSurface)),
                          const SizedBox(height: AppSpace.sm),
                          Text(meta, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                );
                final actionButton = SizedBox(
                  width: compact ? double.infinity : null,
                  child: primaryAction ?? FilledButton(onPressed: onTap, child: Text(action)),
                );
                return compact
                    ? Column(children: <Widget>[header, const SizedBox(height: AppSpace.md), actionButton])
                    : Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Expanded(child: header), const SizedBox(width: AppSpace.md), actionButton]);
              },
            ),
          ),
      ),
    ),
    );
  }
}

class ActionTile extends StatelessWidget {
  const ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppActionCard(
      icon: icon,
      title: title,
      subtitle: subtitle,
      accentColor: color,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            trailing,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 2),
          Icon(CupertinoIcons.chevron_right, size: 14, color: color),
        ],
      ),
    );
  }
}

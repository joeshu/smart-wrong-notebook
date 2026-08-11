import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_patch.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_review.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_split_result.dart';
import 'package:smart_wrong_notebook/src/app/theme/app_visual_style.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_layout.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

class CandidateSwitcherCard extends StatelessWidget {
  const CandidateSwitcherCard({
    required this.splitResult,
    required this.safeCandidateIndex,
    required this.onSelected,
  });

  final QuestionSplitResult splitResult;
  final int safeCandidateIndex;
  final void Function(int index) onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = AppColors.accentPurple;

    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border:
            Border.all(color: accent.withValues(alpha: isDark ? 0.28 : 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.16 : 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(CupertinoIcons.square_list,
                    size: 16, color: accent),
              ),
              const SizedBox(width: AppSpace.sm + 2),
              Text('题号切换',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface)),
            ],
          ),
          const SizedBox(height: AppSpace.md + 2),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 460;
              final chips = Row(
                mainAxisSize: MainAxisSize.min,
                children: splitResult.candidates.asMap().entries.map((entry) {
                  final candidate = entry.value;
                  final isActive = entry.key == safeCandidateIndex;
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpace.sm),
                    child: ChoiceChip(
                      key: ValueKey<String>('candidate-chip-${candidate.order}'),
                      label: Text('第 ${candidate.order} 题'),
                      selected: isActive,
                      onSelected: (_) => onSelected(entry.key),
                      labelStyle: TextStyle(
                        fontSize: 14,
                        color: isActive
                            ? colorScheme.onPrimary
                            : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                      selectedColor: colorScheme.primary,
                      backgroundColor: colorScheme.surface,
                      side: BorderSide(
                        color: isActive
                            ? colorScheme.primary
                            : colorScheme.outlineVariant,
                      ),
                    ),
                  );
                }).toList(),
              );
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: chips,
              );
            },
          ),
        ],
      ),
    );
  }
}

class ReviewRequiredBanner extends StatelessWidget {
  const ReviewRequiredBanner({
    required this.decision,
    required this.confidence,
    this.onConfirm,
    this.isConfirming = false,
  });

  final AiAnalysisReviewDecision decision;
  final double? confidence;
  final VoidCallback? onConfirm;
  final bool isConfirming;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final score = confidence == null
        ? '可信度未知'
        : '整体可信度 ${(confidence! * 100).round()}%';
    return Semantics(
      container: true,
      label: 'AI 结果待人工确认，$score',
      child: Container(
        key: const ValueKey<String>('analysis-review-required-banner'),
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppColors.warning.withValues(alpha: 0.16)
              : AppColors.warningContainerLight,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: Border.all(
            color: AppColors.warning.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(
              CupertinoIcons.exclamationmark_shield,
              color: AppColors.warningDark,
              size: 22,
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'AI 结果待人工确认 · $score',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    decision.fields.isEmpty
                        ? '存在低置信度或无法自动核验的内容。'
                        : '需核对：${decision.fields.join('、')}。',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (decision.reasons.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      decision.reasons.take(2).join('；'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpace.xs),
                  const Text(
                    '确认前不会进入复习计划，也不能直接开始练习。',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warningDark,
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      key: const ValueKey<String>('analysis-confirm-result-button'),
                      onPressed: onConfirm,
                      icon: isConfirming
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(CupertinoIcons.checkmark_shield),
                      label: Text(isConfirming ? '正在确认...' : '我已核对，确认采用'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AnalysisLayerHeader extends StatelessWidget {
  const AnalysisLayerHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class StyledInsightSection extends StatelessWidget {
  const StyledInsightSection({
    required this.style,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tone,
    required this.child,
    this.collapsible = false,
    this.initiallyExpanded = true,
  });

  final AppVisualStyle style;
  final String title;
  final String subtitle;
  final IconData icon;
  final AppTagTone tone;
  final Widget child;
  final bool collapsible;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visual = AppVisualTokens.of(context);
    final badgeText = switch (style) {
      AppVisualStyle.academic => '结论卡',
      AppVisualStyle.paper => '批注区',
      AppVisualStyle.aurora => '聚焦输出',
      AppVisualStyle.forest => '先看这一块',
    };

    return AppInfoSection(
      icon: icon,
      title: title,
      useThemeTone: true,
      themeTone: tone,
      collapsible: collapsible,
      initiallyExpanded: initiallyExpanded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: visual.heroGradient,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeText,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          child,
        ],
      ),
    );
  }
}

class ConsistencyNoticeData {
  const ConsistencyNoticeData({
    required this.text,
    required this.icon,
    required this.color,
    required this.background,
  });

  final String text;
  final IconData icon;
  final Color color;
  final Color background;
}

class ConsistencyNotice extends StatelessWidget {
  const ConsistencyNotice({required this.notice});

  final ConsistencyNoticeData notice;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm + 2, vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color:
            isDark ? notice.color.withValues(alpha: 0.14) : notice.background,
        borderRadius: BorderRadius.circular(AppRadius.small + 2),
        border: Border.all(color: notice.color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(notice.icon, size: 15, color: notice.color),
          const SizedBox(width: AppSpace.xs + 2),
          Expanded(
            child: Text(
              notice.text,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: isDark
                    ? Theme.of(context).colorScheme.onSurface
                    : notice.color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ReviewFieldPanel extends StatelessWidget {
  const ReviewFieldPanel({
    required this.record,
    required this.result,
    required this.actionsEnabled,
    required this.repairingField,
    required this.onEdit,
    required this.onRetry,
  });

  final QuestionRecord record;
  final AnalysisResult result;
  final bool actionsEnabled;
  final String? repairingField;
  final ValueChanged<String> onEdit;
  final ValueChanged<String> onRetry;

  @override
  Widget build(BuildContext context) {
    final fields = result.reviewDecision.fields.isEmpty
        ? const <String>['analysis']
        : result.reviewDecision.fields;
    return Container(
      key: const ValueKey<String>('review-field-panel'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(CupertinoIcons.list_bullet, size: 18),
              const SizedBox(width: AppSpace.xs),
              Text(
                '待确认字段',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          if (!actionsEnabled)
            Text(
              '多题候选或非待确认状态下先展示字段风险，暂不直接编辑。',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ...fields.map((field) => Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: ReviewFieldCard(
                  fieldName: field,
                  value: reviewFieldDisplayValue(result, record, field),
                  confidence: reviewFieldConfidence(result, field),
                  reason: reviewFieldReason(result, field),
                  evidence: reviewFieldEvidence(result, field),
                  canEdit: actionsEnabled && isEditableReviewField(field),
                  canRetry: actionsEnabled &&
                      retryFieldsForReviewField(field) != null &&
                      repairingField == null,
                  isRetrying: repairingField == field,
                  onEdit: () => onEdit(field),
                  onRetry: () => onRetry(field),
                ),
              )),
        ],
      ),
    );
  }
}

class ReviewFieldCard extends StatelessWidget {
  const ReviewFieldCard({
    required this.fieldName,
    required this.value,
    required this.confidence,
    required this.reason,
    required this.evidence,
    required this.canEdit,
    required this.canRetry,
    required this.isRetrying,
    required this.onEdit,
    required this.onRetry,
  });

  final String fieldName;
  final String value;
  final double? confidence;
  final String reason;
  final String evidence;
  final bool canEdit;
  final bool canRetry;
  final bool isRetrying;
  final VoidCallback onEdit;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final confidenceText = confidence == null
        ? '置信度未知'
        : '置信度 ${(confidence! * 100).round()}%';
    return Container(
      key: ValueKey<String>('review-field-card-$fieldName'),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(AppRadius.small + 2),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  reviewFieldLabel(fieldName),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              AppTag(
                label: confidenceText,
                textColor: AppColors.warningDark,
                backgroundColor: AppColors.warningContainerLight,
              ),
            ],
          ),
          if (reason.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpace.xs),
            Text(
              reason,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
          if (evidence.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpace.xs),
            Text(
              '证据：$evidence',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
          if (value.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpace.xs),
            Text(
              value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurface),
            ),
          ],
          const SizedBox(height: AppSpace.xs),
          Wrap(
            spacing: AppSpace.xs,
            children: <Widget>[
              TextButton.icon(
                key: ValueKey<String>('review-field-edit-$fieldName'),
                onPressed: canEdit ? onEdit : null,
                icon: const Icon(CupertinoIcons.pencil, size: 16),
                label: const Text('编辑'),
              ),
              OutlinedButton.icon(
                onPressed: canRetry ? onRetry : null,
                icon: isRetrying
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.arrow_clockwise, size: 16),
                label: Text(isRetrying ? '重试中' : '重新分析'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

AiAnalysisField? parseReviewField(String fieldName) {
  for (final field in AiAnalysisField.values) {
    if (field.name == fieldName) return field;
  }
  return null;
}

Set<AiAnalysisField>? retryFieldsForReviewField(String fieldName) {
  final field = parseReviewField(fieldName);
  if (field == null) return null;
  if (field == AiAnalysisField.mistakeReason ||
      field == AiAnalysisField.mistakeCategory) {
    return const <AiAnalysisField>{
      AiAnalysisField.mistakeCategory,
      AiAnalysisField.mistakeReason,
    };
  }
  return <AiAnalysisField>{field};
}

bool isEditableReviewField(String fieldName) => const <String>{
      'normalizedQuestion',
      'studentAnswer',
      'standardAnswer',
      'solutionSteps',
      'knowledgePoints',
      'mistakeReason',
      'studyAdvice',
    }.contains(fieldName);

String reviewFieldLabel(String fieldName) {
  switch (fieldName) {
    case 'analysis':
      return '整体分析';
    case 'normalizedQuestion':
      return '规范题干';
    case 'studentAnswer':
      return '学生作答';
    case 'standardAnswer':
      return '标准答案';
    case 'solutionSteps':
      return '解题步骤';
    case 'knowledgePoints':
      return '知识点';
    case 'mistakeCategory':
      return '错因分类';
    case 'mistakeReason':
      return '错因说明';
    case 'studyAdvice':
      return '学习建议';
    case 'reviewPlan':
      return '复习计划';
    case 'generatedExercises':
      return '练习题';
    case 'visualAssumptions':
      return '图形假设';
    default:
      return fieldName;
  }
}

String reviewFieldEditableValue(
  AnalysisResult result,
  QuestionRecord record,
  String fieldName,
) {
  switch (fieldName) {
    case 'solutionSteps':
      return result.solutionSteps.isNotEmpty
          ? result.solutionSteps.join('\n')
          : result.steps.join('\n');
    case 'knowledgePoints':
      return result.knowledgePoints.join('\n');
    default:
      return reviewFieldDisplayValue(result, record, fieldName);
  }
}

String reviewFieldDisplayValue(
  AnalysisResult result,
  QuestionRecord record,
  String fieldName,
) {
  switch (fieldName) {
    case 'normalizedQuestion':
      return result.normalizedQuestion.isNotEmpty
          ? result.normalizedQuestion
          : record.correctedText;
    case 'studentAnswer':
      return (record.studentAnswer ?? result.studentAnswer).trim();
    case 'standardAnswer':
      return result.standardAnswer.isNotEmpty
          ? result.standardAnswer
          : result.finalAnswer;
    case 'solutionSteps':
      return (result.solutionSteps.isNotEmpty ? result.solutionSteps : result.steps)
          .join('\n');
    case 'knowledgePoints':
      return result.knowledgePoints.join('、');
    case 'mistakeCategory':
      return result.mistakeCategory?.name ?? '';
    case 'mistakeReason':
      return result.mistakeReason;
    case 'studyAdvice':
      return result.studyAdvice;
    case 'reviewPlan':
      final plan = result.reviewPlan;
      if (plan == null) return '';
      return '${plan.reviewAfterDays} 天后复习：${plan.focus.join('、')}';
    case 'visualAssumptions':
      return result.visualAssumptions?.reviewReason ?? '';
    default:
      return '';
  }
}

double? reviewFieldConfidence(AnalysisResult result, String fieldName) {
  if (fieldName == 'analysis') return result.confidence?.overall;
  return result.confidence?.fields[fieldName];
}

String reviewFieldReason(AnalysisResult result, String fieldName) {
  final uncertainty = result.uncertainties
      .where((item) => item.field == fieldName)
      .map((item) => item.description)
      .join('；');
  if (uncertainty.isNotEmpty) return uncertainty;
  final label = reviewFieldLabel(fieldName);
  for (final reason in result.reviewDecision.reasons) {
    if (reason.contains(fieldName) || reason.contains(label)) return reason;
  }
  return result.reviewDecision.reasons.isEmpty
      ? ''
      : result.reviewDecision.reasons.first;
}

String reviewFieldEvidence(AnalysisResult result, String fieldName) {
  final evidence = result.evidence
      .where((item) => item.field == fieldName)
      .map((item) => item.quote.isEmpty ? item.explanation : item.quote)
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  return evidence.take(2).join('；');
}

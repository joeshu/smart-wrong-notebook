import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/app/theme/app_visual_style.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_review.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_patch.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/services/ai_analysis_confirmation_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/ai_analysis_review_policy.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_split_result.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/cached_question_image.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/confidence_badge.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_layout.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/features/analysis/presentation/specialized_analysis_section.dart';
import 'package:smart_wrong_notebook/src/features/analysis/presentation/widgets/analysis_result_sections.dart';

class AnalysisResultScreen extends ConsumerStatefulWidget {
  const AnalysisResultScreen({super.key});

  @override
  ConsumerState<AnalysisResultScreen> createState() =>
      _AnalysisResultScreenState();
}

class _AnalysisResultScreenState extends ConsumerState<AnalysisResultScreen> {
  int _activeCandidateIndex = 0;
  bool _isConfirming = false;
  String? _repairingField;

  @override
  Widget build(BuildContext context) {
    final record = ref.watch(currentQuestionProvider);

    if (record == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('AI 解析结果'),
          leading: IconButton(
            icon: const Icon(CupertinoIcons.chevron_left),
            onPressed: () => context.go('/analysis/loading'),
          ),
        ),
        body: const Center(child: Text('未找到错题记录')),
      );
    }

    final result = record.analysisResult;
    final splitResult = record.splitResult;
    final hasMultipleCandidates = splitResult?.hasMultipleCandidates ?? false;
    final safeCandidateIndex = hasMultipleCandidates
        ? _activeCandidateIndex.clamp(0, splitResult!.candidates.length - 1)
        : 0;
    final activeCandidate = hasMultipleCandidates
        ? splitResult!.candidates[safeCandidateIndex]
        : null;
    final activeCandidateAnalysis = activeCandidate == null
        ? null
        : record.candidateAnalyses.firstWhereOrNull(
            (candidate) => candidate.candidateId == activeCandidate.id);
    final displayResult = hasMultipleCandidates
        ? activeCandidateAnalysis?.analysisResult
        : result;
    final displayAiTags = hasMultipleCandidates
        ? activeCandidateAnalysis?.aiTags ?? const <String>[]
        : record.aiTags;
    final displayKnowledgePoints = hasMultipleCandidates
        ? activeCandidateAnalysis?.aiKnowledgePoints ?? const <String>[]
        : result?.knowledgePoints ?? const <String>[];
    final displayQuestionText = activeCandidateAnalysis?.questionText ??
        activeCandidate?.text ??
        record.correctedText;
    final displayExercises = hasMultipleCandidates
        ? activeCandidateAnalysis?.savedExercises ?? const []
        : record.savedExercises;
    final candidateInsight = hasMultipleCandidates
        ? _candidateInsight(
            candidateOrder: activeCandidate?.order ?? 1,
            total: splitResult?.candidates.length ?? 1,
            hasIndependentAnalysis: activeCandidateAnalysis != null,
          )
        : null;
    final requiresConfirmation =
        displayResult?.reviewDecision.requiresConfirmation ?? false;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final analysisStyle = AppVisualTokens.of(context).style;
    final layoutProvider = record.tags
        .where((tag) => tag.startsWith('layout_provider:'))
        .map((tag) => tag.substring('layout_provider:'.length))
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 解析结果'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => context.go('/capture/save-confirmation'),
        ),
        actions: <Widget>[
          TextButton.icon(
            onPressed: () => _confirmDiscard(record),
            icon: const Icon(CupertinoIcons.trash, size: 18),
            label: const Text('放弃'),
          ),
        ],
      ),
      body: AppPage(
        maxWidth: AppContentWidth.wide,
        padding: EdgeInsets.zero,
        child: ListView(
        cacheExtent: 4000,
        padding: const EdgeInsets.all(AppSpace.lg),
        children: <Widget>[
          const AppTaskFlow(
            steps: <String>['拍一道错题', '确认识别', '查看错误定位', '开始练习'],
            currentStep: 2,
          ),
          const SizedBox(height: AppSpace.lg),
          if (displayResult?.reviewDecision.requiresConfirmation ?? false) ...<Widget>[
            ReviewRequiredBanner(
              decision: displayResult!.reviewDecision,
              confidence: displayResult.confidence?.overall,
              onConfirm: _isConfirming ||
                      hasMultipleCandidates ||
                      record.contentStatus != ContentStatus.needsConfirmation
                  ? null
                  : () => _confirmCurrentResult(record),
              isConfirming: _isConfirming,
            ),
            const SizedBox(height: AppSpace.md),
            ReviewFieldPanel(
              record: record,
              result: displayResult,
              actionsEnabled: !hasMultipleCandidates &&
                  record.contentStatus == ContentStatus.needsConfirmation,
              repairingField: _repairingField,
              onEdit: (field) => _editReviewField(record, displayResult, field),
              onRetry: (field) => _retryReviewField(record, displayResult, field),
            ),
            const SizedBox(height: AppSpace.md),
          ],
          // 统一标签分类框：科目 | AI识别 | 状态 | 知识点
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md, vertical: AppSpace.md - 2),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.medium),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // 第一行：科目 + AI识别 + 状态
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  children: <Widget>[
                    AppTag(
                      label:
                          displayResult?.subject?.label ?? record.subject.label,
                      useThemeTone: true,
                      themeTone: AppTagTone.primary,
                    ),
                    if (displayResult?.subject != null)
                      AppTag(
                        label: 'AI识别',
                        useThemeTone: true,
                        themeTone: AppTagTone.success,
                      ),
                    AppTag(
                      label: _masteryLabel(record.masteryLevel),
                      textColor: _masteryColor(record.masteryLevel),
                      backgroundColor:
                          _masteryColor(record.masteryLevel).withValues(alpha: 0.1),
                    ),
                    if (layoutProvider.isNotEmpty)
                      AppTag(
                        label: '切题：$layoutProvider',
                        useThemeTone: true,
                        themeTone: AppTagTone.secondary,
                      ),
                  ],
                ),
                if (record.splitResult != null) ...<Widget>[
                  const SizedBox(height: AppSpace.sm + 2),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs + 2,
                    children: <Widget>[
                      AppTag(
                        label: '候选 ${record.splitResult!.candidates.length} 题',
                        useThemeTone: true,
                        themeTone: AppTagTone.tertiary,
                      ),
                      AppTag(
                        label:
                            _splitStrategyLabel(record.splitResult!.strategy),
                        useThemeTone: true,
                        themeTone: AppTagTone.neutral,
                      ),
                      if (activeCandidate != null)
                        AppTag(
                          label: '当前第 ${activeCandidate.order} 题',
                          useThemeTone: true,
                          themeTone: AppTagTone.warning,
                        ),
                    ],
                  ),
                  if (record.splitResult!.hasMultipleCandidates) ...<Widget>[
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      '这张图片已识别为多题内容，保存时会进入逐题确认。',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
                // AI 短标签（橙色）
                if (displayAiTags.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpace.sm + 2),
                  Text('AI标签',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: AppSpace.xs),
                  Wrap(
                    spacing: AppSpace.xs + 2,
                    runSpacing: AppSpace.xs,
                    children: displayAiTags
                        .map((tag) => AppTag(
                              label: tag,
                              useThemeTone: true,
                              themeTone: AppTagTone.warning,
                            ))
                        .toList(),
                  ),
                ],
                // 自定义标签（蓝色）
                if (record.customTags.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpace.sm),
                  Text('自定义标签',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: AppSpace.xs),
                  Wrap(
                    spacing: AppSpace.xs + 2,
                    runSpacing: AppSpace.xs,
                    children: record.customTags
                        .map((t) => AppTag(
                              label: t,
                              useThemeTone: true,
                              themeTone: AppTagTone.primary,
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          if (record.splitResult?.hasMultipleCandidates ?? false) ...<Widget>[
            const SizedBox(height: AppSpace.md),
            CandidateSwitcherCard(
              splitResult: splitResult!,
              safeCandidateIndex: safeCandidateIndex,
              onSelected: (index) =>
                  setState(() => _activeCandidateIndex = index),
            ),
          ],
          if (displayResult == null) ...<Widget>[
            const SizedBox(height: AppSpace.lg + 4),
            AppInfoSection(
              icon: CupertinoIcons.exclamationmark_triangle,
              iconColor: AppColors.danger,
              backgroundColor: AppColors.dangerContainerLight,
              borderColor: const Color(0xFFFECACA),
              title: '第 ${activeCandidate?.order ?? 1}题解析失败',
              titleColor: isDark ? AppColors.dangerLight : AppColors.dangerDark,
              child: MathContentView(
                activeCandidateAnalysis?.errorMessage?.isNotEmpty == true
                    ? '已自动重试，仍未成功。该题暂不可保存，可返回重新解析。\n${activeCandidateAnalysis!.errorMessage}'
                    : '已自动重试，仍未成功。该题暂不可保存，可返回重新解析。',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? AppColors.dangerLight : AppColors.dangerDark,
                  height: 1.5,
                ),
              ),
            ),
          ],
          if (displayResult != null) ...<Widget>[
            const SizedBox(height: AppSpace.lg),
            _TenSecondSummary(
              style: analysisStyle,
              result: displayResult,
              consistencyNotice: _consistencyNotice(displayResult),
            ),
            const SizedBox(height: AppSpace.md),
            AnalysisLayerHeader(
              title: '展开学习',
              subtitle: '以下内容默认收起，需要时再查看完整依据。',
              icon: CupertinoIcons.book,
            ),
            const SizedBox(height: AppSpace.sm),
            StyledInsightSection(
              style: analysisStyle,
              title: '错误定位',
              subtitle: switch (analysisStyle) {
                AppVisualStyle.academic => '先明确错在哪里，再决定是补概念、补步骤还是补审题。',
                AppVisualStyle.paper => '像批改作业一样，把真正失分点圈出来。',
                AppVisualStyle.aurora => '优先锁定最核心的错误信号，减少无效信息。',
                AppVisualStyle.forest => '先看这一题最需要修正的一点，不必一次背太多。',
              },
              icon: CupertinoIcons.scope,
              tone: AppTagTone.warning,
              collapsible: true,
              initiallyExpanded: false,
              child: MathContentView(
                displayResult.mistakeReason,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? AppColors.warningLight : AppColors.warningDark,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (displayResult.specializedAnalysis != null) ...<Widget>[
              const SizedBox(height: AppSpace.md),
              SpecializedAnalysisSection(
                analysis: displayResult.specializedAnalysis!,
              ),
            ],
            const SizedBox(height: AppSpace.sm),
            // 原题（包含图片和文本）
            StyledInsightSection(
              style: analysisStyle,
              title: '原题',
              subtitle: switch (analysisStyle) {
                AppVisualStyle.academic => '核对题干、条件和作答对象，避免后续分析建立在错误前提上。',
                AppVisualStyle.paper => '先把原题完整读清，再看后面的批注与结论。',
                AppVisualStyle.aurora => '把输入源对齐，确保后续解析都基于同一道题。',
                AppVisualStyle.forest => '先安静地把题目看一遍，别急着跳到结论。',
              },
              icon: CupertinoIcons.doc_text,
              tone: AppTagTone.primary,
              collapsible: true,
              initiallyExpanded: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (record.ocrConfidence != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.sm),
                      child: ConfidenceBadge(
                        confidence: record.ocrConfidence,
                        compact: true,
                      ),
                    ),
                  if (File(record.imagePath).existsSync())
                    GestureDetector(
                      onTap: () => _showFullImage(context, record.imagePath),
                      child: Container(
                        height: 120,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AppRadius.small),
                        ),
                        child: Stack(
                          children: <Widget>[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.small),
                              child: SizedBox(
                                width: double.infinity,
                                height: 120,
                                child: CachedQuestionImage(
                                  record.imagePath,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.62),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(CupertinoIcons.zoom_in,
                                        size: 12, color: Colors.white,
                                        shadows: <Shadow>[
                                          Shadow(color: Colors.black54, blurRadius: 2),
                                        ]),
                                    SizedBox(width: 3),
                                    Text('查看原图',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.white,
                                            shadows: <Shadow>[
                                              Shadow(color: Colors.black54, blurRadius: 2),
                                            ])),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (File(record.imagePath).existsSync())
                    const SizedBox(height: AppSpace.sm + 2),
                  MathContentView(
                    displayQuestionText,
                    contentFormat: hasMultipleCandidates
                        ? QuestionContentFormat.latexMixed
                        : record.contentFormat,
                    style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                        height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.sm + 2),
            // Answer
            StyledInsightSection(
              style: analysisStyle,
              title: displayResult.visualAssumptionStatus ==
                      VisualAssumptionStatus.needsReview
                  ? '可能解法'
                  : '正确解答',
              subtitle: switch (analysisStyle) {
                AppVisualStyle.academic => '先给结论，再核对依据和一致性。',
                AppVisualStyle.paper => '把最后可采用的答案整理成可回看的结论。',
                AppVisualStyle.aurora => '优先看 AI 最终输出与一致性信号。',
                AppVisualStyle.forest => '只先关注这题最需要记住的结果。',
              },
              icon: displayResult.visualAssumptionStatus ==
                      VisualAssumptionStatus.needsReview
                  ? CupertinoIcons.exclamationmark_triangle
                  : CupertinoIcons.checkmark_circle,
              tone: displayResult.visualAssumptionStatus ==
                      VisualAssumptionStatus.needsReview
                  ? AppTagTone.warning
                  : AppTagTone.success,
              collapsible: true,
              initiallyExpanded: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  MathContentView(
                    displayResult.finalAnswer,
                    style: TextStyle(
                        fontSize: 14,
                        color: isDark ? AppColors.successLight : const Color(0xFF15803D),
                        fontWeight: FontWeight.w600),
                  ),
                  if (_consistencyNotice(displayResult) != null) ...<Widget>[
                    const SizedBox(height: AppSpace.sm + 2),
                    ConsistencyNotice(
                      notice: _consistencyNotice(displayResult)!,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: AppSpace.sm + 2),
            // Study advice
            StyledInsightSection(
              style: analysisStyle,
              title: '学习建议',
              subtitle: switch (analysisStyle) {
                AppVisualStyle.academic => '把下一步练习动作压缩成可执行建议。',
                AppVisualStyle.paper => '更像老师批注，告诉你这题之后该怎么练。',
                AppVisualStyle.aurora => '把注意力收拢到最值得修正的一点。',
                AppVisualStyle.forest => '减少负担，只看眼下最需要记住的提醒。',
              },
              icon: CupertinoIcons.lightbulb,
              tone: AppTagTone.tertiary,
              collapsible: true,
              initiallyExpanded: false,
              child: MathContentView(
                displayResult.studyAdvice,
                style: TextStyle(
                    fontSize: 14,
                    color: isDark ? AppColors.accentAmber : const Color(0xFFB45309),
                    height: 1.5),
              ),
            ),
            if (candidateInsight != null) ...<Widget>[
              const SizedBox(height: AppSpace.sm + 2),
              StyledInsightSection(
                style: analysisStyle,
                title: '当前子题状态',
                subtitle: switch (analysisStyle) {
                  AppVisualStyle.academic => '当前查看的是切题后的独立分析结果。',
                  AppVisualStyle.paper => '把这道子题单独拎出来，避免上下题信息混杂。',
                  AppVisualStyle.aurora => '聚焦当前子题，不让多题内容干扰判断。',
                  AppVisualStyle.forest => '先只看这一题，减少一次处理的信息量。',
                },
                icon: CupertinoIcons.layers,
                tone: AppTagTone.secondary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    MathContentView(
                      candidateInsight,
                      style: TextStyle(
                          fontSize: 13,
                          color: isDark ? AppColors.accentTealLight : const Color(0xFF134E4A),
                          height: 1.5),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      activeCandidateAnalysis != null
                          ? '当前已切换到第 ${activeCandidate?.order ?? 1} 题独立解析。'
                          : '第 ${activeCandidate?.order ?? 1} 题暂无独立解析。',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
            // Knowledge points
            if (displayKnowledgePoints.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpace.lg),
              Text('知识点',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpace.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: displayKnowledgePoints
                    .map((p) => AppCard(
                          margin: const EdgeInsets.only(bottom: AppSpace.xs + 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpace.sm + 2, vertical: AppSpace.xs + 1),
                          borderRadius: AppRadius.small,
                          child: MathContentView(
                            p,
                            style: TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color: isDark
                                    ? colorScheme.onSurface
                                    : AppColors.primaryDark),
                          ),
                        ))
                    .toList(),
              ),
            ],
            // Detailed reasoning stays available without competing with the conclusion.
            if (displayResult.steps.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpace.lg),
              AppInfoSection(
                icon: CupertinoIcons.list_number,
                title: '详细解题步骤',
                collapsible: true,
                initiallyExpanded: false,
                child: Column(
                  children: displayResult.steps.asMap().entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.md),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Text(
                              '${entry.key + 1}',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          const SizedBox(width: AppSpace.sm),
                          Expanded(
                            child: MathContentView(
                              entry.value,
                              style: TextStyle(
                                fontSize: 14,
                                color: colorScheme.onSurface,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(growable: false),
                ),
              ),
            ],
            // Exercises
            if (displayExercises.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpace.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text('举一反三',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text('${displayExercises.length} 题',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
              if (activeCandidate != null) ...<Widget>[
                const SizedBox(height: AppSpace.xs + 2),
                Text(
                  activeCandidateAnalysis != null
                      ? '当前展示第 ${activeCandidate.order} 题独立生成的练习。'
                      : '第 ${activeCandidate.order} 题暂无独立练习。',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: AppSpace.sm + 2),
              ...displayExercises.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: AppCard(
                      padding: const EdgeInsets.all(AppSpace.md),
                      borderRadius: AppRadius.medium,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpace.sm, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _difficultyColor(context, e.difficulty)
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  e.difficulty,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        _difficultyColor(context, e.difficulty),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              if (e.isCorrect == true)
                                const Icon(CupertinoIcons.checkmark_circle,
                                    color: AppColors.success, size: 18)
                              else if (e.isCorrect == false)
                                const Icon(CupertinoIcons.xmark_circle,
                                    color: AppColors.warning, size: 18),
                            ],
                          ),
                          const SizedBox(height: AppSpace.sm),
                          MathContentView(
                            e.question,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: AppSpace.xs),
                          Row(
                            children: <Widget>[
                              Icon(CupertinoIcons.lightbulb,
                                  size: 14,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: 0.65)),
                              const SizedBox(width: AppSpace.xs),
                              Expanded(
                                child: MathContentView(
                                  '答案：${e.answer}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                          if (e.explanation.isNotEmpty) ...<Widget>[
                            const SizedBox(height: AppSpace.xs),
                            MathContentView(
                              e.explanation,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )),
            ],
            const SizedBox(height: AppSpace.xl),
          ],
        ],
        ),
      ),
      bottomNavigationBar: displayResult == null
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.xl,
                  AppSpace.sm,
                  AppSpace.xl,
                  AppSpace.sm,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppContentWidth.standard,
                    ),
                    child: requiresConfirmation
                        ? FilledButton(
                            onPressed: () => _openSaveFlow(record),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(
                                AppControlSize.standard,
                              ),
                            ),
                            child: const Text('保存为待确认'),
                          )
                        : Row(
                            children: <Widget>[
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _openSaveFlow(record),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(
                                      AppControlSize.standard,
                                    ),
                                  ),
                                  child: const Text('保存到错题本'),
                                ),
                              ),
                              const SizedBox(width: AppSpace.md),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () => _startPractice(
                                    record,
                                    activeCandidateAnalysis,
                                  ),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(
                                      AppControlSize.standard,
                                    ),
                                  ),
                                  child: const Text('开始练习'),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
    );
  }

  Future<void> _openSaveFlow(QuestionRecord record) async {
    final splitter = ref.read(questionSplitServiceProvider);
    ref.read(currentQuestionSplitSessionProvider.notifier).state =
        await buildQuestionSplitSession(record, splitter: splitter);
    if (!mounted) return;
    context.go('/capture/split-confirmation');
  }

  Future<void> _confirmDiscard(QuestionRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('放弃这次识别？'),
        content: const Text('题图、识别结果和本次分析都不会加入错题本。此操作不可恢复。'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('继续查看')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('放弃并删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final worksheet = ref.read(currentWorksheetImportProvider);
    if (worksheet != null && !worksheet.sourcePageIds.contains(record.id)) {
      await persistWorksheetImport(
        ref,
        worksheet.copyWith(pages: worksheet.pages.where((item) => item.id != record.id).toList()),
      );
    }
    await ref.read(questionRepositoryProvider).delete(record.id);
    await ref.read(imageStorageServiceProvider).deleteImage(record.imagePath);
    ref.read(currentQuestionProvider.notifier).state = null;
    invalidateQuestionList(ref);
    if (!mounted) return;
    context.go(worksheet == null ? '/' : '/worksheet/import');
  }

  Future<void> _editReviewField(
    QuestionRecord record,
    AnalysisResult result,
    String fieldName,
  ) async {
    if (!isEditableReviewField(fieldName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${reviewFieldLabel(fieldName)} 暂不支持直接编辑')),
      );
      return;
    }
    final controller = TextEditingController(
      text: reviewFieldEditableValue(result, record, fieldName),
    );
    final edited = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('编辑${reviewFieldLabel(fieldName)}'),
        content: TextField(
          key: ValueKey<String>('review-field-editor-$fieldName'),
          controller: controller,
          maxLines: fieldName == 'solutionSteps' || fieldName == 'knowledgePoints'
              ? 8
              : 5,
          decoration: InputDecoration(
            helperText: fieldName == 'solutionSteps' ||
                    fieldName == 'knowledgePoints'
                ? '每行一项'
                : '请按核对后的内容填写',
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('保存修改'),
          ),
        ],
      ),
    );
    // Do not dispose immediately after showDialog returns: the closing overlay
    // animation can still rebuild the TextField for one frame in widget tests.
    if (!mounted || edited == null) return;
    final trimmed = edited.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('字段内容不能为空')),
      );
      return;
    }

    final updatedResult = _applyManualFieldEdit(result, fieldName, trimmed);
    final affectedFields = _affectedFieldsAfterManualEdit(fieldName);
    final decision = AiAnalysisReviewDecision(
      disposition: AiAnalysisReviewDisposition.needsConfirmation,
      fields: affectedFields,
      reasons: <String>[
        '用户编辑了${reviewFieldLabel(fieldName)}，请核对后确认采用',
      ],
      evaluatedAt: DateTime.now(),
    );
    final reviewedResult = updatedResult.copyWith(
      reviewDecision: decision,
      pipeline: const AiAnalysisPipelineSnapshot(
        status: AiAnalysisPipelineStatus.waitingForConfirmation,
        currentStage: AiAnalysisPipelineStage.questionConfirmation,
        message: '用户已编辑字段，等待确认',
      ),
    );
    var updatedRecord = record.copyWith(
      contentStatus: ContentStatus.needsConfirmation,
      analysisResult: reviewedResult,
      aiTags: reviewedResult.aiTags,
      aiKnowledgePoints: reviewedResult.knowledgePoints,
    );
    if (fieldName == AiAnalysisField.normalizedQuestion.name) {
      updatedRecord = updatedRecord.copyWith(
        normalizedQuestionText: trimmed,
        aiReconstructedText: trimmed,
      );
    } else if (fieldName == AiAnalysisField.studentAnswer.name) {
      updatedRecord = updatedRecord.copyWith(studentAnswer: trimmed);
    } else if (fieldName == AiAnalysisField.standardAnswer.name) {
      updatedRecord = updatedRecord.copyWith(expectedAnswer: trimmed);
    }
    await _persistReviewedRecord(updatedRecord);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已更新${reviewFieldLabel(fieldName)}，请再次核对后确认')),
    );
  }

  Future<void> _retryReviewField(
    QuestionRecord record,
    AnalysisResult result,
    String fieldName,
  ) async {
    final retryFields = retryFieldsForReviewField(fieldName);
    if (retryFields == null || retryFields.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${reviewFieldLabel(fieldName)} 暂不支持局部重试')),
      );
      return;
    }
    if (_repairingField != null) return;
    setState(() => _repairingField = fieldName);
    try {
      final repaired = await ref.read(aiAnalysisServiceProvider).retryAnalysisFields(
            current: result,
            fields: retryFields,
            confirmedQuestion: record.correctedText,
            subjectName: record.subject.name,
            studentAnswer: record.studentAnswer ?? result.studentAnswer,
            imagePath: record.imagePath,
          );
      const policy = AiAnalysisReviewPolicy();
      final hasStudentAnswer =
          (record.studentAnswer ?? repaired.studentAnswer).trim().isNotEmpty;
      var decision = policy.evaluate(
        repaired,
        hasStudentAnswer: hasStudentAnswer,
      );
      if (!decision.requiresConfirmation) {
        decision = AiAnalysisReviewDecision(
          disposition: AiAnalysisReviewDisposition.needsConfirmation,
          fields: retryFields.map((field) => field.name).toList(growable: false),
          reasons: const <String>['字段已重新分析，请核对后确认采用'],
          evaluatedAt: DateTime.now(),
        );
      }
      final reviewedResult = repaired.copyWith(
        reviewDecision: decision,
        pipeline: policy.completedPipeline(decision),
      );
      final updatedRecord = record.copyWith(
        contentStatus: ContentStatus.needsConfirmation,
        analysisResult: reviewedResult,
        subject: reviewedResult.subject ?? record.subject,
        aiTags: reviewedResult.aiTags,
        aiKnowledgePoints: reviewedResult.knowledgePoints,
      );
      await _persistReviewedRecord(updatedRecord);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已重新分析${reviewFieldLabel(fieldName)}，请核对后确认')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('局部重试失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _repairingField = null);
    }
  }

  Future<void> _persistReviewedRecord(QuestionRecord updated) async {
    await ref.read(questionRepositoryProvider).saveDraft(updated);
    final worksheet = ref.read(currentWorksheetImportProvider);
    if (worksheet != null && !worksheet.sourcePageIds.contains(updated.id)) {
      await persistWorksheetImport(
        ref,
        worksheet.copyWith(
          pages: worksheet.pages
              .map((page) => page.id == updated.id ? updated : page)
              .toList(),
        ),
      );
    }
    ref.read(currentQuestionProvider.notifier).state = updated;
    invalidateQuestionList(ref);
  }

  AnalysisResult _applyManualFieldEdit(
    AnalysisResult result,
    String fieldName,
    String value,
  ) {
    final lines = value
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    switch (fieldName) {
      case 'normalizedQuestion':
        return result.copyWith(
          normalizedQuestion: value,
          reconstructedQuestionText: value,
        );
      case 'studentAnswer':
        return result.copyWith(studentAnswer: value);
      case 'standardAnswer':
        return result.copyWith(finalAnswer: value, standardAnswer: value);
      case 'solutionSteps':
        return result.copyWith(steps: lines, solutionSteps: lines);
      case 'knowledgePoints':
        return result.copyWith(knowledgePoints: lines);
      case 'mistakeReason':
        return result.copyWith(mistakeReason: value);
      case 'studyAdvice':
        return result.copyWith(studyAdvice: value);
      default:
        return result;
    }
  }

  List<String> _affectedFieldsAfterManualEdit(String fieldName) {
    switch (fieldName) {
      case 'normalizedQuestion':
      case 'studentAnswer':
        return const <String>[
          'normalizedQuestion',
          'studentAnswer',
          'standardAnswer',
          'solutionSteps',
          'mistakeReason',
          'knowledgePoints',
          'reviewPlan',
        ];
      case 'standardAnswer':
      case 'solutionSteps':
        return const <String>[
          'standardAnswer',
          'solutionSteps',
          'mistakeReason',
          'knowledgePoints',
          'reviewPlan',
        ];
      default:
        return <String>[fieldName];
    }
  }

  Future<void> _confirmCurrentResult(QuestionRecord record) async {
    if (_isConfirming || record.contentStatus != ContentStatus.needsConfirmation) {
      return;
    }
    setState(() => _isConfirming = true);
    try {
      final confirmed = const AiAnalysisConfirmationService().confirm(
        record,
        source: AiConfirmationSource.currentResult,
      );
      await ref.read(questionRepositoryProvider).saveDraft(confirmed);
      final worksheet = ref.read(currentWorksheetImportProvider);
      if (worksheet != null && !worksheet.sourcePageIds.contains(confirmed.id)) {
        await persistWorksheetImport(
          ref,
          worksheet.copyWith(
            pages: worksheet.pages
                .map((page) => page.id == confirmed.id ? confirmed : page)
                .toList(),
          ),
        );
      }
      ref.read(currentQuestionProvider.notifier).state = confirmed;
      invalidateQuestionList(ref);
      // Knowledge links are created only after explicit confirmation.
      if (confirmed.aiKnowledgePoints.isNotEmpty) {
        try {
          await ref.read(knowledgePointMappingServiceProvider).createLinksForQuestion(
                questionId: confirmed.id,
                knowledgePointTexts: confirmed.aiKnowledgePoints,
              );
          invalidatePendingKnowledgePoints(ref);
        } catch (_) {
          // A mapping failure must not undo the user's explicit confirmation.
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已确认，题目现在可以进入练习和复习计划')),
      );
      setState(() {});
    } on AiAnalysisConfirmationException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('确认失败：${error.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  void _startPractice(
    QuestionRecord record,
    CandidateAnalysisSnapshot? activeCandidateAnalysis,
  ) {
    ref.read(currentPracticeContextProvider.notifier).state = PracticeContext(
      source: PracticeContextSource.analysis,
      candidateId: activeCandidateAnalysis?.candidateId,
      candidateOrder: activeCandidateAnalysis?.order,
      returnRoute: '/analysis/result',
    );
    ref.read(currentQuestionProvider.notifier).state = record;
    context.go('/exercise/practice');
  }

  String _candidateInsight({
    required int candidateOrder,
    required int total,
    required bool hasIndependentAnalysis,
  }) {
    return hasIndependentAnalysis
        ? '当前正在查看第 $candidateOrder / $total 题，已切换到独立解析结果。'
        : '当前正在查看第 $candidateOrder / $total 题，题干切换已生效。';
  }

  String _splitStrategyLabel(Object strategy) {
    switch (strategy.toString().split('.').last) {
      case 'numbered':
        return '编号拆题';
      case 'paragraph':
        return '分段拆题';
      default:
        return '单题回退';
    }
  }

  Color _difficultyColor(BuildContext context, String difficulty) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (difficulty) {
      case '简单':
        return AppColors.success;
      case '中等':
        return AppColors.accentAmber;
      case '困难':
        return AppColors.danger;
      case '提高':
        return AppColors.accentPurple;
      case '同级':
        return AppColors.info;
      default:
        return colorScheme.onSurfaceVariant;
    }
  }

  ConsistencyNoticeData? _consistencyNotice(AnalysisResult result) {
    switch (result.consistencyStatus) {
      case AnalysisConsistencyStatus.repaired:
        if (result.visualAssumptionStatus ==
            VisualAssumptionStatus.needsReview) {
          return ConsistencyNoticeData(
            text: result.consistencyNote.isNotEmpty
                ? result.consistencyNote
                : 'AI 已复核答案；图中关键标注含义仍需核对',
            icon: CupertinoIcons.exclamationmark_triangle,
            color: AppColors.warning,
            background: AppColors.warningContainerLight,
          );
        }
        return ConsistencyNoticeData(
          text: 'AI 已复核并修正答案',
          icon: CupertinoIcons.checkmark_shield,
          color: AppColors.success,
          background: AppColors.successContainerLight,
        );
      case AnalysisConsistencyStatus.needsReview:
        if (result.visualAssumptionStatus ==
            VisualAssumptionStatus.needsReview) {
          return ConsistencyNoticeData(
            text: result.consistencyNote.isNotEmpty
                ? result.consistencyNote
                : '图中关键标注含义需核对，当前为可能解法',
            icon: CupertinoIcons.exclamationmark_triangle,
            color: AppColors.warning,
            background: AppColors.warningContainerLight,
          );
        }
        return ConsistencyNoticeData(
          text: '答案与步骤可能不一致，请核对',
          icon: CupertinoIcons.exclamationmark_triangle,
          color: AppColors.warning,
          background: AppColors.warningContainerLight,
        );
      case AnalysisConsistencyStatus.unchecked:
      case AnalysisConsistencyStatus.consistent:
      case AnalysisConsistencyStatus.unverifiable:
        return null;
    }
  }

  void _showFullImage(BuildContext context, String imagePath) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            title: const Text('原图'),
          ),
          body: Center(
            child: InteractiveViewer(
              child: CachedQuestionImage(imagePath, highRes: true),
            ),
          ),
        ),
      ),
    );
  }
}

extension _IterableFirstOrNullExtension<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E item) test) {
    for (final item in this) {
      if (test(item)) return item;
    }
    return null;
  }
}


class _TenSecondSummary extends StatelessWidget {
  const _TenSecondSummary({
    required this.style,
    required this.result,
    required this.consistencyNotice,
  });

  final AppVisualStyle style;
  final AnalysisResult result;
  final ConsistencyNoticeData? consistencyNotice;

  @override
  Widget build(BuildContext context) {
    final visual = AppVisualTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final confidence = result.confidence?.overall;
    final needsReview = result.reviewDecision.requiresConfirmation;
    final confidenceLabel = needsReview
        ? '采用前需确认'
        : confidence == null
            ? '可信度未标注'
            : '可信度 ${(confidence * 100).round()}%';

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: AppSpace.sm + 2,
            ),
            decoration: BoxDecoration(
              gradient: visual.heroGradient,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(visual.cardRadius - 1),
              ),
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  CupertinoIcons.bolt_fill,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: AppSpace.sm),
                const Expanded(
                  child: Text(
                    '10 秒结论',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    confidenceLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(
              children: <Widget>[
                if (consistencyNotice != null) ...<Widget>[
                  ConsistencyNotice(notice: consistencyNotice!),
                  const SizedBox(height: AppSpace.md),
                ],
                _SummaryLine(
                  icon: CupertinoIcons.scope,
                  label: '错在哪里',
                  content: result.mistakeReason,
                  color: scheme.error,
                ),
                const SizedBox(height: AppSpace.md),
                _SummaryLine(
                  icon: CupertinoIcons.checkmark_circle_fill,
                  label: result.visualAssumptionStatus ==
                          VisualAssumptionStatus.needsReview
                      ? '可能答案'
                      : '正确答案',
                  content: result.finalAnswer,
                  color: scheme.primary,
                ),
                const SizedBox(height: AppSpace.md),
                _SummaryLine(
                  icon: CupertinoIcons.arrow_right_circle_fill,
                  label: '下一步',
                  content: result.studyAdvice,
                  color: scheme.tertiary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.icon,
    required this.label,
    required this.content,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String content;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                MathContentView(
                  content,
                  mode: MathContentViewMode.compact,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

String _masteryLabel(MasteryLevel level) {
  switch (level) {
    case MasteryLevel.newQuestion:
      return '未复习';
    case MasteryLevel.reviewing:
      return '复习中';
    case MasteryLevel.mastered:
      return '已掌握';
  }
}

Color _masteryColor(MasteryLevel level) {
  switch (level) {
    case MasteryLevel.newQuestion:
      return AppColors.slate;
    case MasteryLevel.reviewing:
      return AppColors.warning;
    case MasteryLevel.mastered:
      return AppColors.success;
  }
}

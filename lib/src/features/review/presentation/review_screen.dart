import 'dart:async';
import 'dart:math' show Random;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/core/constants/app_strings.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/domain/services/review_schedule_service.dart';
import 'package:smart_wrong_notebook/src/features/review/presentation/review_controller.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_layout.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_motion.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_typography.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/cached_question_image.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';

/// Phase 7-1：复习模式——顺序 / 随机 / 专项。
enum ReviewMode { sequential, random, focused }

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  /// 本次会话的复习统计：忘记 / 模糊 / 掌握 三类计数。
  final Map<ReviewRating, int> _sessionStats = <ReviewRating, int>{
    ReviewRating.forgot: 0,
    ReviewRating.hard: 0,
    ReviewRating.easy: 0,
  };

  /// 进入复习页时待复习题数，用于判断是否全部完成。
  int _initialPending = 0;
  bool _summaryShown = false;

  /// 连续复习模式：评价完成后自动滚动到下一题。
  bool _continuousMode = false;

  /// Phase 7-1：复习模式（顺序 / 随机 / 专项）。
  ReviewMode _mode = ReviewMode.sequential;

  /// Phase 7-1：专项模式选中的知识点 ID（来自薄弱点 TOP 卡片）。
  String? _focusedKpId;

  /// Phase 7-1：随机模式种子，进入随机模式时设置一次，避免每次 build 重新打乱。
  int _randomSeed = 0;

  /// 待复习列表的滚动控制器，用于支持「下一题」自动滚动。
  final ScrollController _pendingScrollController = ScrollController();

  /// 整体进度卡片是否可见：向下滚动浏览题目时自动收起，回到顶部时再现。
  bool _summaryVisible = true;

  @override
  void initState() {
    super.initState();
    _pendingScrollController.addListener(_onPendingScroll);
  }

  void _onPendingScroll() {
    // 滚动超过一屏高度的一半即认为进入「浏览题目」状态，收起进度卡片。
    final shouldShow = _pendingScrollController.offset <= 240;
    if (shouldShow != _summaryVisible && mounted) {
      setState(() => _summaryVisible = shouldShow);
    }
  }

  @override
  void dispose() {
    _pendingScrollController.removeListener(_onPendingScroll);
    _pendingScrollController.dispose();
    super.dispose();
  }

  void _onRated(ReviewRating rating) {
    setState(() => _sessionStats[rating] = (_sessionStats[rating] ?? 0) + 1);
    // 总结弹窗的检查在 build 中数据可用时进行，避免在 provider 加载期间误判。
  }

  /// 滚动到下一题。预估单题卡片高度约 380px，确保下一张卡片可见。
  void _scrollToNextPending() {
    final controller = _pendingScrollController;
    if (!controller.hasClients) return;
    final target = controller.offset + 380;
    final max = controller.position.maxScrollExtent;
    controller.animateTo(
      target > max ? max : target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// Phase 7-1：切换复习模式。
  /// 进入随机模式时如果种子未设置，则初始化为当前时间戳，确保本次会话内顺序稳定。
  void _changeMode(ReviewMode next) {
    setState(() {
      _mode = next;
      if (next == ReviewMode.random && _randomSeed == 0) {
        _randomSeed = DateTime.now().millisecondsSinceEpoch;
      }
      // 离开专项模式时清空选中知识点，回到全量待复习。
      if (next != ReviewMode.focused) {
        _focusedKpId = null;
      }
    });
  }

  /// Phase 7-1：开始某个薄弱知识点的专项复习。
  void _startFocused(String kpId) {
    setState(() {
      _focusedKpId = kpId;
      _mode = ReviewMode.focused;
    });
  }

  /// Phase 7-1：根据当前模式对待复习列表进行重排或过滤。
  List<QuestionRecord> _applyReviewMode(
    List<QuestionRecord> pending,
    Set<String>? focusedQuestionIds,
  ) {
    switch (_mode) {
      case ReviewMode.sequential:
        if (pending.length <= 1) return List<QuestionRecord>.of(pending);
        final sorted = List<QuestionRecord>.of(pending)
          ..sort((a, b) {
            final an = a.nextReviewAt;
            final bn = b.nextReviewAt;
            if (an == null && bn == null) return 0;
            if (an == null) return 1;
            if (bn == null) return -1;
            return an.compareTo(bn);
          });
        return sorted;
      case ReviewMode.random:
        final shuffled = List<QuestionRecord>.of(pending)
          ..shuffle(Random(_randomSeed));
        return shuffled;
      case ReviewMode.focused:
        if (focusedQuestionIds == null || focusedQuestionIds.isEmpty) {
          return const <QuestionRecord>[];
        }
        return pending
            .where((q) => focusedQuestionIds.contains(q.id))
            .toList();
    }
  }

  void _showSummaryDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(children: <Widget>[
          Icon(CupertinoIcons.checkmark_seal_fill, color: AppColors.success),
          SizedBox(width: AppSpace.sm),
          Text('本次复习完成'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '本次共复习 ${_sessionStats.values.fold<int>(0, (a, b) => a + b)} 题：',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpace.sm),
            _SummaryRow(
              label: '忘记',
              count: _sessionStats[ReviewRating.forgot] ?? 0,
              color: AppColors.danger,
            ),
            _SummaryRow(
              label: '模糊',
              count: _sessionStats[ReviewRating.hard] ?? 0,
              color: AppColors.warning,
            ),
            _SummaryRow(
              label: '掌握',
              count: _sessionStats[ReviewRating.easy] ?? 0,
              color: AppColors.success,
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              (_sessionStats[ReviewRating.forgot] ?? 0) > 0
                  ? '忘记的题目将在近期再次出现，建议加强巩固。'
                  : '本次复习表现不错，继续保持节奏！',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后再说'),
          ),
          FilledButton.tonal(
            onPressed: () {
              Navigator.pop(ctx);
              // 关闭弹窗后用户可继续查看已排程题目，本轮统计保留。
            },
            child: const Text('继续下一组'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/notebook');
            },
            child: const Text('返回错题本'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final questionsAsync = ref.watch(questionListProvider);
    final reviewLogsAsync = ref.watch(reviewLogListProvider);
    final batchGroups = ref.watch(questionBatchGroupsProvider).valueOrNull;
    // Phase 7-3：连续复习天数来自 todayReviewPlanProvider（已实现 streakDays）。
    final planAsync = ref.watch(todayReviewPlanProvider);
    // Phase 7-1：薄弱点 TOP 列表，用于专项复习入口卡。
    final weakPointsAsync = ref.watch(weakPointRecommendationsProvider);

    return questionsAsync.when(
      data: (questions) {
        const scheduler = ReviewScheduleService();
        final pending = questions.where(scheduler.isDue).toList();
        final scheduled = questions.where((q) => !scheduler.isDue(q)).toList();
        final logs = reviewLogsAsync.valueOrNull ?? const <ReviewLog>[];
        final reviewedToday = _reviewedToday(logs);
        final todayTarget = pending.length + reviewedToday;

        // Phase 7-3：复习统计——近 7 天复习题数 / 掌握率 / 连续复习天数。
        final last7DaysReviews = _reviewedLast7Days(logs);
        final masteredCount = questions
            .where((q) => q.masteryLevel == MasteryLevel.mastered)
            .length;
        final masteryRate = questions.isEmpty
            ? 0
            : (masteredCount / questions.length * 100).round();
        final streakDays = planAsync.valueOrNull?.streakDays ?? 0;

        // Phase 7-1：解析薄弱点 TOP5 + 当前专项模式下选中的题目集合。
        final weakPoints = weakPointsAsync.valueOrNull ?? const <WeakPointRecommendation>[];
        final topWeakPoints = weakPoints.take(5).toList();
        Set<String>? focusedQuestionIds;
        String? focusedKpName;
        if (_mode == ReviewMode.focused && _focusedKpId != null) {
          WeakPointRecommendation? match;
          for (final w in weakPoints) {
            if (w.recommendation.knowledgePointId == _focusedKpId) {
              match = w;
              break;
            }
          }
          if (match != null) {
            focusedQuestionIds = match.recommendation.relatedQuestionIds.toSet();
            focusedKpName = match.knowledgePointName;
          } else {
            // 薄弱点列表已变更（如评分后该 KP 不再薄弱），退出专项模式。
            focusedQuestionIds = const <String>{};
            focusedKpName = _focusedKpId;
          }
        }
        final displayPending = _applyReviewMode(pending, focusedQuestionIds);

        // 首次拿到待复习列表时记录初始数量，用于判断本次会话是否全部完成。
        if (_initialPending == 0 && pending.isNotEmpty) {
          _initialPending = pending.length;
        }

        // 数据可用时检查是否应展示本次复习总结：本次至少评价过一题，且当前已无待复习。
        final reviewed = _sessionStats.values.fold<int>(0, (a, b) => a + b);
        if (!_summaryShown && _initialPending > 0 && reviewed > 0 && pending.isEmpty) {
          _summaryShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _showSummaryDialog());
        }

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text(AppStrings.reviewTitle),
              actions: <Widget>[
                IconButton(
                  icon: Icon(_continuousMode
                      ? CupertinoIcons.repeat_1
                      : CupertinoIcons.repeat),
                  tooltip: _continuousMode ? '关闭连续复习' : '开启连续复习',
                  color: _continuousMode
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  onPressed: () => setState(() => _continuousMode = !_continuousMode),
                ),
                IconButton(
                  icon: const Icon(CupertinoIcons.clock),
                  tooltip: AppStrings.reviewHistory,
                  onPressed: () => context.go('/review/history'),
                ),
              ],
              bottom: TabBar(
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                labelColor: Theme.of(context).colorScheme.onPrimary,
                unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                tabs: <Widget>[
                  Tab(text: '${AppStrings.reviewPending} ${pending.length}'),
                  Tab(text: '${AppStrings.reviewScheduled} ${scheduled.length}'),
                ],
              ),
            ),
            body: AppPage(
              maxWidth: AppContentWidth.wide,
              padding: EdgeInsets.zero,
              child: Column(
              children: <Widget>[
                AnimatedSwitcher(
                  duration: AppMotion.isTest ? Duration.zero : AppMotion.resolve(context, AppMotion.fast),
                  switchInCurve: AppMotion.standard,
                  switchOutCurve: AppMotion.standard,
                  transitionBuilder: (child, animation) => SizeTransition(
                    sizeFactor: animation,
                    axisAlignment: -1,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: _summaryVisible
                      ? Padding(
                          key: const ValueKey('summary'),
                          padding: const EdgeInsets.fromLTRB(
                              AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.sm),
                          child: _SummaryCard(
                            total: questions.length,
                            pending: pending.length,
                            scheduled: scheduled.length,
                            reviewedToday: reviewedToday,
                            todayTarget: todayTarget,
                            last7DaysReviews: last7DaysReviews,
                            masteryRate: masteryRate,
                            streakDays: streakDays,
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('summary-hidden')),
                ),
                // Phase 7-1：复习模式选择 + 薄弱点专项入口。
                _ReviewModeBar(
                  mode: _mode,
                  focusedKpName: focusedKpName,
                  onModeChanged: _changeMode,
                  onExitFocused: () => _changeMode(ReviewMode.sequential),
                ),
                if (_mode != ReviewMode.focused && topWeakPoints.isNotEmpty)
                  _WeakPointEntries(
                    weakPoints: topWeakPoints,
                    pending: pending,
                    onSelect: _startFocused,
                  ),
                Expanded(
                  child: TabBarView(
                    children: <Widget>[
                      _ReviewQuestionList(
                        questions: displayPending,
                        emptyMessage: _mode == ReviewMode.focused
                            ? '该知识点暂无待复习题目，可切换到其他模式或选择另一知识点。'
                            : AppStrings.reviewEmptyPending,
                        batchGroups: batchGroups,
                        ref: ref,
                        onRated: _onRated,
                        scrollController: _pendingScrollController,
                        onNext: _scrollToNextPending,
                        autoAdvance: _continuousMode,
                      ),
                      _ReviewQuestionList(
                        questions: scheduled,
                        emptyMessage: AppStrings.reviewEmptyScheduled,
                        batchGroups: batchGroups,
                        ref: ref,
                        onRated: null,
                      ),
                    ],
                  ),
                ),
              ],
              ),
            ),
          ),
        );
      },
      loading: () => const Scaffold(
        body: AppLoadingState(label: '正在整理复习计划…'),
      ),
      error: (_, __) => Scaffold(
        body: AppErrorState(
          message: '复习计划暂时无法读取。',
          onRetry: () => ref.invalidate(questionListProvider),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.count, required this.color});
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpace.sm),
          Text(label, style: const TextStyle(fontSize: 13)),
          const Spacer(),
          Text('$count 题', style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

int _reviewedToday(List<ReviewLog> logs, {DateTime? now}) {
  final day = now ?? DateTime.now();
  final ids = <String>{};
  for (final log in logs) {
    final at = log.reviewedAt.toLocal();
    if (at.year == day.year && at.month == day.month && at.day == day.day) {
      ids.add(log.questionRecordId);
    }
  }
  return ids.length;
}

/// Phase 7-3：近 7 天（含今天）复习过的不同题目数，用于复习统计卡。
int _reviewedLast7Days(List<ReviewLog> logs, {DateTime? now}) {
  final day = now ?? DateTime.now();
  final today = DateTime(day.year, day.month, day.day);
  final weekAgo = today.subtract(const Duration(days: 6)); // 含今天共 7 天
  final ids = <String>{};
  for (final log in logs) {
    final at = log.reviewedAt.toLocal();
    final logDay = DateTime(at.year, at.month, at.day);
    if (!logDay.isBefore(weekAgo) && !logDay.isAfter(today)) {
      ids.add(log.questionRecordId);
    }
  }
  return ids.length;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.total,
    required this.pending,
    required this.scheduled,
    required this.reviewedToday,
    required this.todayTarget,
    required this.last7DaysReviews,
    required this.masteryRate,
    required this.streakDays,
  });

  final int total;
  final int pending;
  final int scheduled;
  final int reviewedToday;
  final int todayTarget;

  /// Phase 7-3：近 7 天复习过的不同题目数。
  final int last7DaysReviews;

  /// Phase 7-3：整体掌握率（0-100）。
  final int masteryRate;

  /// Phase 7-3：连续复习天数（来自 todayReviewPlanProvider.streakDays）。
  final int streakDays;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final masteryColor = masteryRate >= 60
        ? AppColors.success
        : masteryRate >= 30
            ? AppColors.warning
            : AppColors.danger;

    return AppCard(
      borderRadius: AppRadius.large,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                AppStrings.reviewOverallProgress,
                style: AppTextStyle.apply(AppTextStyle.subtitle).copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '共 $total 题',
                style: AppTextStyle.apply(AppTextStyle.caption).copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          // 压缩为一行 4 个核心指标：待复习 / 近7天 / 掌握率 / 连续天。
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _MiniStat(
                  value: '$pending',
                  label: AppStrings.reviewPending,
                  color: AppColors.warning,
                  icon: CupertinoIcons.alarm),
              _MiniStat(
                  value: '$last7DaysReviews',
                  label: '近7天',
                  color: colorScheme.primary,
                  icon: CupertinoIcons.calendar),
              _MiniStat(
                value: '$masteryRate%',
                label: '掌握率',
                color: masteryColor,
                icon: CupertinoIcons.chart_bar,
              ),
              _MiniStat(
                value: '$streakDays',
                label: '连续天',
                color: AppColors.accentAmber,
                icon: CupertinoIcons.flame,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            todayTarget == 0
                ? '今日暂无复习计划'
                : '$reviewedToday / $todayTarget ${AppStrings.reviewTodayProgress}',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: todayTarget == 0 ? 0 : reviewedToday / todayTarget,
            minHeight: 6,
          ),
        ],
      ),
    );
  }
}

/// Phase 7-1：复习模式选择条 + 专项模式提示。
class _ReviewModeBar extends StatelessWidget {
  const _ReviewModeBar({
    required this.mode,
    required this.focusedKpName,
    required this.onModeChanged,
    required this.onExitFocused,
  });

  final ReviewMode mode;
  final String? focusedKpName;
  final ValueChanged<ReviewMode> onModeChanged;
  final VoidCallback onExitFocused;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SegmentedButton<ReviewMode>(
            segments: const <ButtonSegment<ReviewMode>>[
              ButtonSegment<ReviewMode>(
                  value: ReviewMode.sequential,
                  icon: Icon(CupertinoIcons.sort_down, size: 16),
                  label: Text('顺序')),
              ButtonSegment<ReviewMode>(
                  value: ReviewMode.random,
                  icon: Icon(CupertinoIcons.shuffle, size: 16),
                  label: Text('随机')),
              ButtonSegment<ReviewMode>(
                  value: ReviewMode.focused,
                  icon: Icon(CupertinoIcons.scope, size: 16),
                  label: Text('专项')),
            ],
            selected: <ReviewMode>{mode},
            onSelectionChanged: (Set<ReviewMode> selection) =>
                onModeChanged(selection.first),
          ),
          if (mode == ReviewMode.focused) ...<Widget>[
            const SizedBox(height: AppSpace.xs),
            Row(
              children: <Widget>[
                Icon(CupertinoIcons.scope, size: 14, color: colorScheme.primary),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Text(
                    focusedKpName == null
                        ? '正在专项复习'
                        : '正在专项复习：$focusedKpName',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onExitFocused,
                  icon: const Icon(CupertinoIcons.xmark, size: 14),
                  label: const Text('退出专项', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Phase 7-1：薄弱点专项复习入口卡（横向滚动，TOP5）。
class _WeakPointEntries extends StatelessWidget {
  const _WeakPointEntries({
    required this.weakPoints,
    required this.pending,
    required this.onSelect,
  });

  final List<WeakPointRecommendation> weakPoints;
  final List<QuestionRecord> pending;
  final ValueChanged<String> onSelect;

  /// 计算该薄弱知识点下当前待复习的题目数（精确反映「现在开始专项」会看到的题数）。
  int _dueCountFor(WeakPointRecommendation weak) {
    final ids = weak.recommendation.relatedQuestionIds.toSet();
    if (ids.isEmpty) return weak.pendingReviewCount;
    return pending.where((q) => ids.contains(q.id)).length;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        itemCount: weakPoints.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpace.sm),
        itemBuilder: (context, index) {
          final w = weakPoints[index];
          final dueCount = _dueCountFor(w);
          final masteryPct = w.mastery?.masteryPercentage.round() ?? 0;
          final masteryColor = masteryPct >= 60
              ? AppColors.success
              : masteryPct >= 30
                  ? AppColors.warning
                  : AppColors.danger;
          return _WeakPointEntryCard(
            name: w.knowledgePointName,
            dueCount: dueCount,
            masteryPct: masteryPct,
            masteryColor: masteryColor,
            isDark: isDark,
            colorScheme: colorScheme,
            onTap: dueCount > 0
                ? () => onSelect(w.recommendation.knowledgePointId)
                : null,
          );
        },
      ),
    );
  }
}

class _WeakPointEntryCard extends StatelessWidget {
  const _WeakPointEntryCard({
    required this.name,
    required this.dueCount,
    required this.masteryPct,
    required this.masteryColor,
    required this.isDark,
    required this.colorScheme,
    required this.onTap,
  });

  final String name;
  final int dueCount;
  final int masteryPct;
  final Color masteryColor;
  final bool isDark;
  final ColorScheme colorScheme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final bg = disabled
        ? (isDark ? colorScheme.surfaceContainerHighest : AppColors.slateContainerLight)
        : (isDark
            ? masteryColor.withValues(alpha: 0.14)
            : masteryColor.withValues(alpha: 0.08));
    final border = disabled
        ? colorScheme.outlineVariant.withValues(alpha: 0.5)
        : masteryColor.withValues(alpha: 0.45);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Container(
          width: 180,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md, vertical: AppSpace.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            border: Border.all(color: border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: disabled
                            ? colorScheme.onSurfaceVariant
                            : colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: masteryColor.withValues(alpha: isDark ? 0.18 : 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$masteryPct%',
                      style: TextStyle(
                        fontSize: 12,
                        color: masteryColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                disabled ? '暂无待复习' : '待复习 $dueCount 题',
                style: TextStyle(
                  fontSize: 12,
                  color: disabled ? colorScheme.onSurfaceVariant : masteryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: <Widget>[
                  Icon(
                    disabled
                        ? CupertinoIcons.lock
                        : CupertinoIcons.play_circle_fill,
                    size: 12,
                    color: disabled ? colorScheme.onSurfaceVariant : masteryColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    disabled ? '稍后再练' : '开始专项',
                    style: TextStyle(
                      fontSize: 12,
                      color: disabled ? colorScheme.onSurfaceVariant : masteryColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.value,
    required this.label,
    required this.color,
    this.icon = CupertinoIcons.circle,
  });

  final String value;
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 4),
        Text(value,
            style: AppTextStyle.apply(AppTextStyle.subtitle).copyWith(
              color: color,
            )),
        const SizedBox(height: 2),
        Text(label,
            style: AppTextStyle.apply(AppTextStyle.caption).copyWith(
              color: color,
            )),
      ],
    );
  }
}

class _ReviewQuestionList extends StatelessWidget {
  const _ReviewQuestionList({
    required this.questions,
    required this.emptyMessage,
    required this.batchGroups,
    required this.ref,
    this.onRated,
    this.scrollController,
    this.onNext,
    this.autoAdvance = false,
  });

  final List<QuestionRecord> questions;
  final String emptyMessage;
  final Map<String, QuestionBatchGroup>? batchGroups;
  final WidgetRef ref;
  final ValueChanged<ReviewRating>? onRated;
  final ScrollController? scrollController;
  final VoidCallback? onNext;
  final bool autoAdvance;

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        child: AppEmptyState(
          icon: CupertinoIcons.star,
          title: '太棒了！',
          description: emptyMessage,
        ),
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.lg),
      itemCount: questions.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm),
      itemBuilder: (context, index) => _ReviewCard(
        question: questions[index],
        batchLabel: _batchLabel(questions[index], batchGroups),
        onOpen: () {
          ref.read(currentQuestionProvider.notifier).state = questions[index];
          context.go('/notebook/question/${questions[index].id}');
        },
        onRated: onRated,
        onNext: onNext,
        autoAdvance: autoAdvance,
        delay: AppMotion.staggerStep * index,
      ),
    );
  }
}

String? _batchLabel(
    QuestionRecord question, Map<String, QuestionBatchGroup>? batchGroups) {
  final rootId = questionBatchRootId(question);
  if (rootId == null) return null;

  final group = batchGroups?[rootId];
  if (group == null || group.questions.length < 2) return null;

  final order = question.splitOrder;
  return order == null ? '来自同一拍照批次' : '来自同一拍照批次 · 第 $order 题';
}

String _masteryLabel(MasteryLevel level) {
  switch (level) {
    case MasteryLevel.newQuestion:
      return '待复习';
    case MasteryLevel.reviewing:
      return '待复习';
    case MasteryLevel.mastered:
      return '已掌握';
  }
}

Color _masteryColor(BuildContext context, MasteryLevel level) {
  final colorScheme = Theme.of(context).colorScheme;
  switch (level) {
    case MasteryLevel.newQuestion:
      return colorScheme.onSurfaceVariant;
    case MasteryLevel.reviewing:
      return AppColors.warning;
    case MasteryLevel.mastered:
      return AppColors.success;
  }
}

class _MasteryChip extends StatelessWidget {
  const _MasteryChip({required this.level});

  final MasteryLevel level;

  @override
  Widget build(BuildContext context) {
    final color = _masteryColor(context, level);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _masteryLabel(level),
        style: TextStyle(fontSize: 12, color: color),
      ),
    );
  }
}

String _nextReviewLabel(DateTime date) {
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '下次复习 $month-$day $hour:$minute';
}

class _ReviewCard extends ConsumerStatefulWidget {
  const _ReviewCard({
    required this.question,
    required this.onOpen,
    this.batchLabel,
    this.onRated,
    this.onNext,
    this.autoAdvance = false,
    this.delay = Duration.zero,
  });

  final QuestionRecord question;
  final VoidCallback onOpen;
  final String? batchLabel;
  final ValueChanged<ReviewRating>? onRated;
  final VoidCallback? onNext;
  final bool autoAdvance;
  final Duration delay;

  @override
  ConsumerState<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends ConsumerState<_ReviewCard> {
  bool _revealed = false;
  bool _rating = false;
  bool _rated = false;
  Timer? _autoAdvanceTimer;

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    super.dispose();
  }

  Future<void> _rate(ReviewRating rating) async {
    if (_rating || _rated) return;
    setState(() => _rating = true);
    final controller = ReviewController(
      repository: ref.read(questionRepositoryProvider),
      logRepository: ref.read(reviewLogRepositoryProvider),
    );
    try {
      final updated = switch (rating) {
        ReviewRating.forgot => await controller.markForgot(widget.question.id),
        ReviewRating.hard => await controller.markReviewing(widget.question.id),
        ReviewRating.easy => await controller.markMastered(widget.question.id),
      };
      invalidateQuestionList(ref);
      // Phase 7-4：显式刷新薄弱点推荐与知识树快照，确保评分后首页薄弱
      // 卡片、知识树页面即时更新。weakPointRecommendationsProvider 内部
      // 会调用 KnowledgePointMasteryService.calculateBatch 重算相关知识点
      // 掌握度，从而闭合「复习 → 掌握度更新 → 推荐刷新」回路。
      ref.invalidate(weakPointRecommendationsProvider);
      ref.invalidate(knowledgeTreeOverviewProvider);
      widget.onRated?.call(rating);
      if (mounted) {
        setState(() {
          _rating = false;
          _rated = true;
        });
        _showRatingFeedback(rating, updated);
        // 连续复习模式：评价完成后短暂延迟再自动滚动到下一题，
        // 让用户先看到反馈卡片和 SnackBar。
        if (widget.autoAdvance && widget.onNext != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _autoAdvanceTimer?.cancel();
            if (AppMotion.isTest) return;
            _autoAdvanceTimer = Timer(const Duration(milliseconds: 600), () {
              if (mounted) widget.onNext?.call();
            });
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _rating = false);
        _showRatingError(e);
      }
    }
  }

  void _showRatingFeedback(ReviewRating rating, QuestionRecord updated) {
    final ratingLabel = switch (rating) {
      ReviewRating.forgot => '忘记',
      ReviewRating.hard => '模糊',
      ReviewRating.easy => '掌握',
    };
    final masteryLabel = _masteryLabel(updated.masteryLevel);
    final nextLabel = updated.nextReviewAt != null
        ? _nextReviewLabel(updated.nextReviewAt!)
        : '已掌握，暂无下次复习';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已记录「$ratingLabel」· $masteryLabel\n$nextLabel'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '下一题',
          onPressed: () {
            // SnackBar 自身消失即可，列表已刷新，下一题自然显示在原位置。
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  void _showRatingError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('复习记录保存失败，请重试'),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '重试',
          onPressed: () {
            // 不在此处自动重试特定 rating，引导用户再次点击按钮。
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.question.analysisResult;
    final answer = (widget.question.expectedAnswer?.trim().isNotEmpty ?? false)
        ? widget.question.expectedAnswer!.trim()
        : result?.finalAnswer.trim() ?? '';
    final hasAnswer = answer.isNotEmpty;

    if (_rated) {
      return _RatedCard(
        question: widget.question,
        onOpen: widget.onOpen,
        onNext: widget.onNext,
      );
    }

    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ReviewCardContent(
          question: widget.question,
          onOpen: widget.onOpen,
          batchLabel: widget.batchLabel,
        ),
        if (!hasAnswer) ...<Widget>[
          const SizedBox(height: AppSpace.xs),
          Text(
            '本题未保存参考答案，可直接评价或打开详情查看',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (_revealed && hasAnswer) ...<Widget>[
          const SizedBox(height: AppSpace.xs),
          AppInfoSection(
            icon: CupertinoIcons.checkmark_circle,
            title: '参考答案',
            iconColor: AppColors.successDark,
            backgroundColor: AppColors.successContainerLight,
            borderColor: AppColors.success.withValues(alpha: 0.3),
            titleColor: AppColors.successDark,
            child: MathContentView(answer, contentFormat: widget.question.contentFormat),
          ),
        ],
        const SizedBox(height: AppSpace.xs),
        Row(
          children: <Widget>[
            // 「查看答案」紧凑按钮（与评分按钮同行）
            _CompactRevealButton(
              hasAnswer: hasAnswer,
              revealed: _revealed,
              onTap: hasAnswer
                  ? () => setState(() => _revealed = !_revealed)
                  : widget.onOpen,
            ),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: _RateButton(
                rating: ReviewRating.forgot,
                loading: _rating,
                onTap: () => _rate(ReviewRating.forgot),
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: _RateButton(
                rating: ReviewRating.hard,
                loading: _rating,
                onTap: () => _rate(ReviewRating.hard),
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: _RateButton(
                rating: ReviewRating.easy,
                loading: _rating,
                onTap: () => _rate(ReviewRating.easy),
              ),
            ),
          ],
        ),
      ],
    );
    return AppMotion.isTest
        ? card
        : Animate(
            effects: <Effect>[
              FadeEffect(duration: AppMotion.fast, curve: AppMotion.standard, delay: widget.delay),
              SlideEffect(begin: const Offset(0, 0.04), end: Offset.zero, duration: AppMotion.fast, curve: AppMotion.standard, delay: widget.delay),
            ],
            child: card,
          );
  }
}

/// 复习评分按钮：按「忘记 / 模糊 / 掌握」三档赋予语义色与图标，
/// 让每题的回忆结果选择更有辨识度与反馈感。
class _RateButton extends StatelessWidget {
  const _RateButton({
    required this.rating,
    this.loading = false,
    required this.onTap,
  });

  final ReviewRating rating;
  final bool loading;
  final VoidCallback onTap;

  static const Map<ReviewRating, (Color, IconData, String)> _meta =
      <ReviewRating, (Color, IconData, String)>{
    ReviewRating.forgot: (AppColors.danger, CupertinoIcons.xmark_circle_fill, '忘记'),
    ReviewRating.hard: (AppColors.warning, CupertinoIcons.exclamationmark_circle_fill, '模糊'),
    ReviewRating.easy: (AppColors.success, CupertinoIcons.checkmark_circle_fill, '掌握'),
  };

  @override
  Widget build(BuildContext context) {
    final meta = _meta[rating]!;
    final color = meta.$1;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disabled = loading;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: AppMotion.micro,
          curve: AppMotion.standard,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: disabled
                ? (isDark ? AppColors.slateContainerDark : AppColors.slateContainerLight)
                : color.withValues(alpha: isDark ? 0.18 : 0.1),
            border: Border.all(
              color: disabled
                  ? Colors.transparent
                  : color.withValues(alpha: isDark ? 0.4 : 0.32),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: loading
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(meta.$2, size: 15, color: color),
                      const SizedBox(width: 4),
                      Text(
                        meta.$3,
                        style: AppTextStyle.apply(AppTextStyle.caption).copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// 紧凑型「查看答案」按钮，用于与评分按钮合并在同一行。
class _CompactRevealButton extends StatelessWidget {
  const _CompactRevealButton({
    required this.hasAnswer,
    required this.revealed,
    required this.onTap,
  });

  final bool hasAnswer;
  final bool revealed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final icon = hasAnswer
        ? (revealed ? CupertinoIcons.eye_slash : CupertinoIcons.eye)
        : CupertinoIcons.doc_text_search;
    final label = hasAnswer ? (revealed ? '收起' : '查看') : '详情';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.slateContainerDark : AppColors.slateContainerLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.5),
          ),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 15, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 3),
              Text(
                label,
                style: AppTextStyle.apply(AppTextStyle.caption).copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 评价完成后展示的简短卡片，提示已记录并提供「打开详情」入口。
class _RatedCard extends StatelessWidget {
  const _RatedCard({required this.question, required this.onOpen, this.onNext});

  final QuestionRecord question;
  final VoidCallback onOpen;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppCard(
      backgroundColor: AppColors.success.withValues(alpha: 0.08),
      borderColor: AppColors.success.withValues(alpha: 0.35),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      child: Row(
        children: <Widget>[
          Icon(CupertinoIcons.checkmark_circle_fill, size: 18, color: AppColors.success),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              question.nextReviewAt != null
                  ? '已记录 · ${_nextReviewLabel(question.nextReviewAt!)}'
                  : '已记录 · 已掌握',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
            ),
          ),
          TextButton(onPressed: onOpen, child: const Text('详情')),
          if (onNext != null) ...<Widget>[
            const SizedBox(width: AppSpace.xs),
            FilledButton.icon(
              onPressed: onNext,
              icon: const Icon(CupertinoIcons.arrow_down, size: 16),
              label: const Text('下一题'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewCardContent extends StatelessWidget {
  const _ReviewCardContent({
    required this.question,
    required this.onOpen,
    this.batchLabel,
  });

  final QuestionRecord question;
  final VoidCallback onOpen;
  final String? batchLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final hasImage = question.imagePath?.isNotEmpty ?? false;
    // 图片缩略图固定占位 64px，让文字始终占满剩余宽度
    const double thumbSize = 64;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.sm, AppSpace.md),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Stack(
          children: <Widget>[
            // 主体：文字内容（始终占满全宽，右边给图片缩略图预留 64px + 间距）
            Padding(
              padding: EdgeInsets.only(right: hasImage ? thumbSize + AppSpace.sm : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // 题目正文：使用 MathContentView 默认（full）模式正确渲染 LaTeX
                  MathContentView(
                    question.correctedText.isNotEmpty
                        ? question.correctedText
                        : '📷 查看图片题目',
                    contentFormat: question.contentFormat,
                    style: AppTextStyle.apply(AppTextStyle.body).copyWith(
                      fontWeight: FontWeight.w500,
                      color: question.correctedText.isNotEmpty
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  // 元信息行：batchLabel + nextReview 合并为一行
                  if (batchLabel != null || question.nextReviewAt != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        if (batchLabel != null) ...<Widget>[
                          Icon(CupertinoIcons.photo_on_rectangle,
                              size: 11, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              batchLabel!,
                              style: AppTextStyle.apply(AppTextStyle.overline).copyWith(
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        if (batchLabel != null && question.nextReviewAt != null)
                          const SizedBox(width: AppSpace.sm),
                        if (question.nextReviewAt != null) ...<Widget>[
                          Icon(CupertinoIcons.calendar,
                              size: 11, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              _nextReviewLabel(question.nextReviewAt!),
                              style: AppTextStyle.apply(AppTextStyle.overline).copyWith(
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                  // 标签行
                  const SizedBox(height: 4),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        Text(
                          question.subject.label,
                          style: AppTextStyle.apply(AppTextStyle.caption).copyWith(
                            color: question.subject.color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        _MasteryChip(level: question.masteryLevel),
                        const SizedBox(width: 4),
                        ...question.aiTags.map((tag) {
                          const tagColor = AppColors.accentAmber;
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: AppTag(
                              label: tag,
                              textColor: isDark ? colorScheme.onSurface : tagColor,
                              backgroundColor: isDark
                                  ? tagColor.withValues(alpha: 0.14)
                                  : AppColors.accentAmberContainerLight,
                              fontSize: 11,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 右上角：图片缩略图（固定 64×64，不影响主体布局）
            if (hasImage)
              Positioned(
                top: 0,
                right: AppSpace.xs,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  child: SizedBox(
                    width: thumbSize,
                    height: thumbSize,
                    child: CachedQuestionImage(
                      question.imagePath!,
                      fit: BoxFit.cover,
                      maxWidth: 200,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                  ),
                ),
              ),
            // 右下角：跳转箭头
            Positioned(
              bottom: 0,
              right: 0,
              child: Icon(CupertinoIcons.chevron_right,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                  size: 16),
            ),
          ],
        ),
      ),
    );
  }
}

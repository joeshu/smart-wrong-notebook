import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/app/theme/app_visual_style.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_type.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/core/constants/app_strings.dart';
import 'package:smart_wrong_notebook/src/features/capture/presentation/capture_entry_launcher.dart';
import 'package:smart_wrong_notebook/src/features/notebook/application/knowledge_point_practice_controller.dart';
import 'package:smart_wrong_notebook/src/shared/models/question_display_status.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_components.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_layout.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';

class NotebookScreen extends ConsumerStatefulWidget {
  const NotebookScreen({super.key});

  @override
  ConsumerState<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends ConsumerState<NotebookScreen> {
  final _searchController = TextEditingController();
  bool _buildingKnowledgePointPractice = false;
  bool _selectionMode = false;
  bool _showArchived = false;
  final Set<String> _selectedQuestionIds = <String>{};

  /// Phase 6-1：错题列表视图模式偏好（卡片 / 列表 / 时间线），持久化到
  /// SharedPreferences。initState 异步加载，加载完成前默认 [NotebookViewMode.card]。
  NotebookViewMode _viewMode = NotebookViewMode.card;
  static const _viewModePrefsKey = 'notebook:view_mode';

  @override
  void initState() {
    super.initState();
    _loadViewMode();
  }

  Future<void> _loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_viewModePrefsKey);
    if (stored == null) return;
    final parsed = NotebookViewMode.fromStorageName(stored);
    if (parsed == _viewMode) return;
    if (!mounted) return;
    setState(() => _viewMode = parsed);
  }

  Future<void> _setViewMode(NotebookViewMode mode) async {
    if (mode == _viewMode) return;
    setState(() => _viewMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_viewModePrefsKey, mode.storageName);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, dynamic question) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('删除后无法恢复，确定要删除这道错题吗？'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              await ref.read(questionRepositoryProvider).delete(question.id);
              invalidateQuestionList(ref);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  Future<void> _startKnowledgePointPractice(
    String knowledgePoint,
    List<QuestionRecord> questions,
  ) async {
    if (_buildingKnowledgePointPractice) return;
    setState(() => _buildingKnowledgePointPractice = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final controller = KnowledgePointPracticeController(
        ref.read(aiAnalysisServiceProvider),
      );
      final prepared = await controller.buildRound(
        knowledgePoint: knowledgePoint,
        questions: questions,
      );
      await ref.read(questionRepositoryProvider).update(prepared);
      invalidateQuestionList(ref);
      ref.read(currentPracticeContextProvider.notifier).state =
          const PracticeContext(
        source: PracticeContextSource.notebook,
        returnRoute: '/notebook',
      );
      ref.read(currentQuestionProvider.notifier).state = prepared;
      if (!mounted) return;
      context.go('/exercise/practice');
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('专项练习准备失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _buildingKnowledgePointPractice = false);
    }
  }

  void _applyMenuAction(WidgetRef ref, _NotebookMenuAction action) {
    switch (action) {
      case _NotebookMenuAction.dueOnly:
        final current = ref.read(dueOnlyFilterProvider);
        ref.read(dueOnlyFilterProvider.notifier).state = !current;
        break;
      case _NotebookMenuAction.favoritesOnly:
        final current = ref.read(favoritesOnlyFilterProvider);
        ref.read(favoritesOnlyFilterProvider.notifier).state = !current;
        break;
      case _NotebookMenuAction.failedOnly:
        final current = ref.read(failedOnlyFilterProvider);
        ref.read(failedOnlyFilterProvider.notifier).state = !current;
        break;
      case _NotebookMenuAction.allDates:
        ref.read(questionDateRangeProvider.notifier).state =
            QuestionDateRange.all;
        break;
      case _NotebookMenuAction.last7Days:
        ref.read(questionDateRangeProvider.notifier).state =
            QuestionDateRange.last7Days;
        break;
      case _NotebookMenuAction.last30Days:
        ref.read(questionDateRangeProvider.notifier).state =
            QuestionDateRange.last30Days;
        break;
      case _NotebookMenuAction.newest:
        ref.read(questionSortProvider.notifier).state = QuestionSort.newest;
        break;
      case _NotebookMenuAction.oldest:
        ref.read(questionSortProvider.notifier).state = QuestionSort.oldest;
        break;
      case _NotebookMenuAction.nextReview:
        ref.read(questionSortProvider.notifier).state = QuestionSort.nextReview;
        break;
    }
  }

  void _toggleSelection(String questionId) {
    setState(() {
      if (!_selectedQuestionIds.add(questionId)) {
        _selectedQuestionIds.remove(questionId);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedQuestionIds.clear();
    });
  }

  void _openWorksheet(BuildContext context, WidgetRef ref) {
    if (_selectedQuestionIds.isEmpty) return;
    ref.read(worksheetDraftQuestionIdsProvider.notifier).state =
        _selectedQuestionIds.toList();
    _exitSelectionMode();
    context.go('/worksheet');
  }

  /// 多选模式下"导出选中题"：把选中题目 ID 通过路由 query 传给导出工作台，
  /// 工作台首帧会自动用这些 ID 构造筛选条件。
  void _exportSelected(BuildContext context) {
    if (_selectedQuestionIds.isEmpty) return;
    final idsParam = _selectedQuestionIds.join(',');
    _exitSelectionMode();
    context.push('/settings/export-workbench?ids=$idsParam');
  }

  Future<void> _deleteSelected(BuildContext context, WidgetRef ref) async {
    if (_selectedQuestionIds.isEmpty) return;
    final count = _selectedQuestionIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除已选错题？'),
        content: Text('将永久删除 $count 道错题及其本地图片，无法恢复。'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton.tonal(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    final repository = ref.read(questionRepositoryProvider);
    for (final id in _selectedQuestionIds) {
      await repository.delete(id);
    }
    invalidateQuestionList(ref);
    if (mounted) _exitSelectionMode();
  }
  void _clearFilters(WidgetRef ref) {
    ref.read(selectedSubjectFilterProvider.notifier).state = null;
    ref.read(selectedMasteryFilterProvider.notifier).state = null;
    ref.read(unmasteredOnlyFilterProvider.notifier).state = false;
    ref.read(selectedMistakeCategoryFilterProvider.notifier).state = null;
    ref.read(selectedKnowledgePointFilterProvider.notifier).state = null;
    ref.read(selectedTagsFilterProvider.notifier).state = const <String>[];
    ref.read(dueOnlyFilterProvider.notifier).state = false;
    ref.read(favoritesOnlyFilterProvider.notifier).state = false;
    ref.read(failedOnlyFilterProvider.notifier).state = false;
    ref.read(pendingAiOnlyFilterProvider.notifier).state = false;
    ref.read(lowConfidenceOnlyFilterProvider.notifier).state = false;
    ref.read(questionDateRangeProvider.notifier).state = QuestionDateRange.all;
    ref.read(selectedSourceFilterProvider.notifier).state = null;
    ref.read(selectedLearningStageFilterProvider.notifier).state = null;
    ref.read(selectedDifficultyFilterProvider.notifier).state = null;
    ref.read(selectedAttemptStatusFilterProvider.notifier).state = null;
    ref.read(selectedQuestionTypeFilterProvider.notifier).state = null;
    ref.read(questionSortProvider.notifier).state = QuestionSort.newest;
  }

  /// Phase 6-1：根据当前视图模式切换列表渲染。
  Widget _buildQuestionList({
    required BuildContext context,
    required WidgetRef ref,
    required List<QuestionRecord> visibleQuestions,
    required bool hasPracticeAction,
    required String? selectedKnowledgePoint,
  }) {
    switch (_viewMode) {
      case NotebookViewMode.card:
        return _buildCardList(
          context: context,
          ref: ref,
          visibleQuestions: visibleQuestions,
          hasPracticeAction: hasPracticeAction,
          selectedKnowledgePoint: selectedKnowledgePoint,
        );
      case NotebookViewMode.list:
        return _buildCompactList(
          context: context,
          ref: ref,
          visibleQuestions: visibleQuestions,
          hasPracticeAction: hasPracticeAction,
          selectedKnowledgePoint: selectedKnowledgePoint,
        );
      case NotebookViewMode.timeline:
        return _buildTimelineView(
          context: context,
          ref: ref,
          visibleQuestions: visibleQuestions,
        );
    }
  }

  Widget _buildCardList({
    required BuildContext context,
    required WidgetRef ref,
    required List<QuestionRecord> visibleQuestions,
    required bool hasPracticeAction,
    required String? selectedKnowledgePoint,
  }) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg, vertical: AppSpace.sm),
      itemCount: visibleQuestions.length + (hasPracticeAction ? 1 : 0),
      itemBuilder: (context, index) {
        if (hasPracticeAction && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _KnowledgePointPracticeCard(
              knowledgePoint: selectedKnowledgePoint!,
              isLoading: _buildingKnowledgePointPractice,
              onStart: () => _startKnowledgePointPractice(
                selectedKnowledgePoint,
                visibleQuestions,
              ),
            ),
          );
        }
        final questionIndex = index - (hasPracticeAction ? 1 : 0);
        final q = visibleQuestions[questionIndex];
        return RepaintBoundary(
          child: _QuestionCard(
            question: q,
            selectionMode: _selectionMode,
            selected: _selectedQuestionIds.contains(q.id),
            onSelect: () => _toggleSelection(q.id),
            onTap: () {
              ref.read(currentQuestionProvider.notifier).state = q;
              context.go('/notebook/question/${q.id}');
            },
            onDelete: () => _confirmDelete(context, ref, q),
            onKnowledgePointTap: (kp) {
              ref
                  .read(
                      selectedKnowledgePointFilterProvider.notifier)
                  .state = kp;
            },
            primaryAction: _selectionMode
                ? null
                : _cardPrimaryAction(context, ref, q),
          ),
        );
      },
    );
  }

  Widget _buildCompactList({
    required BuildContext context,
    required WidgetRef ref,
    required List<QuestionRecord> visibleQuestions,
    required bool hasPracticeAction,
    required String? selectedKnowledgePoint,
  }) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg, vertical: AppSpace.sm),
      itemCount: visibleQuestions.length + (hasPracticeAction ? 1 : 0),
      itemBuilder: (context, index) {
        if (hasPracticeAction && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _KnowledgePointPracticeCard(
              knowledgePoint: selectedKnowledgePoint!,
              isLoading: _buildingKnowledgePointPractice,
              onStart: () => _startKnowledgePointPractice(
                selectedKnowledgePoint,
                visibleQuestions,
              ),
            ),
          );
        }
        final questionIndex = index - (hasPracticeAction ? 1 : 0);
        final q = visibleQuestions[questionIndex];
        return RepaintBoundary(
          child: _CompactQuestionRow(
            question: q,
            selectionMode: _selectionMode,
            selected: _selectedQuestionIds.contains(q.id),
            onSelect: () => _toggleSelection(q.id),
            onTap: () {
              ref.read(currentQuestionProvider.notifier).state = q;
              context.go('/notebook/question/${q.id}');
            },
            onDelete: () => _confirmDelete(context, ref, q),
          ),
        );
      },
    );
  }

  Widget _buildTimelineView({
    required BuildContext context,
    required WidgetRef ref,
    required List<QuestionRecord> visibleQuestions,
  }) {
    if (visibleQuestions.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(AppSpace.xl),
        children: <Widget>[
          Center(
            child: Column(
              children: <Widget>[
                Icon(CupertinoIcons.calendar,
                    size: 40,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: AppSpace.md),
                Text('该筛选下暂无错题',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
              ],
            ),
          ),
        ],
      );
    }
    // 按日期分组（使用 createdAt 的 y-m-d 作为 key），同日内按时间倒序。
    final groups = <String, List<QuestionRecord>>{};
    for (final q in visibleQuestions) {
      final local = q.createdAt.toLocal();
      final key =
          '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
      (groups[key] ??= <QuestionRecord>[]).add(q);
    }
    final sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    final itemCount = sortedKeys.length +
        sortedKeys.fold<int>(
            0, (acc, k) => acc + groups[k]!.length);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg, vertical: AppSpace.sm),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        var i = index;
        for (final key in sortedKeys) {
          if (i == 0) {
            return _TimelineDateHeader(
              dateKey: key,
              count: groups[key]!.length,
            );
          }
          i -= 1;
          final group = groups[key]!;
          if (i < group.length) {
            final q = group[i];
            return RepaintBoundary(
              child: _TimelineQuestionRow(
                question: q,
                selectionMode: _selectionMode,
                selected: _selectedQuestionIds.contains(q.id),
                onSelect: () => _toggleSelection(q.id),
                onTap: () {
                  ref.read(currentQuestionProvider.notifier).state = q;
                  context.go('/notebook/question/${q.id}');
                },
                onDelete: () => _confirmDelete(context, ref, q),
                isLastInGroup: i == group.length - 1,
              ),
            );
          }
          i -= group.length;
        }
        return const SizedBox.shrink();
      },
    );
  }

  _CardPrimaryAction? _cardPrimaryAction(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) {
    if (question.contentStatus == ContentStatus.failed ||
        question.contentStatus == ContentStatus.analysisFailed) {
      return _CardPrimaryAction(label: '重新分析', icon: CupertinoIcons.arrow_clockwise, onTap: () {
        ref.read(currentQuestionProvider.notifier).state = question;
        context.go('/notebook/question/${question.id}');
      });
    }
    if (question.analysisResult == null) {
      return _CardPrimaryAction(label: '继续校对', icon: CupertinoIcons.pencil, onTap: () {
        ref.read(currentQuestionProvider.notifier).state = question;
        context.go('/notebook/question/${question.id}');
      });
    }
    final due = question.nextReviewAt != null && !question.nextReviewAt!.isAfter(DateTime.now());
    if (due) return _CardPrimaryAction(label: '开始复习', icon: CupertinoIcons.play_fill, onTap: () => context.go('/review'));
    if (question.masteryLevel == MasteryLevel.newQuestion) {
      return _CardPrimaryAction(label: '开始练习', icon: CupertinoIcons.pencil_ellipsis_rectangle, onTap: () {
        ref.read(currentQuestionProvider.notifier).state = question;
        context.go('/notebook/question/${question.id}');
      });
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final questionsAsync = ref.watch(filteredQuestionListProvider);
    final selectedSubject = ref.watch(selectedSubjectFilterProvider);
    final selectedMastery = ref.watch(selectedMasteryFilterProvider);
    final unmasteredOnly = ref.watch(unmasteredOnlyFilterProvider);
    final selectedMistakeCategory =
        ref.watch(selectedMistakeCategoryFilterProvider);
    final selectedTags = ref.watch(selectedTagsFilterProvider);
    final dueOnly = ref.watch(dueOnlyFilterProvider);
    final favoritesOnly = ref.watch(favoritesOnlyFilterProvider);
    final failedOnly = ref.watch(failedOnlyFilterProvider);
    final pendingAiOnly = ref.watch(pendingAiOnlyFilterProvider);
    final lowConfidenceOnly = ref.watch(lowConfidenceOnlyFilterProvider);
    final dateRange = ref.watch(questionDateRangeProvider);
    final selectedSource = ref.watch(selectedSourceFilterProvider);
    final sources = ref.watch(allSourcesProvider).valueOrNull ?? const <String>[];
    final stages = ref.watch(allLearningStagesProvider).valueOrNull ?? const <String>[];
    final selectedStage = ref.watch(selectedLearningStageFilterProvider);
    final selectedDifficulty = ref.watch(selectedDifficultyFilterProvider);
    final selectedAttemptStatus = ref.watch(selectedAttemptStatusFilterProvider);
    final selectedQuestionType = ref.watch(selectedQuestionTypeFilterProvider);
    final sort = ref.watch(questionSortProvider);
    final selectedKnowledgePoint =
        ref.watch(selectedKnowledgePointFilterProvider);
    final activeFilterLabels = <String>[
      if (selectedSubject != null) selectedSubject.label,
      if (selectedMastery != null) _masteryFilterLabel(selectedMastery),
      if (unmasteredOnly) '未掌握',
      if (selectedMistakeCategory != null) selectedMistakeCategory.label,
      if (selectedKnowledgePoint != null) selectedKnowledgePoint,
      if (selectedTags.isNotEmpty) ...selectedTags,
      if (dueOnly) '待复习',
      if (favoritesOnly) '收藏',
      if (failedOnly) '待处理',
      if (pendingAiOnly) '待 AI 分析',
      if (lowConfidenceOnly) '待校对',
      if (dateRange == QuestionDateRange.last7Days) '近 7 天',
      if (dateRange == QuestionDateRange.last30Days) '近 30 天',
      if (selectedSource != null) '来源：$selectedSource',
      if (selectedStage != null) '年级：$selectedStage',
      if (selectedDifficulty != null) _difficultyFilterLabel(selectedDifficulty),
      if (selectedAttemptStatus != null) _attemptFilterLabel(selectedAttemptStatus),
      if (selectedQuestionType != null) selectedQuestionType.label,
      if (sort != QuestionSort.newest) _sortFilterLabel(sort),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectionMode ? '已选 ${_selectedQuestionIds.length} 道' : AppStrings.notebookTitle),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(CupertinoIcons.xmark),
                tooltip: '取消选择',
                onPressed: _exitSelectionMode,
              )
            : null,
        actions: _selectionMode
            ? <Widget>[
                IconButton(
                  icon: const Icon(CupertinoIcons.checkmark_square),
                  tooltip: '全选当前列表',
                  onPressed: () {
                    final items = questionsAsync.valueOrNull ?? const <QuestionRecord>[];
                    setState(() => _selectedQuestionIds.addAll(items.map((item) => item.id)));
                  },
                ),
              ]
            : <Widget>[
                IconButton(
                  icon: const Icon(CupertinoIcons.checkmark_square),
                  tooltip: '选择错题',
                  onPressed: () => setState(() => _selectionMode = true),
                ),
                IconButton(
                  icon: const Icon(CupertinoIcons.camera),
                  onPressed: () => CaptureEntryLauncher.show(context),
                  tooltip: '录入错题',
                ),
                PopupMenuButton<_NotebookMenuAction>(
                  icon: const Icon(CupertinoIcons.arrow_up_arrow_down),
                  tooltip: '排序',
                  onSelected: (action) => _applyMenuAction(ref, action),
                  itemBuilder: (_) => <PopupMenuEntry<_NotebookMenuAction>>[
                    CheckedPopupMenuItem<_NotebookMenuAction>(
                      value: _NotebookMenuAction.newest,
                      checked: sort == QuestionSort.newest,
                      child: const Text('按最新录入'),
                    ),
                    CheckedPopupMenuItem<_NotebookMenuAction>(
                      value: _NotebookMenuAction.oldest,
                      checked: sort == QuestionSort.oldest,
                      child: const Text('按最早录入'),
                    ),
                    CheckedPopupMenuItem<_NotebookMenuAction>(
                      value: _NotebookMenuAction.nextReview,
                      checked: sort == QuestionSort.nextReview,
                      child: const Text('按下次复习'),
                    ),
                  ],
                ),
              ],
      ),
      body: AppPage(
        maxWidth: AppContentWidth.wide,
        padding: EdgeInsets.zero,
        child: Column(
        children: <Widget>[
          _NotebookArchiveOverview(
            questions:
                questionsAsync.valueOrNull ?? const <QuestionRecord>[],
          ),
          // 搜索栏
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.xs),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: AppStrings.notebookSearchHint,
                prefixIcon: const Icon(CupertinoIcons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(CupertinoIcons.xmark_circle, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(searchQueryProvider.notifier).state = '';
                          setState(() {});
                        },
                      )
                    : null,
              ),
              onChanged: (v) {
                ref.read(searchQueryProvider.notifier).state = v;
                setState(() {});
              },
            ),
          ),
          // 高频筛选保留在首屏；低频条件收纳到高级筛选面板。
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
            child: Row(
              children: <Widget>[
                _Chip(
                  label: AppStrings.notebookFilterAll,
                  selected: activeFilterLabels.isEmpty,
                  onTap: () => _clearFilters(ref),
                ),
                const SizedBox(width: AppSpace.sm),
                _Chip(
                  label: AppStrings.notebookFilterDue,
                  selected: dueOnly,
                  onTap: () => ref.read(dueOnlyFilterProvider.notifier).state = !dueOnly,
                ),
                const SizedBox(width: AppSpace.sm),
                _Chip(
                  label: AppStrings.notebookFilterUnmastered,
                  selected: unmasteredOnly,
                  onTap: () => ref.read(unmasteredOnlyFilterProvider.notifier).state = !unmasteredOnly,
                ),
                const SizedBox(width: AppSpace.sm),
                _Chip(
                  label: '已掌握',
                  selected: selectedMastery == MasteryLevel.mastered,
                  onTap: () {
                    final notifier = ref.read(selectedMasteryFilterProvider.notifier);
                    notifier.state = selectedMastery == MasteryLevel.mastered
                        ? null
                        : MasteryLevel.mastered;
                  },
                ),
                const SizedBox(width: AppSpace.sm),
                _Chip(
                  label: AppStrings.notebookFilterFavorite,
                  selected: favoritesOnly,
                  onTap: () => ref.read(favoritesOnlyFilterProvider.notifier).state = !favoritesOnly,
                ),
                const SizedBox(width: AppSpace.sm),
                _Chip(
                  label: '待 AI',
                  selected: pendingAiOnly,
                  onTap: () => ref.read(pendingAiOnlyFilterProvider.notifier).state = !pendingAiOnly,
                ),
                const SizedBox(width: AppSpace.sm),
                _Chip(
                  label: '待校对',
                  selected: lowConfidenceOnly,
                  onTap: () => ref.read(lowConfidenceOnlyFilterProvider.notifier).state = !lowConfidenceOnly,
                ),
                const SizedBox(width: AppSpace.sm),
                _Chip(
                  label: AppStrings.notebookFilterMore,
                  selected: activeFilterLabels.any((label) =>
                      label != AppStrings.notebookFilterDue &&
                      label != AppStrings.notebookFilterUnmastered &&
                      label != AppStrings.notebookFilterFavorite &&
                      label != '已掌握' &&
                      label != '待 AI' &&
                      label != '待校对'),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => _AdvancedFilterSheet(
                      sources: sources,
                      stages: stages,
                      onClear: () => _clearFilters(ref),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 视图切换 + 显示归档（合并为一行，节省纵向空间）
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg, vertical: AppSpace.xs),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: SegmentedButton<NotebookViewMode>(
                    segments: const <ButtonSegment<NotebookViewMode>>[
                      ButtonSegment<NotebookViewMode>(
                        value: NotebookViewMode.card,
                        icon: Icon(CupertinoIcons.square_grid_2x2, size: 16),
                        label: Text('卡片'),
                      ),
                      ButtonSegment<NotebookViewMode>(
                        value: NotebookViewMode.list,
                        icon: Icon(CupertinoIcons.list_bullet, size: 16),
                        label: Text('列表'),
                      ),
                      ButtonSegment<NotebookViewMode>(
                        value: NotebookViewMode.timeline,
                        icon: Icon(CupertinoIcons.calendar, size: 16),
                        label: Text('时间线'),
                      ),
                    ],
                    selected: <NotebookViewMode>{_viewMode},
                    onSelectionChanged: (selection) =>
                        _setViewMode(selection.first),
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle: WidgetStateProperty.all(
                        const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(CupertinoIcons.archivebox,
                        size: 14, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Switch.adaptive(
                      value: _showArchived,
                      onChanged: (value) => setState(() => _showArchived = value),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (activeFilterLabels.isNotEmpty)
            _ActiveFilterSummary(
              labels: activeFilterLabels,
              onClear: () => _clearFilters(ref),
            ),
          const SizedBox(height: AppSpace.sm),
          // List
          Expanded(
            child: questionsAsync.when(
              data: (questions) {
                final visibleQuestions = _showArchived
                    ? questions
                    : questions.where((q) => !q.isArchived).toList();
                if (visibleQuestions.isEmpty) {
                  return AppEmptyState(
                    icon: CupertinoIcons.question,
                    title: AppStrings.notebookEmptyTitle,
                    description: AppStrings.notebookEmptySubtitle,
                    action: FilledButton.icon(
                      onPressed: () => CaptureEntryLauncher.show(context),
                      icon: const Icon(CupertinoIcons.add),
                      label: const Text(AppStrings.homeCapture),
                    ),
                  );
                }
                final hasPracticeAction =
                    selectedKnowledgePoint != null && visibleQuestions.isNotEmpty;
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(questionListProvider);
                  },
                  child: _buildQuestionList(
                    context: context,
                    ref: ref,
                    visibleQuestions: visibleQuestions,
                    hasPracticeAction: hasPracticeAction,
                    selectedKnowledgePoint: selectedKnowledgePoint,
                  ),
                );
              },
              loading: () => const AppLoadingState(label: '正在整理错题本…'),
              error: (_, __) => AppErrorState(onRetry: () => ref.invalidate(questionListProvider)),
            ),
          ),
          if (_selectionMode)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(children: <Widget>[
          Expanded(child: OutlinedButton.icon(onPressed: _selectedQuestionIds.isEmpty ? null : () => _deleteSelected(context, ref), icon: const Icon(CupertinoIcons.trash), label: const Text('删除'))),
          const SizedBox(width: 8),
          Expanded(child: FilledButton.icon(onPressed: _selectedQuestionIds.isEmpty ? null : () => _openWorksheet(context, ref), icon: const Icon(CupertinoIcons.doc_text), label: const Text('组卷'))),
          const SizedBox(width: 8),
          Expanded(child: FilledButton.tonalIcon(onPressed: _selectedQuestionIds.isEmpty ? null : () => _exportSelected(context), icon: const Icon(CupertinoIcons.arrow_up_doc), label: const Text('导出'))),
        ]),
              ),
            ),
        ],
        ),
      ),
    );
  }
}

enum _NotebookMenuAction {
  dueOnly,
  favoritesOnly,
  failedOnly,
  allDates,
  last7Days,
  last30Days,
  newest,
  oldest,
  nextReview,
}

class _NotebookArchiveOverview extends StatelessWidget {
  const _NotebookArchiveOverview({required this.questions});

  final List<QuestionRecord> questions;

  @override
  Widget build(BuildContext context) {
    final visual = AppVisualTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final dueCount = questions
        .where((q) => q.nextReviewAt != null && !q.nextReviewAt!.isAfter(now))
        .length;
    final attentionCount = questions
        .where((q) =>
            q.analysisResult == null ||
            q.contentStatus == ContentStatus.failed ||
            q.contentStatus == ContentStatus.analysisFailed ||
            (q.ocrConfidence != null && q.ocrConfidence! < .7))
        .length;
    final title = switch (visual.style) {
      AppVisualStyle.academic => '错题档案总览',
      AppVisualStyle.paper => '本册错题摘要',
      AppVisualStyle.aurora => '薄弱点聚焦',
      AppVisualStyle.forest => '今天温习什么',
    };
    final helper = switch (visual.style) {
      AppVisualStyle.academic => '先处理待校对和到期复习，保持档案清晰可用。',
      AppVisualStyle.paper => '把待整理的题目补齐，再按章节慢慢回看。',
      AppVisualStyle.aurora => '优先聚焦需要处理的输入与今日到期任务。',
      AppVisualStyle.forest => '不用一次做完，先从今天到期的题目开始。',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.lg,
        AppSpace.xs,
      ),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: visual.heroGradient,
                borderRadius: BorderRadius.circular(visual.controlRadius),
              ),
              child: Icon(
                switch (visual.style) {
                  AppVisualStyle.academic => CupertinoIcons.chart_bar_square,
                  AppVisualStyle.paper => CupertinoIcons.book,
                  AppVisualStyle.aurora => CupertinoIcons.scope,
                  AppVisualStyle.forest => CupertinoIcons.tree,
                },
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    helper,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            _ArchiveCount(value: questions.length, label: '全部'),
            const SizedBox(width: AppSpace.sm),
            _ArchiveCount(value: attentionCount, label: '待处理'),
            const SizedBox(width: AppSpace.sm),
            _ArchiveCount(value: dueCount, label: '到期'),
          ],
        ),
      ),
    );
  }
}

class _ArchiveCount extends StatelessWidget {
  const _ArchiveCount({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          Text(
            '$value',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
}

class _CardPrimaryAction {
  const _CardPrimaryAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class _ArchiveActionButton extends StatelessWidget {
  const _ArchiveActionButton({required this.action});

  final _CardPrimaryAction action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: AppSpace.xs),
      child: TextButton.icon(
        onPressed: action.onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: scheme.primaryContainer.withValues(alpha: .68),
          foregroundColor: scheme.onPrimaryContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        icon: Icon(action.icon, size: 14),
        label: Text(action.label),
      ),
    );
  }
}

class _KnowledgePointPracticeCard extends StatelessWidget {
  const _KnowledgePointPracticeCard({
    required this.knowledgePoint,
    required this.isLoading,
    required this.onStart,
  });

  final String knowledgePoint;
  final bool isLoading;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(CupertinoIcons.play_circle,
              color: colorScheme.onPrimaryContainer, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('专项练习：$knowledgePoint',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onPrimaryContainer)),
                const SizedBox(height: 3),
                Text('聚合关联错题的已有练习；没有练习时自动请求 AI 生成。',
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.onPrimaryContainer)),
              ],
            ),
          ),
          isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(onPressed: onStart, child: const Text('开始')),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppFilterChip(
        label: label,
        isSelected: selected,
        onTap: onTap,
      );
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.selectionMode,
    required this.selected,
    required this.onSelect,
    required this.onTap,
    required this.onDelete,
    required this.onKnowledgePointTap,
    required this.primaryAction,
  });

  final dynamic question;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final void Function(String knowledgePoint) onKnowledgePointTap;
  final _CardPrimaryAction? primaryAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final aiTags = question.aiTags ?? <String>[];
    final customTags = question.customTags ?? <String>[];
    final allTags = [...aiTags, ...customTags];
    final displayStatus = inferQuestionDisplayStatus(question);
    final isArchived = (question.isArchived as bool?) ?? false;

    return Dismissible(
      key: ValueKey(question.id),
      direction: selectionMode ? DismissDirection.none : DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: AppSpace.md),
        decoration: BoxDecoration(
          color:
              AppColors.danger.withValues(alpha: isDark ? 0.22 : 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(CupertinoIcons.trash, color: AppColors.danger),
      ),
      child: Semantics(
        button: true,
        label:
            '错题: ${question.correctedText}，科目: ${question.subject.label}，状态: ${_masteryLabel(question.masteryLevel)}，日期: ${_formatDate(question.createdAt)}，左滑删除',
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.md),
          child: GestureDetector(
            onTap: selectionMode ? onSelect : onTap,
            child: Opacity(
              opacity: isArchived ? 0.55 : 1.0,
              child: AppCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm + 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (selectionMode) ...<Widget>[
                      Checkbox(value: selected, onChanged: (_) => onSelect()),
                      const SizedBox(width: 4),
                    ],
                    Container(
                      width: 4,
                      height: 88,
                      decoration: BoxDecoration(
                        color: _priorityColor(context, displayStatus),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    _SubjectAvatar(question: question),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _buildArchiveHeader(context, displayStatus),
                          const SizedBox(height: AppSpace.sm),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: Hero(
                                  tag: 'question_text_${question.id}',
                                  child: Material(
                                    color: Colors.transparent,
                                    child: MathContentView(
                                      question.correctedText,
                                      contentFormat: question.contentFormat,
                                      mode: MathContentViewMode.compact,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14),
                                    ),
                                  ),
                                ),
                              ),
                              if (primaryAction != null)
                                _ArchiveActionButton(action: primaryAction!)
                              else
                                Padding(
                                  padding:
                                      const EdgeInsets.only(left: 4, top: 2),
                                  child: Icon(
                                    CupertinoIcons.chevron_right,
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.65),
                                    size: 18,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpace.xs),
                          _buildMetaInfo(context, displayStatus, isArchived),
                          if (_hasArchiveSignals) ...<Widget>[
                            const SizedBox(height: AppSpace.xs),
                            _buildArchiveSignals(context),
                          ],
                          if (allTags.isNotEmpty) ...<Widget>[
                            const SizedBox(height: AppSpace.xs),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: <Widget>[
                                  ...allTags.map((tag) {
                                    final isAiTag = aiTags.contains(tag);
                                    return Padding(
                                      padding: const EdgeInsets.only(right: AppSpace.xs),
                                      child: AppTag(
                                        label: tag,
                                        useThemeTone: true,
                                        themeTone: isAiTag
                                            ? AppTagTone.warning
                                            : AppTagTone.secondary,
                                        fontSize: 12,
                                        onTap: () => onKnowledgePointTap(tag),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _priorityColor(
    BuildContext context,
    QuestionDisplayStatus displayStatus,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final confidence = question.ocrConfidence as double?;
    final dueNow = question.nextReviewAt != null &&
        !question.nextReviewAt!.isAfter(DateTime.now());
    if (displayStatus.isFailed) return scheme.error;
    if (confidence != null && confidence < .7) return AppColors.accentAmber;
    if (dueNow) return const Color(0xFFEA580C);
    if (displayStatus.isInProgress) return scheme.primary;
    if (question.masteryLevel == MasteryLevel.mastered) {
      return AppColors.success;
    }
    return scheme.outlineVariant;
  }

  bool get _hasArchiveSignals =>
      question.mistakeCategory != null || question.ocrConfidence != null;

  Widget _buildArchiveSignals(BuildContext context) {
    final category = question.mistakeCategory as MistakeCategory?;
    final confidence = question.ocrConfidence as double?;
    return Wrap(
      spacing: AppSpace.xs,
      runSpacing: AppSpace.xs,
      children: <Widget>[
        if (category != null)
          AppTag(
            label: '错因 · ${category.label}',
            useThemeTone: true,
            themeTone: AppTagTone.tertiary,
            fontSize: 11,
          ),
        if (confidence != null)
          AppTag(
            label: '识别 ${(confidence * 100).round()}%',
            useThemeTone: true,
            themeTone:
                confidence < .7 ? AppTagTone.warning : AppTagTone.neutral,
            fontSize: 11,
          ),
      ],
    );
  }

  Widget _buildArchiveHeader(
    BuildContext context,
    QuestionDisplayStatus displayStatus,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final confidence = question.ocrConfidence as double?;
    final dueNow = question.nextReviewAt != null &&
        !question.nextReviewAt!.isAfter(DateTime.now());

    final (:label, :tone) = switch ((
      displayStatus.isFailed,
      confidence != null && confidence < .7,
      dueNow,
      displayStatus.isInProgress,
    )) {
      (true, _, _, _) => (label: '待处理', tone: AppTagTone.danger),
      (_, true, _, _) => (label: '待校对', tone: AppTagTone.warning),
      (_, _, true, _) => (label: '今日复习', tone: AppTagTone.warning),
      (_, _, _, true) => (label: '处理中', tone: AppTagTone.primary),
      _ => (label: '档案就绪', tone: AppTagTone.success),
    };

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            '${question.subject.label}档案  ·  ${_formatDate(question.createdAt)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: .2,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        AppTag(
          label: label,
          useThemeTone: true,
          themeTone: tone,
          fontSize: 11,
        ),
      ],
    );
  }

  IconData _dueIcon(QuestionRecord question) => question.nextReviewAt == null
      ? CupertinoIcons.calendar_badge_plus
      : !question.nextReviewAt!.isAfter(DateTime.now())
          ? CupertinoIcons.bell_fill : CupertinoIcons.calendar;

  Color _dueColor(BuildContext context, QuestionRecord question) => question.nextReviewAt != null && !question.nextReviewAt!.isAfter(DateTime.now())
      ? const Color(0xFFEA580C) : Theme.of(context).colorScheme.onSurfaceVariant;

  String _dueLabel(QuestionRecord question) {
    final next = question.nextReviewAt;
    if (next == null) return '尚未安排复习';
    final today = DateTime.now();
    if (!next.isAfter(today)) return '今天待复习';
    final days = DateTime(next.year, next.month, next.day).difference(DateTime(today.year, today.month, today.day)).inDays;
    return days == 1 ? '明天复习' : '$days 天后复习';
  }

  IconData _masteryIcon(MasteryLevel level) {
    switch (level) {
      case MasteryLevel.newQuestion:
        return CupertinoIcons.circle;
      case MasteryLevel.reviewing:
        return CupertinoIcons.circle_lefthalf_fill;
      case MasteryLevel.mastered:
        return CupertinoIcons.checkmark_circle_fill;
    }
  }

  Widget _buildMetaInfo(
      BuildContext context, QuestionDisplayStatus displayStatus, bool isArchived) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final masteryColor = _masteryColor(context, question.masteryLevel);
    final dueColor = _dueColor(context, question);
    final showDue = question.nextReviewAt != null;

    final spans = <InlineSpan>[
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Icon(
          _masteryIcon(question.masteryLevel),
          size: 11,
          color: masteryColor,
        ),
      ),
      TextSpan(
        text: _masteryLabel(question.masteryLevel),
        style: TextStyle(color: masteryColor),
      ),
    ];

    if (displayStatus.isFailed) {
      final failedColor = AppColors.danger;
      spans.add(const TextSpan(text: ' · '));
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Icon(CupertinoIcons.exclamationmark_triangle_fill,
            size: 11, color: failedColor),
      ));
      spans.add(TextSpan(
        text: displayStatus.label,
        style: TextStyle(color: failedColor),
      ));
    } else if (displayStatus.isInProgress) {
      final inProgressColor = isDark ? AppColors.info : AppColors.primary;
      spans.add(const TextSpan(text: ' · '));
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Icon(CupertinoIcons.hourglass,
            size: 11, color: inProgressColor),
      ));
      spans.add(TextSpan(
        text: displayStatus.label,
        style: TextStyle(color: inProgressColor),
      ));
    }

    if (isArchived) {
      spans.add(const TextSpan(text: ' · '));
      spans.add(const WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Icon(CupertinoIcons.archivebox, size: 11, color: AppColors.slate),
      ));
      spans.add(const TextSpan(
        text: '已归档',
        style: TextStyle(color: AppColors.slate),
      ));
    }

    if (showDue) {
      spans.add(const TextSpan(text: ' · '));
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Icon(_dueIcon(question), size: 11, color: dueColor),
      ));
      spans.add(TextSpan(
        text: _dueLabel(question),
        style: TextStyle(color: dueColor),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text.rich(
          TextSpan(
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            children: spans,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (_hasStatusBadges) ...<Widget>[
          const SizedBox(height: AppSpace.xs),
          _buildStatusBadges(context, displayStatus),
        ],
      ],
    );
  }

  /// 是否需要展示状态徽章行（难度 / 作答状态 / 置信度 / 反思笔记 / 判分结果）。
  bool get _hasStatusBadges =>
      this.question.difficulty != null ||
      this.question.attemptStatus != null ||
      (this.question.ocrConfidence != null && this.question.ocrConfidence! < 0.7) ||
      (this.question.reflectionNote?.isNotEmpty ?? false) ||
      this.question.isCorrect != null;

  /// 渲染状态徽章行：用紧凑的色块徽章展示难度/作答状态/置信度/反思/判分。
  Widget _buildStatusBadges(
      BuildContext context, QuestionDisplayStatus displayStatus) {
    final children = <Widget>[];

    final providerTag = question.tags.firstWhere(
      (tag) => tag.startsWith('layout_provider:'),
      orElse: () => '',
    );
    if (providerTag.isNotEmpty) {
      children.add(_MetaBadge(
        label: providerTag.substring('layout_provider:'.length),
        color: AppColors.successDark,
        icon: CupertinoIcons.doc_text_search,
      ));
    }

    if (displayStatus == QuestionDisplayStatus.recognized) {
      children.add(_MetaBadge(
        label: '待 AI',
        color: AppColors.primary,
        icon: CupertinoIcons.sparkles,
      ));
    } else if (displayStatus == QuestionDisplayStatus.analyzed) {
      children.add(_MetaBadge(
        label: 'AI 已分析',
        color: AppColors.success,
        icon: CupertinoIcons.checkmark_seal,
      ));
    }

    final difficulty = question.difficulty;
    if (difficulty != null) {
      children.add(_MetaBadge(
        label: _difficultyLabel(difficulty),
        color: _difficultyColor(difficulty),
      ));
    }

    final attempt = question.attemptStatus;
    if (attempt != null && attempt != AttemptStatus.notAttempted) {
      children.add(_MetaBadge(
        label: _attemptStatusLabel(attempt),
        color: _attemptStatusColor(attempt),
        icon: _attemptStatusIcon(attempt),
      ));
    }

    final confidence = question.ocrConfidence;
    if (confidence != null && confidence < 0.7) {
      children.add(_MetaBadge(
        label: '置信度低',
        color: AppColors.warning,
        icon: CupertinoIcons.exclamationmark,
      ));
    }

    if (question.reflectionNote?.isNotEmpty ?? false) {
      children.add(_MetaBadge(
        label: '反思',
        color: AppColors.accentPurple,
        icon: CupertinoIcons.pencil_ellipsis_rectangle,
      ));
    }

    final isCorrect = question.isCorrect;
    if (isCorrect != null) {
      children.add(_MetaBadge(
        label: isCorrect ? '答对' : '答错',
        color: isCorrect ? AppColors.success : AppColors.danger,
        icon: isCorrect
            ? CupertinoIcons.checkmark_circle_fill
            : CupertinoIcons.xmark_circle_fill,
      ));
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: AppSpace.xs,
      runSpacing: AppSpace.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  String _difficultyLabel(QuestionDifficulty difficulty) {
    switch (difficulty) {
      case QuestionDifficulty.foundation:
        return '基础';
      case QuestionDifficulty.advanced:
        return '提高';
      case QuestionDifficulty.challenge:
        return '挑战';
      case QuestionDifficulty.custom:
        return '自定义';
    }
  }

  Color _difficultyColor(QuestionDifficulty difficulty) {
    switch (difficulty) {
      case QuestionDifficulty.foundation:
        return AppColors.accentTeal;
      case QuestionDifficulty.advanced:
        return AppColors.accentAmber;
      case QuestionDifficulty.challenge:
        return AppColors.danger;
      case QuestionDifficulty.custom:
        return AppColors.slate;
    }
  }

  String _attemptStatusLabel(AttemptStatus status) {
    switch (status) {
      case AttemptStatus.notAttempted:
        return '未作答';
      case AttemptStatus.wrongAttempt:
        return '答错';
      case AttemptStatus.incomplete:
        return '未完成';
      case AttemptStatus.unknown:
        return '作答未知';
    }
  }

  Color _attemptStatusColor(AttemptStatus status) {
    switch (status) {
      case AttemptStatus.notAttempted:
        return AppColors.slate;
      case AttemptStatus.wrongAttempt:
        return AppColors.danger;
      case AttemptStatus.incomplete:
        return AppColors.warning;
      case AttemptStatus.unknown:
        return AppColors.slate;
    }
  }

  IconData _attemptStatusIcon(AttemptStatus status) {
    switch (status) {
      case AttemptStatus.notAttempted:
        return CupertinoIcons.circle;
      case AttemptStatus.wrongAttempt:
        return CupertinoIcons.xmark_circle;
      case AttemptStatus.incomplete:
        return CupertinoIcons.exclamationmark_circle;
      case AttemptStatus.unknown:
        return CupertinoIcons.question_circle;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return '今天';
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${date.month}月${date.day}日';
  }

}

class _SubjectAvatar extends StatelessWidget {
  const _SubjectAvatar({required this.question});

  final QuestionRecord question;

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 360;
    final size = isSmall ? 36.0 : 40.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: question.subject.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Hero(
        tag: 'subject_icon_${question.id}',
        child: Icon(question.subject.icon,
            size: isSmall ? 18 : 20, color: question.subject.color),
      ),
    );
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

String _masteryLabel(MasteryLevel level) {
  switch (level) {
    case MasteryLevel.newQuestion:
      return '新增';
    case MasteryLevel.reviewing:
      return '复习中';
    case MasteryLevel.mastered:
      return '已掌握';
  }
}

/// 错题卡片上的紧凑元数据徽章：色块背景 + 可选图标 + 标签。
/// 用于在列表层快速展示难度 / 作答状态 / 置信度 / 反思笔记 / 判分结果。
class _MetaBadge extends StatelessWidget {
  const _MetaBadge({
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.10),
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 2),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

String _difficultyFilterLabel(QuestionDifficulty value) => switch (value) {
      QuestionDifficulty.foundation => '基础题',
      QuestionDifficulty.advanced => '提高题',
      QuestionDifficulty.challenge => '压轴题',
      QuestionDifficulty.custom => '自定义层级',
    };

String _attemptFilterLabel(AttemptStatus value) => switch (value) {
      AttemptStatus.notAttempted => '不会做',
      AttemptStatus.wrongAttempt => '做错了',
      AttemptStatus.incomplete => '未完成',
      AttemptStatus.unknown => '作答未判断',
    };

String _masteryFilterLabel(MasteryLevel value) => switch (value) {
      MasteryLevel.newQuestion => '新题',
      MasteryLevel.reviewing => '学习中',
      MasteryLevel.mastered => '已掌握',
    };

String _sortFilterLabel(QuestionSort value) => switch (value) {
      QuestionSort.newest => '最新录入',
      QuestionSort.oldest => '最早录入',
      QuestionSort.nextReview => '下次复习',
      QuestionSort.mastery => '掌握度低到高',
      QuestionSort.subject => '按科目',
    };

class _AdvancedFilterSheet extends ConsumerWidget {
  const _AdvancedFilterSheet({
    required this.sources,
    required this.stages,
    required this.onClear,
  });

  final List<String> sources;
  final List<String> stages;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subject = ref.watch(selectedSubjectFilterProvider);
    final category = ref.watch(selectedMistakeCategoryFilterProvider);
    final knowledge = ref.watch(selectedKnowledgePointFilterProvider);
    final dateRange = ref.watch(questionDateRangeProvider);
    final source = ref.watch(selectedSourceFilterProvider);
    final stage = ref.watch(selectedLearningStageFilterProvider);
    final difficulty = ref.watch(selectedDifficultyFilterProvider);
    final attempt = ref.watch(selectedAttemptStatusFilterProvider);
    final questionType = ref.watch(selectedQuestionTypeFilterProvider);
    final failedOnly = ref.watch(failedOnlyFilterProvider);
    final sort = ref.watch(questionSortProvider);
    final points = ref.watch(allKnowledgePointsProvider).valueOrNull ?? const <String>[];

    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: .65,
        minChildSize: .4,
        maxChildSize: .9,
        expand: false,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          children: <Widget>[
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Theme.of(context).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: <Widget>[Text(AppStrings.notebookAdvancedFilter, style: Theme.of(context).textTheme.titleLarge), const Spacer(), TextButton(onPressed: onClear, child: const Text(AppStrings.notebookClearFilters))]),
            _FilterOptionGroup<Subject>(title: '科目', values: Subject.values, selected: subject, label: (value) => value.label, onChanged: (value) => ref.read(selectedSubjectFilterProvider.notifier).state = value),
            _FilterOptionGroup<MistakeCategory>(title: '错因', values: MistakeCategory.values, selected: category, label: (value) => value.label, onChanged: (value) => ref.read(selectedMistakeCategoryFilterProvider.notifier).state = value),
            _FilterOptionGroup<QuestionType>(title: '题型', values: QuestionType.values, selected: questionType, label: (value) => value.label, onChanged: (value) => ref.read(selectedQuestionTypeFilterProvider.notifier).state = value),
            if (points.isNotEmpty) _FilterOptionGroup<String>(title: '知识点', values: points, selected: knowledge, label: (value) => value, onChanged: (value) => ref.read(selectedKnowledgePointFilterProvider.notifier).state = value),
            _FilterOptionGroup<QuestionDateRange>(title: '录入日期', values: const <QuestionDateRange>[QuestionDateRange.all, QuestionDateRange.last7Days, QuestionDateRange.last30Days], selected: dateRange, label: _dateRangeLabel, onChanged: (value) => ref.read(questionDateRangeProvider.notifier).state = value ?? QuestionDateRange.all),
            if (sources.isNotEmpty) _FilterOptionGroup<String>(title: '来源批次', values: sources, selected: source, label: (value) => value, onChanged: (value) => ref.read(selectedSourceFilterProvider.notifier).state = value),
            if (stages.isNotEmpty) _FilterOptionGroup<String>(title: '年级 / 学习阶段', values: stages, selected: stage, label: (value) => value, onChanged: (value) => ref.read(selectedLearningStageFilterProvider.notifier).state = value),
            _FilterOptionGroup<QuestionDifficulty>(title: '难度', values: QuestionDifficulty.values, selected: difficulty, label: _difficultyFilterLabel, onChanged: (value) => ref.read(selectedDifficultyFilterProvider.notifier).state = value),
            _FilterOptionGroup<AttemptStatus>(title: '作答状态', values: AttemptStatus.values, selected: attempt, label: _attemptFilterLabel, onChanged: (value) => ref.read(selectedAttemptStatusFilterProvider.notifier).state = value),
            _FilterOptionGroup<QuestionSort>(title: '排序', values: QuestionSort.values, selected: sort, label: _sortFilterLabel, onChanged: (value) => ref.read(questionSortProvider.notifier).state = value ?? QuestionSort.newest),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('仅看待处理草稿'),
              value: failedOnly,
              onChanged: (value) => ref.read(failedOnlyFilterProvider.notifier).state = value,
            ),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text(AppStrings.notebookDone))),
          ],
        ),
      ),
    );
  }
}

class _FilterOptionGroup<T> extends StatelessWidget {
  const _FilterOptionGroup({required this.title, required this.values, required this.selected, required this.label, required this.onChanged});
  final String title;
  final List<T> values;
  final T? selected;
  final String Function(T) label;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: values.map((value) => ChoiceChip(label: Text(label(value)), selected: selected == value, onSelected: (_) => onChanged(selected == value ? null : value))).toList()),
    ]),
  );
}

String _dateRangeLabel(QuestionDateRange value) => switch (value) {
      QuestionDateRange.all => '不限',
      QuestionDateRange.last7Days => '近 7 天',
      QuestionDateRange.last30Days => '近 30 天',
    };

class _ActiveFilterSummary extends StatelessWidget {
  const _ActiveFilterSummary({required this.labels, required this.onClear});

  final List<String> labels;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
      child: Row(
        children: <Widget>[
          const Icon(CupertinoIcons.line_horizontal_3_decrease_circle,
              size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              labels.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }
}

/// Phase 6-1：将 'yyyy-MM-dd' 格式的日期键格式化为友好的中文标签。
/// 今天 / 昨天 / N天前 / M月D日（更早或未来日期回退到月日）。
String _formatTimelineDateKey(String dateKey) {
  final parts = dateKey.split('-');
  if (parts.length != 3) return dateKey;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return dateKey;
  final date = DateTime(year, month, day);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(date).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  if (diff > 1 && diff < 7) return '$diff天前';
  if (diff == -1) return '明天';
  return '$month月$day日';
}

/// Phase 6-1：紧凑列表行——一行一题，省去题图缩略图与多行徽章，
/// 适合在长列表中快速浏览。复用 [_SubjectAvatar] / [_MetaBadge] /
/// [_masteryColor] / [_masteryLabel] 保持视觉一致。
class _CompactQuestionRow extends StatelessWidget {
  const _CompactQuestionRow({
    required this.question,
    required this.selectionMode,
    required this.selected,
    required this.onSelect,
    required this.onTap,
    required this.onDelete,
  });

  final QuestionRecord question;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final masteryColor = _masteryColor(context, question.masteryLevel);
    final isArchived = question.isArchived;
    final displayStatus = inferQuestionDisplayStatus(question);

    return Dismissible(
      key: ValueKey('compact-${question.id}'),
      direction:
          selectionMode ? DismissDirection.none : DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: AppSpace.sm),
        decoration: BoxDecoration(
          color:
              AppColors.danger.withValues(alpha: isDark ? 0.22 : 0.10),
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
        child: const Icon(CupertinoIcons.trash, color: AppColors.danger),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: GestureDetector(
          onTap: selectionMode ? onSelect : onTap,
          child: Opacity(
            opacity: isArchived ? 0.55 : 1.0,
            child: AppCard(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md, vertical: AppSpace.sm),
              child: Row(
                children: <Widget>[
                  if (selectionMode) ...<Widget>[
                    Checkbox(value: selected, onChanged: (_) => onSelect()),
                    const SizedBox(width: 4),
                  ],
                  _SubjectAvatar(question: question),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        MathContentView(
                          question.correctedText,
                          contentFormat: question.contentFormat,
                          mode: MathContentViewMode.compact,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w500, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: AppSpace.xs,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            Text(
                              question.subject.label,
                              style: TextStyle(
                                fontSize: 12,
                                color: question.subject.color,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (question.questionType != null)
                              _MetaBadge(
                                label: question.questionType!.label,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            if (displayStatus.isFailed)
                              _MetaBadge(
                                label: displayStatus.label,
                                color: AppColors.danger,
                                icon: CupertinoIcons.exclamationmark_triangle_fill,
                              ),
                            if (isArchived)
                              _MetaBadge(
                                label: '已归档',
                                color: AppColors.slate,
                                icon: CupertinoIcons.archivebox,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: masteryColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _masteryLabel(question.masteryLevel),
                            style: TextStyle(
                              fontSize: 12,
                              color: masteryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Icon(
                        CupertinoIcons.chevron_right,
                        size: 14,
                        color: colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.65),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Phase 6-1：时间线日期分组头。显示友好日期 + 当日题数。
class _TimelineDateHeader extends StatelessWidget {
  const _TimelineDateHeader({
    required this.dateKey,
    required this.count,
  });

  final String dateKey;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.xs, AppSpace.md, AppSpace.xs, AppSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Text(
            _formatTimelineDateKey(dateKey),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Text(
            '$count 道',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Phase 6-1：时间线题目行。左侧为时间线轨道（节点 + 连接线），
/// 右侧为题干与元信息。当 [isLastInGroup] 为 true 时轨道不向下方延伸，
/// 以便与下一日的分组头断开。
class _TimelineQuestionRow extends StatelessWidget {
  const _TimelineQuestionRow({
    required this.question,
    required this.selectionMode,
    required this.selected,
    required this.onSelect,
    required this.onTap,
    required this.onDelete,
    required this.isLastInGroup,
  });

  final QuestionRecord question;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool isLastInGroup;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final masteryColor = _masteryColor(context, question.masteryLevel);
    final isArchived = question.isArchived;

    return Dismissible(
      key: ValueKey('timeline-${question.id}'),
      direction:
          selectionMode ? DismissDirection.none : DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color:
              AppColors.danger.withValues(alpha: isDark ? 0.22 : 0.10),
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
        child: const Icon(CupertinoIcons.trash, color: AppColors.danger),
      ),
      child: GestureDetector(
        onTap: selectionMode ? onSelect : onTap,
        child: Opacity(
          opacity: isArchived ? 0.55 : 1.0,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  width: 24,
                  child: CustomPaint(
                    painter: _TimelineTrackPainter(
                      lineColor: colorScheme.outlineVariant,
                      nodeColor: masteryColor,
                      surfaceColor: colorScheme.surface,
                      drawLineBelow: !isLastInGroup,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        0, AppSpace.xs, AppSpace.sm, AppSpace.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (selectionMode)
                          Align(
                            alignment: Alignment.centerRight,
                            child: Checkbox(
                                value: selected,
                                onChanged: (_) => onSelect()),
                          ),
                        MathContentView(
                          question.correctedText,
                          contentFormat: question.contentFormat,
                          mode: MathContentViewMode.compact,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w500, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: AppSpace.xs,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            Text(
                              question.subject.label,
                              style: TextStyle(
                                fontSize: 12,
                                color: question.subject.color,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '· ${_masteryLabel(question.masteryLevel)}',
                              style: TextStyle(
                                  fontSize: 12, color: masteryColor),
                            ),
                            Text(
                              '· ${question.createdAt.hour.toString().padLeft(2, '0')}:${question.createdAt.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: AppSpace.xs),
                  child: Icon(
                    CupertinoIcons.chevron_right,
                    size: 14,
                    color:
                        colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
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

/// [_TimelineQuestionRow] 左侧轨道的绘制器：顶端向下绘制竖线，
/// 在竖线上方绘制节点圆点（带 surface 描边以遮断竖线）。
/// 当 [drawLineBelow] 为 false（即分组最后一行）时，竖线只画到节点中心，
/// 不再向下延伸。
class _TimelineTrackPainter extends CustomPainter {
  _TimelineTrackPainter({
    required this.lineColor,
    required this.nodeColor,
    required this.surfaceColor,
    required this.drawLineBelow,
  });

  final Color lineColor;
  final Color nodeColor;
  final Color surfaceColor;
  final bool drawLineBelow;

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final nodeCenterY = 10.0;
    final nodeRadius = 5.0;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final lineBottom = drawLineBelow ? size.height : nodeCenterY;
    canvas.drawLine(
      Offset(centerX, 0),
      Offset(centerX, lineBottom),
      linePaint,
    );

    // surface 描边遮断竖线，让节点视觉上"穿"在线上
    final borderPaint = Paint()
      ..color = surfaceColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(centerX, nodeCenterY),
      nodeRadius + 2,
      borderPaint,
    );
    final nodePaint = Paint()
      ..color = nodeColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(centerX, nodeCenterY),
      nodeRadius,
      nodePaint,
    );
  }

  @override
  bool shouldRepaint(_TimelineTrackPainter oldDelegate) =>
      lineColor != oldDelegate.lineColor ||
      nodeColor != oldDelegate.nodeColor ||
      surfaceColor != oldDelegate.surfaceColor ||
      drawLineBelow != oldDelegate.drawLineBelow;
}

/// Phase 6-1：错题列表视图模式。
enum NotebookViewMode {
  /// 卡片视图（默认，信息最全，含题图缩略图）。
  card,

  /// 紧凑列表视图（一行一题，按科目/题型/掌握度排成表）。
  list,

  /// 时间线视图（按日期分组，事件流：添加 / 复习 / 分析）。
  timeline;

  /// 持久化到 SharedPreferences 的稳定标识符。
  String get storageName => name;

  /// 从持久化的字符串反序列化。无法识别时回退到 [card]。
  static NotebookViewMode fromStorageName(String? value) {
    switch (value) {
      case 'list':
        return NotebookViewMode.list;
      case 'timeline':
        return NotebookViewMode.timeline;
      case 'card':
      default:
        return NotebookViewMode.card;
    }
  }
}

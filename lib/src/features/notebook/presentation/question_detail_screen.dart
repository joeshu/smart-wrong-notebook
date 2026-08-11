import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/core/constants/app_strings.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/pending_knowledge_point_mapping.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_knowledge_link.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_type.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/domain/services/auto_grading_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/review_schedule_service.dart';
import 'package:smart_wrong_notebook/src/features/review/presentation/review_controller.dart';
import 'package:smart_wrong_notebook/src/shared/models/question_display_status.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_layout.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/cached_question_image.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/confidence_badge.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/single_text_field_dialog.dart';

class QuestionDetailScreen extends ConsumerStatefulWidget {
  const QuestionDetailScreen({super.key});

  @override
  ConsumerState<QuestionDetailScreen> createState() => _QuestionDetailScreenState();
}

class _QuestionDetailScreenState extends ConsumerState<QuestionDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(currentQuestionProvider);

    if (current == null) {
      return Scaffold(
        appBar: AppBar(title: const Text(AppStrings.detailTitle)),
        body: const Center(child: Text('未找到该错题')),
      );
    }

    final result = current.analysisResult;
    final batchGroupsAsync = ref.watch(questionBatchGroupsProvider);
    final batchGroups = batchGroupsAsync.valueOrNull;
    final batchGroup = batchGroups?[questionBatchRootId(current)];
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.detailTitle),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => context.go('/notebook'),
        ),
        actions: <Widget>[
          IconButton(
            icon: Icon(current.isFavorite
                ? CupertinoIcons.star_fill
                : CupertinoIcons.star),
            tooltip: current.isFavorite ? '取消收藏' : '收藏',
            onPressed: () => _toggleFavorite(context, ref, current),
          ),
          IconButton(
            icon: Icon(current.isArchived
                ? CupertinoIcons.archivebox_fill
                : CupertinoIcons.archivebox),
            tooltip: current.isArchived ? '取消归档' : '归档',
            onPressed: () => current.isArchived
                ? _unarchive(context, ref, current)
                : _confirmArchive(context, ref, current),
          ),
          IconButton(
            icon: Icon(_editing ? CupertinoIcons.check_mark : CupertinoIcons.pencil),
            tooltip: _editing ? '完成编辑' : '编辑题目',
            onPressed: () => setState(() => _editing = !_editing),
          ),
          if (_editing)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') _confirmDelete(context, ref, current);
              },
              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: <Widget>[
                    Icon(CupertinoIcons.trash, color: AppColors.danger, size: 20),
                    SizedBox(width: 8),
                    Text('删除', style: TextStyle(color: AppColors.danger)),
                  ]),
                ),
              ],
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(999),
          ),
          labelColor: colorScheme.onPrimary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          tabs: const <Widget>[
            Tab(text: AppStrings.detailTabQuestion),
            Tab(text: AppStrings.detailTabAnalysis),
            Tab(text: AppStrings.detailTabPractice),
            Tab(text: AppStrings.detailTabRecord),
          ],
        ),
      ),
      body: AppPage(
        maxWidth: AppContentWidth.wide,
        padding: EdgeInsets.zero,
        child: Column(
        children: <Widget>[
          if (_editing)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, 0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _editQuestion(context, ref, current),
                  icon: const Icon(CupertinoIcons.doc_text),
                  label: const Text('编辑题干、答案与解析'),
                ),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: <Widget>[
                _QuestionTab(
                  current: current,
                  editing: _editing,
                  batchGroup: batchGroup,
                  showFullImage: (path, filename) =>
                      _showFullImage(context, path, filename),
                  onReselectImage: () => _reselectImage(context, ref, current),
                  onToggleFavorite: () => _toggleFavorite(context, ref, current),
                  onEditSource: () => _editSource(context, ref, current),
                  onEditLearningContext: () => _editLearningContext(context, ref, current),
                  onSelectSibling: (question) {
                    ref.read(currentQuestionProvider.notifier).state = question;
                    context.go('/notebook/question/${question.id}');
                  },
                  onAddTag: () => _showAddTagDialog(context, ref, current),
                  onEditReflection: () => _editReflection(context, ref, current),
                  onEditStudentAnswer: () => _editStudentAnswer(context, ref, current),
                  onEditExpectedAnswer: () => _editExpectedAnswer(context, ref, current),
                  onGradeAnswer: () => _gradeAnswer(context, ref, current),
                ),
                _AnalysisTab(
                  current: current,
                  result: result,
                  onSetCategory: (category) => _setMistakeCategory(context, ref, current, category),
                  onAddAnalysis: () {
                    ref.read(currentQuestionProvider.notifier).state = current;
                    context.go('/analysis/loading');
                  },
                ),
                _PracticeTab(current: current),
                _RecordTab(
                  current: current,
                  onForgot: () => _markResult(context, ref, current, ReviewRating.forgot),
                  onHard: () => _markResult(context, ref, current, ReviewRating.hard),
                  onEasy: () => _markResult(context, ref, current, ReviewRating.easy),
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  void _editLearningContext(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) {
    final stageController = TextEditingController(text: question.learningStage ?? '');
    final workController = TextEditingController(text: question.studentWork ?? '');
    var difficulty = question.difficulty;
    var attemptStatus = question.attemptStatus;
    var questionType = question.questionType;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text(AppStrings.detailLearningProfile),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                DropdownButtonFormField<QuestionType?>(
                  value: questionType,
                  decoration: const InputDecoration(
                    labelText: '题型',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('未设置')),
                    DropdownMenuItem(value: QuestionType.singleChoice, child: Text('单选题')),
                    DropdownMenuItem(value: QuestionType.multipleChoice, child: Text('多选题')),
                    DropdownMenuItem(value: QuestionType.trueFalse, child: Text('判断题')),
                    DropdownMenuItem(value: QuestionType.fillIn, child: Text('填空题')),
                    DropdownMenuItem(value: QuestionType.shortAnswer, child: Text('简答题')),
                    DropdownMenuItem(value: QuestionType.essay, child: Text('论述题')),
                    DropdownMenuItem(value: QuestionType.calculation, child: Text('计算题')),
                    DropdownMenuItem(value: QuestionType.proof, child: Text('证明题')),
                    DropdownMenuItem(value: QuestionType.experiment, child: Text('实验题')),
                    DropdownMenuItem(value: QuestionType.other, child: Text('其他题型')),
                  ],
                  onChanged: (value) => setState(() => questionType = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: stageController,
                  maxLength: 30,
                  decoration: const InputDecoration(
                    labelText: '年级 / 教材阶段',
                    hintText: '例如：七年级上、人教版必修一',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<QuestionDifficulty?>(
                  value: difficulty,
                  decoration: const InputDecoration(
                    labelText: '题目层级',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('未设置')),
                    DropdownMenuItem(value: QuestionDifficulty.foundation, child: Text('基础')),
                    DropdownMenuItem(value: QuestionDifficulty.advanced, child: Text('提高')),
                    DropdownMenuItem(value: QuestionDifficulty.challenge, child: Text('压轴 / 挑战')),
                    DropdownMenuItem(value: QuestionDifficulty.custom, child: Text('自定义')),
                  ],
                  onChanged: (value) => setState(() => difficulty = value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AttemptStatus?>(
                  value: attemptStatus,
                  decoration: const InputDecoration(
                    labelText: '作答状态',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('未判断')),
                    DropdownMenuItem(value: AttemptStatus.notAttempted, child: Text('不会做')),
                    DropdownMenuItem(value: AttemptStatus.wrongAttempt, child: Text('做错了')),
                    DropdownMenuItem(value: AttemptStatus.incomplete, child: Text('未完成')),
                    DropdownMenuItem(value: AttemptStatus.unknown, child: Text('未判断（已标记）')),
                  ],
                  onChanged: (value) => setState(() => attemptStatus = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: workController,
                  maxLines: 3,
                  maxLength: 240,
                  decoration: const InputDecoration(
                    labelText: '我的作答 / 订正过程',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                var updated = question.withLearningContext(
                  learningStage: stageController.text,
                  difficulty: difficulty,
                  attemptStatus: attemptStatus,
                  studentWork: workController.text,
                );
                if (updated.questionType != questionType) {
                  updated = updated.copyWith(questionType: questionType);
                }
                await ref.read(questionRepositoryProvider).update(updated);
                ref.read(currentQuestionProvider.notifier).state = updated;
                invalidateQuestionList(ref);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    ).then((_) {
      stageController.dispose();
      workController.dispose();
    });
  }

  Future<void> _editSource(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) async {
    final text = await showSingleTextFieldDialog(
      context: context,
      title: '题目来源',
      initialText: question.source ?? '',
      autofocus: true,
      maxLength: 30,
      hintText: '例如：期中考试、课堂作业',
    );
    if (text == null) return;
    final updated = question.withSource(text);
    await ref.read(questionRepositoryProvider).update(updated);
    ref.read(currentQuestionProvider.notifier).state = updated;
    invalidateQuestionList(ref);
  }

  Future<void> _editQuestion(
      BuildContext context, WidgetRef ref, QuestionRecord question) async {
    final text = await showSingleTextFieldDialog(
      context: context,
      title: '编辑题目',
      initialText: question.correctedText,
      maxLines: 4,
    );
    if (text == null) return;
    final updated = question.copyWith(normalizedQuestionText: text);
    await ref.read(questionRepositoryProvider).update(updated);
    ref.read(currentQuestionProvider.notifier).state = updated;
    invalidateQuestionList(ref);
  }

  Future<void> _editReflection(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) async {
    final text = await showSingleTextFieldDialog(
      context: context,
      title: '学习反思',
      initialText: question.reflectionNote ?? '',
      maxLines: 6,
      minLines: 3,
      hintText: '记录你对这道题的反思、总结或易错点…',
    );
    if (text == null) return;
    final updated = question.copyWith(reflectionNote: text);
    await ref.read(questionRepositoryProvider).update(updated);
    ref.read(currentQuestionProvider.notifier).state = updated;
    invalidateQuestionList(ref);
  }

  Future<void> _editStudentAnswer(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) async {
    final text = await showSingleTextFieldDialog(
      context: context,
      title: '我的答案',
      initialText: question.studentAnswer ?? '',
      maxLines: 8,
      minLines: 3,
      hintText: '记录你的作答过程（支持 LaTeX 公式）…',
    );
    if (text == null) return;
    final updated = question.copyWith(studentAnswer: text);
    await ref.read(questionRepositoryProvider).saveDraft(updated);
    ref.read(currentQuestionProvider.notifier).state = updated;
    invalidateQuestionList(ref);
  }

  Future<void> _editExpectedAnswer(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) async {
    final text = await showSingleTextFieldDialog(
      context: context,
      title: '标准答案',
      initialText: question.expectedAnswer ?? '',
      maxLines: 8,
      minLines: 3,
      hintText: '填写标准答案（支持 LaTeX 公式）…',
    );
    if (text == null) return;
    final updated = question.withExpectedAnswer(text);
    await ref.read(questionRepositoryProvider).saveDraft(updated);
    ref.read(currentQuestionProvider.notifier).state = updated;
    invalidateQuestionList(ref);
  }

  Future<void> _gradeAnswer(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) async {
    final service = AutoGradingService(
      ref.read(aiAnalysisServiceProvider),
      ref.read(questionRepositoryProvider),
    );
    try {
      final isCorrect = await service.gradeQuestion(question);
      // gradeQuestion 内部已通过 saveDraft 写回 isCorrect；这里同步刷新当前
      // 题目快照，避免 UI 等待 watchAll() 推送。
      final updated = question.withIsCorrect(isCorrect);
      ref.read(currentQuestionProvider.notifier).state = updated;
      invalidateQuestionList(ref);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isCorrect ? '判分结果：正确' : '判分结果：错误')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('判分失败：$e')),
      );
    }
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, QuestionRecord question) {
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
              if (context.mounted) context.go('/notebook');
            },
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  void _showAddTagDialog(
      BuildContext context, WidgetRef ref, QuestionRecord question) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加标签'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '输入标签名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text('已有标签',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: <Widget>[
                ...question.aiTags
                    .map((tag) => _dialogTagChip(tag, Colors.orange)),
                ...question.aiKnowledgePoints
                    .map((kp) => _dialogTagChip(kp, Colors.orange)),
                ...question.customTags
                    .map((t) => _dialogTagChip(t, Colors.indigo)),
              ],
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final tag = controller.text.trim();
              if (tag.isEmpty) return;

              final allTags = [
                ...question.aiTags,
                ...question.aiKnowledgePoints,
                ...question.customTags
              ];
              if (allTags.contains(tag)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('标签已存在')),
                );
                return;
              }

              final newTags = [...question.customTags, tag];
              final updated = question.copyWith(customTags: newTags);
              await ref.read(questionRepositoryProvider).update(updated);
              ref.read(currentQuestionProvider.notifier).state = updated;
              invalidateQuestionList(ref);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  Widget _dialogTagChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: color)),
    );
  }

  void _showFullImage(BuildContext context, String imagePath, String? filename) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            title: Text(filename != null && filename.isNotEmpty
                ? '原图 · $filename'
                : '原图'),
          ),
          body: Center(
            child: InteractiveViewer(
              child: CachedQuestionImage(
                imagePath,
                highRes: true,
                filename: filename,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 详情页重新选图：保留题目其它字段，仅替换 imagePath 并持久化。
  ///
  /// 与批量导入页不同，这里走错题本仓库而不是 worksheet 会话，因为题目
  /// 已经落库。旧文件若仍存在则清理；不阻塞主流程。
  Future<void> _reselectImage(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final XFile? picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2560,
      maxHeight: 2560,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    try {
      final storage = ref.read(imageStorageServiceProvider);
      final newPath = await storage.saveImage(File(picked.path));
      final oldPath = question.imagePath;
      // 重置识别状态为 processing，提示用户重新走识别流程；同时清空失败原因。
      final updated = question.copyWith(
        imagePath: newPath,
        contentStatus: ContentStatus.processing,
        ocrConfidence: null,
      ).withLastAnalysisError(null);
      await ref.read(questionRepositoryProvider).update(updated);
      ref.read(currentQuestionProvider.notifier).state = updated;
      invalidateQuestionList(ref);
      if (oldPath.isNotEmpty && oldPath != newPath) {
        await storage.deleteImage(oldPath);
      }
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text('已重新选图，识别状态已重置，可重新识别'),
        duration: Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('重新选图失败: $e')));
    }
  }

  Future<void> _toggleFavorite(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) async {
    final updated = question.withFavorite(!question.isFavorite);
    await ref.read(questionRepositoryProvider).update(updated);
    ref.read(currentQuestionProvider.notifier).state = updated;
    invalidateQuestionList(ref);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(updated.isFavorite ? '已收藏' : '已取消收藏')),
    );
  }

  void _confirmArchive(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('归档这道错题？'),
        content: const Text('归档后题目默认从错题本列表隐藏，可在"显示归档"中查看，随时可取消归档。'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _archive(context, ref, question);
            },
            child: const Text('归档'),
          ),
        ],
      ),
    );
  }

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) async {
    final updated = question.archive();
    await ref.read(questionRepositoryProvider).saveDraft(updated);
    ref.read(currentQuestionProvider.notifier).state = updated;
    invalidateQuestionList(ref);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已归档')),
    );
  }

  Future<void> _unarchive(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) async {
    final updated = question.unarchive();
    await ref.read(questionRepositoryProvider).saveDraft(updated);
    ref.read(currentQuestionProvider.notifier).state = updated;
    invalidateQuestionList(ref);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已取消归档')),
    );
  }

  Future<void> _setMistakeCategory(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
    MistakeCategory? category,
  ) async {
    final updated = question.withMistakeCategory(category);
    await ref.read(questionRepositoryProvider).update(updated);
    ref.read(currentQuestionProvider.notifier).state = updated;
    invalidateQuestionList(ref);
    if (!context.mounted) return;
    final message = category == null ? '已清除错因分类' : '错因已标记为：${category.label}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _markResult(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
    ReviewRating rating,
  ) async {
    final controller = ReviewController(
      repository: ref.read(questionRepositoryProvider),
      logRepository: ref.read(reviewLogRepositoryProvider),
    );
    final updated = switch (rating) {
      ReviewRating.forgot => await controller.markForgot(question.id),
      ReviewRating.hard => await controller.markReviewing(question.id),
      ReviewRating.easy => await controller.markMastered(question.id),
    };
    invalidateQuestionList(ref);
    ref.read(currentQuestionProvider.notifier).state = updated;
    if (!context.mounted) return;
    final message = switch (rating) {
      ReviewRating.forgot => '将在 1 小时后再次复习',
      ReviewRating.hard => '已安排后续复习',
      ReviewRating.easy => '已掌握，复习间隔已延长',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _RecognitionStatusTags extends StatelessWidget {
  const _RecognitionStatusTags({required this.question});
  final QuestionRecord question;

  @override
  Widget build(BuildContext context) {
    final source = question.tags.firstWhere(
      (tag) => tag.startsWith('layout_provider:'),
      orElse: () => '',
    );
    final provider = source.isEmpty ? null : source.substring('layout_provider:'.length);
    // 统一用 QuestionDisplayStatus 推导识别/AI 文案与配色，
    // 与首页、题卡、批量任务保持一致，避免各页面硬编码口径分裂。
    final displayStatus = inferQuestionDisplayStatus(question);
    final isAwaitingAiConfirmation =
        displayStatus == QuestionDisplayStatus.needsConfirmation;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final recognitionLabel = provider ??
        (question.imagePath.isNotEmpty ? '已识别' : '未识别');
    // 学习状态标签与 _MasteryTag 共用同一套口径（文案 + 颜色），
    // 避免顶部摘要与状态徽章行的学习标签文本/颜色不一致。
    final learningLabel = '学习：${_masteryLabel(question.masteryLevel)}';
    final learningColor = _masteryColor(context, question.masteryLevel);
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: <Widget>[
        AppTag(
          label: '识别：$recognitionLabel',
          textColor: displayStatus.isFailed
              ? AppColors.danger
              : AppColors.successDark,
          backgroundColor: displayStatus.isFailed
              ? (isDark
                  ? AppColors.danger.withValues(alpha: 0.24)
                  : AppColors.dangerContainerLight)
              : (isDark
                  ? AppColors.success.withValues(alpha: 0.24)
                  : AppColors.successContainerLight),
        ),
        AppTag(
          label: isAwaitingAiConfirmation
              ? 'AI：待确认'
              : displayStatus == QuestionDisplayStatus.analyzed
                  ? 'AI：已分析'
                  : (displayStatus == QuestionDisplayStatus.analysisFailed
                      ? 'AI：分析失败'
                      : 'AI：未分析'),
          textColor: isAwaitingAiConfirmation
              ? AppColors.warningDark
              : displayStatus == QuestionDisplayStatus.analyzed
                  ? AppColors.primaryDark
                  : (displayStatus == QuestionDisplayStatus.analysisFailed
                      ? AppColors.danger
                      : AppColors.slate),
          backgroundColor: isAwaitingAiConfirmation
              ? (isDark
                  ? AppColors.warning.withValues(alpha: 0.24)
                  : AppColors.warningContainerLight)
              : displayStatus == QuestionDisplayStatus.analyzed
                  ? (isDark
                      ? AppColors.primary.withValues(alpha: 0.24)
                      : AppColors.primaryContainerLight)
                  : (displayStatus == QuestionDisplayStatus.analysisFailed
                      ? (isDark
                          ? AppColors.danger.withValues(alpha: 0.24)
                          : AppColors.dangerContainerLight)
                      : (isDark
                          ? AppColors.slate.withValues(alpha: 0.24)
                          : AppColors.slateContainerLight)),
        ),
        AppTag(
          label: learningLabel,
          textColor: isDark ? Theme.of(context).colorScheme.onSurface : learningColor,
          backgroundColor: learningColor.withValues(alpha: isDark ? 0.16 : 0.1),
        ),
      ],
    );
  }
}

class _QuestionTab extends StatelessWidget {
  const _QuestionTab({
    required this.current,
    required this.editing,
    required this.batchGroup,
    required this.showFullImage,
    required this.onReselectImage,
    required this.onToggleFavorite,
    required this.onEditSource,
    required this.onEditLearningContext,
    required this.onSelectSibling,
    required this.onAddTag,
    required this.onEditReflection,
    required this.onEditStudentAnswer,
    required this.onEditExpectedAnswer,
    required this.onGradeAnswer,
  });

  final QuestionRecord current;
  final bool editing;
  final QuestionBatchGroup? batchGroup;
  /// 放大查看原图。第二个参数为原图文件名，可为空。
  final void Function(String path, String? filename) showFullImage;
  /// 重新选图入口，由详情页 state 提供。
  /// 缩略图/放大态附件加载失败时，让用户重新绑定原图。
  final VoidCallback onReselectImage;
  final VoidCallback onToggleFavorite;
  final VoidCallback onEditSource;
  final VoidCallback onEditLearningContext;
  final void Function(QuestionRecord) onSelectSibling;
  final VoidCallback onAddTag;
  final VoidCallback onEditReflection;
  final VoidCallback onEditStudentAnswer;
  final VoidCallback onEditExpectedAnswer;
  final Future<void> Function() onGradeAnswer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = current.analysisResult;

    return ListView(
      padding: const EdgeInsets.all(AppSpace.md),
      children: <Widget>[
        if (_statusBanner(context, current) != null) ...<Widget>[
          _statusBanner(context, current)!,
          const SizedBox(height: AppSpace.md),
        ],
        AppCard(
          borderRadius: AppRadius.large,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: <Widget>[
                  AppTag(
                    label: current.subject.label,
                    useThemeTone: true,
                    themeTone: AppTagTone.primary,
                  ),
                  if (current.questionType != null)
                    AppTag(
                      label: current.questionType!.label,
                      useThemeTone: true,
                      themeTone: AppTagTone.secondary,
                    ),
                  if (result?.subject != null)
                    AppTag(
                      label: 'AI识别',
                      useThemeTone: true,
                      themeTone: AppTagTone.success,
                    ),
                  _MasteryTag(current: current),
                  _RecognitionStatusTags(question: current),
                  if (_batchLabel(current) != null)
                    AppTag(
                      label: _batchLabel(current)!,
                      useThemeTone: true,
                      themeTone: AppTagTone.neutral,
                    ),
                  if (current.source != null)
                    AppTag(
                      label: current.source!,
                      useThemeTone: true,
                      themeTone: AppTagTone.success,
                    ),
                ],
              ),
              if (current.aiTags.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpace.md),
                Text('AI标签',
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.onSurfaceVariant)),
                const SizedBox(height: AppSpace.xs),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  children: current.aiTags
                      .map((tag) => AppTag(
                            label: tag,
                            useThemeTone: true,
                            themeTone: AppTagTone.tertiary,
                          ))
                      .toList(),
                ),
              ],
              if (current.customTags.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpace.md),
                Text('自定义标签',
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.onSurfaceVariant)),
                const SizedBox(height: AppSpace.xs),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  children: current.customTags
                      .map((t) => AppTag(
                            label: t,
                            useThemeTone: true,
                            themeTone: AppTagTone.primary,
                          ))
                      .toList(),
                ),
              ],
              if (editing) ...<Widget>[
                const SizedBox(height: AppSpace.md),
                _AddTagButton(onTap: onAddTag),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        _LearningProfileGrid(
          question: current,
          editing: editing,
          onToggleFavorite: onToggleFavorite,
          onEditSource: onEditSource,
          onEditLearningContext: onEditLearningContext,
        ),
        if (batchGroup != null) ...<Widget>[
          const SizedBox(height: AppSpace.md),
          _BatchSiblingCard(
            current: current,
            group: batchGroup!,
            onSelect: onSelectSibling,
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        _buildOriginalQuestion(context, isDark, colorScheme),
        const SizedBox(height: AppSpace.lg),
        _OcrContentCard(question: current),
        const SizedBox(height: AppSpace.lg),
        if (current.studentAnswer != null &&
            current.studentAnswer!.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpace.lg),
          _StudentAnswerCard(
            answer: current.studentAnswer!,
            contentFormat: current.contentFormat,
            onEdit: onEditStudentAnswer,
          ),
          const SizedBox(height: AppSpace.lg),
          _ExpectedAnswerCard(
            expectedAnswer: current.expectedAnswer,
            studentAnswer: current.studentAnswer,
            isCorrect: current.isCorrect,
            contentFormat: current.contentFormat,
            onEdit: onEditExpectedAnswer,
            onGrade: onGradeAnswer,
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        _ReflectionNoteCard(
          note: current.reflectionNote,
          onEdit: onEditReflection,
        ),
      ],
    );
  }

  String? _batchLabel(QuestionRecord question) {
    if (question.parentQuestionId == null && question.rootQuestionId == null) {
      return null;
    }
    final order = question.splitOrder;
    return order == null ? '拍照批次' : '拍照批次 · 第 $order 题';
  }

  Widget _buildOriginalQuestion(BuildContext context, bool isDark, ColorScheme colorScheme) {
    return AppInfoSection(
      icon: CupertinoIcons.doc_text,
      title: AppStrings.detailOriginalQuestion,
      useThemeTone: true,
      themeTone: AppTagTone.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (current.ocrConfidence != null) ...<Widget>[
            ConfidenceBadge(confidence: current.ocrConfidence, compact: true),
            const SizedBox(height: AppSpace.sm),
          ],
          if (current.imagePath.isNotEmpty) ...<Widget>[
            GestureDetector(
              onTap: () => showFullImage(current.imagePath, current.originalImageFilename),
              child: Container(
                height: 160,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: Stack(
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.small),
                      child: SizedBox(
                        width: double.infinity,
                        height: 160,
                        child: CachedQuestionImage(
                          current.imagePath,
                          fit: BoxFit.contain,
                          onReselect: onReselectImage,
                          filename: current.originalImageFilename,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(CupertinoIcons.zoom_in, size: 12, color: Colors.white,
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
                                  ],
                                )),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.md),
          ],
          MathContentView(
            current.correctedText,
            contentFormat: current.contentFormat,
            style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface,
                height: 1.5),
          ),
        ],
      ),
    );
  }

  /// 顶部状态横幅：识别失败 / 附件缺失 / 低置信度。
  /// 只在出现问题时显示，无问题时返回 null 不占空间。
  Widget? _statusBanner(BuildContext context, QuestionRecord question) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final List<Widget> alerts = <Widget>[];

    final displayStatus = inferQuestionDisplayStatus(question);
    if (displayStatus == QuestionDisplayStatus.recognitionFailed) {
      final reason = question.lastAnalysisError;
      alerts.add(_BannerItem(
        icon: CupertinoIcons.exclamationmark_triangle_fill,
        text: reason != null && reason.isNotEmpty
            ? '识别失败：$reason\n原图已保留，可重试或切换识别引擎'
            : '识别失败：已保留原图，可在「分析」页重试或切换识别引擎',
        color: AppColors.danger,
        backgroundColor: isDark ? const Color(0xFF3B1414) : const Color(0xFFFEF2F2),
      ));
    } else if (displayStatus == QuestionDisplayStatus.analysisFailed) {
      final reason = question.lastAnalysisError;
      alerts.add(_BannerItem(
        icon: CupertinoIcons.exclamationmark_triangle_fill,
        text: reason != null && reason.isNotEmpty
            ? 'AI 分析失败：$reason\n已保留原图与校对题干，可重试或切换 AI 引擎'
            : 'AI 分析失败：已保留原图与校对题干，可在「分析」页重试',
        color: AppColors.danger,
        backgroundColor: isDark ? const Color(0xFF3B1414) : const Color(0xFFFEF2F2),
      ));
    } else if (displayStatus == QuestionDisplayStatus.needsConfirmation) {
      final fields = question.analysisResult?.reviewDecision.fields ?? const <String>[];
      alerts.add(_BannerItem(
        icon: CupertinoIcons.exclamationmark_shield,
        text: fields.isEmpty
            ? 'AI 结果待人工确认，确认前不会进入复习计划'
            : 'AI 结果待确认：${fields.join('、')}。确认前不会进入复习计划',
        color: AppColors.warningDark,
        backgroundColor: isDark
            ? AppColors.warning.withValues(alpha: 0.18)
            : AppColors.warningContainerLight,
      ));
    } else if (displayStatus == QuestionDisplayStatus.recognizing ||
        displayStatus == QuestionDisplayStatus.analyzing) {
      alerts.add(_BannerItem(
        icon: CupertinoIcons.hourglass,
        text: displayStatus == QuestionDisplayStatus.recognizing
            ? '识别中：正在识别题目内容'
            : '分析中：AI 正在生成解析',
        color: AppColors.info,
        backgroundColor: isDark ? const Color(0xFF0B1B3A) : const Color(0xFFE0F2FE),
      ));
    }
    if (question.imagePath.isEmpty) {
      alerts.add(_BannerItem(
        icon: CupertinoIcons.photo,
        text: '附件缺失：未保存原图，仅保留识别文本与 AI 分析',
        color: AppColors.danger,
        backgroundColor: isDark ? const Color(0xFF3B1414) : const Color(0xFFFEF2F2),
      ));
    } else if (question.ocrConfidence != null && question.ocrConfidence! < 0.7) {
      alerts.add(_BannerItem(
        icon: CupertinoIcons.exclamationmark_shield_fill,
        text: '识别置信度较低（${(question.ocrConfidence! * 100).round()}%），建议校对题干与公式',
        color: const Color(0xFFB45309),
        backgroundColor: isDark ? const Color(0xFF2D1B0E) : const Color(0xFFFFFBEB),
      ));
    }

    if (alerts.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: alerts,
    );
  }
}

/// 顶部状态横幅的单条提醒。
class _BannerItem extends StatelessWidget {
  const _BannerItem({
    required this.icon,
    required this.text,
    required this.color,
    required this.backgroundColor,
  });
  final IconData icon;
  final String text;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm + 2),
      margin: const EdgeInsets.only(bottom: AppSpace.xs),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: color, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

/// OCR 识别内容对照卡片：展示原文 vs 校对后内容 + 结构化公式与表格。
///
/// QuestionRecord 未对 formulas/tables/options 做结构化建模，这里从
/// normalizedQuestionText 中用正则提取（与 worksheet_region_editor_screen
/// 的 _formulasFor/_tablesFor 保持一致），在详情页提供与识别工作台对照的视图。
class _OcrContentCard extends StatelessWidget {
  const _OcrContentCard({required this.question});
  final QuestionRecord question;

  List<String> _extractFormulas(String text) {
    return RegExp(r'\$[^$]+\$').allMatches(text).map((m) => m.group(0)!).toList();
  }

  List<String> _extractTables(String text) {
    final lines = text.split('\n').where((line) => line.trimLeft().startsWith('|')).toList();
    if (lines.isEmpty) return const <String>[];
    // 按空行分段，每段为一个表格
    final tables = <String>[];
    var current = <String>[];
    for (final line in lines) {
      current.add(line);
    }
    if (current.isNotEmpty) tables.add(current.join('\n'));
    return tables;
  }

  /// 从校对文本中提取选项行。
  /// 支持 `A. xxx`、`A) xxx`、`(A) xxx`、`A、xxx` 等格式。
  /// 不区分大小写，字母限定 A-F（覆盖 90% 以上题目）。
  List<String> _extractOptions(String text) {
    final regex = RegExp(r'^\s*[\(]?([A-Fa-f])[\).、]\s+(.+)$');
    final options = <String>[];
    for (final line in text.split('\n')) {
      final match = regex.firstMatch(line);
      if (match != null) {
        options.add('${match.group(1)!.toUpperCase()}. ${match.group(2)}');
      }
    }
    // 至少 2 条才算选项，避免误把单行 "A. 苹果" 当选项
    return options.length >= 2 ? options : const <String>[];
  }

  /// 检测题干中是否包含图形相关关键词，给出图形识别状态提示。
  /// 返回 null 表示无图形相关内容；返回字符串为状态描述。
  String? _detectFigureStatus(String text) {
    final keywords = <String>[
      '如图', '下图', '上图', '图所示', '图①', '图②', '图③', '图 1', '图 2',
      '几何图', '坐标系', '数轴', '函数图象', '函数图像', '示意图',
      '△', '∠', '⊙', '▱', '梯形', '矩形', '正方形', '圆',
    ];
    final lower = text.toLowerCase();
    for (final kw in keywords) {
      if (lower.contains(kw.toLowerCase())) {
        return '题干含图形相关描述（关键词：$kw）。当前仅识别文字，'
            '图形细节请对照原图核对；AI 分析会基于原图做视觉推断。';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final original = question.extractedQuestionText;
    final corrected = question.normalizedQuestionText;
    final aiReconstructed = question.aiReconstructedText;
    final hasDiff = original != corrected && original.isNotEmpty;
    final formulas = _extractFormulas(corrected);
    final tables = _extractTables(corrected);
    final options = _extractOptions(corrected);
    final figureNote = _detectFigureStatus(corrected);

    // 若原文与校对后一致且无结构化内容、无 AI 重构，不显示空卡片
    if (!hasDiff &&
        formulas.isEmpty &&
        tables.isEmpty &&
        options.isEmpty &&
        figureNote == null &&
        (aiReconstructed == null || aiReconstructed.isEmpty)) {
      return const SizedBox.shrink();
    }

    return AppInfoSection(
      icon: CupertinoIcons.arrow_left_right,
      title: 'OCR 识别内容对照',
      iconColor: AppColors.info,
      backgroundColor: isDark ? colorScheme.surface : AppColors.infoContainerLight,
      borderColor: isDark ? AppColors.info.withValues(alpha: 0.28) : const Color(0xFFBAE6FD),
      titleColor: AppColors.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (hasDiff) ...<Widget>[
            Text('识别原文',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: AppSpace.xs),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: Text(original,
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant, height: 1.4),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(height: AppSpace.md),
            Text('校对后',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: AppSpace.xs),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.small),
                border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
              ),
              child: MathContentView(
                corrected,
                contentFormat: question.contentFormat,
                style: TextStyle(fontSize: 12, color: colorScheme.onSurface, height: 1.4),
              ),
            ),
          ] else ...<Widget>[
            MathContentView(
              corrected,
              contentFormat: question.contentFormat,
              style: TextStyle(fontSize: 12, color: colorScheme.onSurface, height: 1.4),
            ),
          ],
          if (aiReconstructed != null && aiReconstructed.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpace.md),
            Text('AI 重构题干',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success)),
            const SizedBox(height: AppSpace.xs),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.success.withValues(alpha: 0.12)
                    : AppColors.successContainerLight,
                borderRadius: BorderRadius.circular(AppRadius.small),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: MathContentView(
                aiReconstructed,
                contentFormat: QuestionContentFormat.latexMixed,
                style: TextStyle(fontSize: 12, color: isDark ? colorScheme.onSurface : AppColors.successDark, height: 1.4),
              ),
            ),
          ],
          if (formulas.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpace.md),
            Text('公式（${formulas.length}）',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: AppSpace.xs),
            ...formulas.map((item) => Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: MathContentView(
                      item,
                      contentFormat: QuestionContentFormat.latexMixed,
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
                    ),
                  ),
                )),
          ],
          if (tables.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpace.md),
            Text('表格（${tables.length}）',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: AppSpace.xs),
            ...tables.map((table) => Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: _MarkdownTablePreview(source: table),
                )),
          ],
          if (options.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpace.md),
            Text('选项（${options.length}）',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: AppSpace.xs),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: options
                    .map((opt) => Padding(
                          padding: const EdgeInsets.only(top: 2, bottom: 2),
                          child: MathContentView(
                            opt,
                            contentFormat: question.contentFormat,
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
          if (figureNote != null) ...<Widget>[
            const SizedBox(height: AppSpace.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.accentAmber.withValues(alpha: 0.12)
                    : AppColors.accentAmberContainerLight,
                borderRadius: BorderRadius.circular(AppRadius.small),
                border: Border.all(color: AppColors.accentAmber.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(CupertinoIcons.photo, size: 14, color: AppColors.accentAmber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      figureNote,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? colorScheme.onSurface : const Color(0xFF92400E),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Markdown 表格预览：把 `|` 分隔的文本渲染成 Table widget。
///
/// 与 worksheet_region_editor_screen 的 _MarkdownTablePreview 行为一致，
/// 详情页用于展示从 normalizedQuestionText 提取的表格段。
class _MarkdownTablePreview extends StatelessWidget {
  const _MarkdownTablePreview({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final rows = source.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (rows.isEmpty) return const SizedBox.shrink();

    // 第二行若是分隔行（|---|---|），跳过渲染但保留列对齐
    final hasSeparator = rows.length >= 2 &&
        RegExp(r'^\s*\|?[\s\-:|]+\|?\s*$').hasMatch(rows[1]) &&
        rows[1].contains('-');
    final dataRows = hasSeparator
        ? <String>[rows[0], ...rows.sublist(2)]
        : rows;

    List<String> splitRow(String line) {
      var s = line.trim();
      if (s.startsWith('|')) s = s.substring(1);
      if (s.endsWith('|')) s = s.substring(0, s.length - 1);
      return s.split('|').map((c) => c.trim()).toList();
    }

    final parsed = dataRows.map(splitRow).toList();
    if (parsed.isEmpty) return const SizedBox.shrink();
    final colCount = parsed.map((r) => r.length).reduce((a, b) => a > b ? a : b);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder(
            horizontalInside: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              width: 0.5,
            ),
            verticalInside: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              width: 0.5,
            ),
          ),
          children: parsed.asMap().entries.map((entry) {
            final isHeader = entry.key == 0;
            final cells = List<String>.generate(colCount,
                (i) => i < entry.value.length ? entry.value[i] : '');
            return TableRow(
              children: cells
                  .map((c) => Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.sm, vertical: 4),
                        child: MathContentView(
                          c,
                          contentFormat: QuestionContentFormat.latexMixed,
                          style: TextStyle(
                            fontSize: 12,
                            color: isHeader
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                            fontWeight:
                                isHeader ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ))
                  .toList(),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ReflectionNoteCard extends StatelessWidget {
  const _ReflectionNoteCard({required this.note, required this.onEdit});

  final String? note;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasNote = note != null && note!.isNotEmpty;

    return AppInfoSection(
      icon: CupertinoIcons.pencil_ellipsis_rectangle,
      title: '学习反思',
      useThemeTone: true,
      themeTone: AppTagTone.primary,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: GestureDetector(
              onTap: onEdit,
              child: hasNote
                  ? Text(
                      note!,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: colorScheme.onSurface,
                      ),
                    )
                  : Text(
                      '点此添加学习反思…',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          IconButton(
            icon: const Icon(CupertinoIcons.pencil, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: '编辑学习反思',
            color: colorScheme.onSurfaceVariant,
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

class _StudentAnswerCard extends StatelessWidget {
  const _StudentAnswerCard({
    required this.answer,
    required this.contentFormat,
    required this.onEdit,
  });

  final String answer;
  final QuestionContentFormat contentFormat;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppInfoSection(
      icon: CupertinoIcons.doc_richtext,
      title: '我的答案',
      useThemeTone: true,
      themeTone: AppTagTone.secondary,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: MathContentView(
              answer,
              contentFormat: contentFormat,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          IconButton(
            icon: const Icon(CupertinoIcons.pencil, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: '编辑我的答案',
            color: colorScheme.onSurfaceVariant,
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

/// 标准答案卡片，附带 AI 判分入口与判分结果徽章。
///
/// 仅当题目已有学生作答时显示（判分才有意义），由父组件控制显示条件。
class _ExpectedAnswerCard extends StatefulWidget {
  const _ExpectedAnswerCard({
    required this.expectedAnswer,
    required this.studentAnswer,
    required this.isCorrect,
    required this.contentFormat,
    required this.onEdit,
    required this.onGrade,
  });

  final String? expectedAnswer;
  final String? studentAnswer;
  final bool? isCorrect;
  final QuestionContentFormat contentFormat;
  final VoidCallback onEdit;
  final Future<void> Function() onGrade;

  @override
  State<_ExpectedAnswerCard> createState() => _ExpectedAnswerCardState();
}

class _ExpectedAnswerCardState extends State<_ExpectedAnswerCard> {
  bool _grading = false;

  Future<void> _handleGrade() async {
    if (_grading) return;
    setState(() => _grading = true);
    try {
      await widget.onGrade();
    } finally {
      if (mounted) {
        setState(() => _grading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasAnswer =
        widget.expectedAnswer != null && widget.expectedAnswer!.isNotEmpty;

    return AppInfoSection(
      icon: CupertinoIcons.checkmark_seal,
      title: '标准答案',
      iconColor: AppColors.primary,
      backgroundColor: AppColors.primaryContainerLight,
      borderColor: const Color(0xFFC7D2FE),
      titleColor: AppColors.primaryDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: hasAnswer
                    ? MathContentView(
                        widget.expectedAnswer!,
                        contentFormat: widget.contentFormat,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: colorScheme.onSurface,
                        ),
                      )
                    : GestureDetector(
                        onTap: widget.onEdit,
                        child: Text(
                          '点此填写标准答案，用于 AI 判分…',
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: AppSpace.sm),
              IconButton(
                icon: const Icon(CupertinoIcons.pencil, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: '编辑标准答案',
                color: colorScheme.onSurfaceVariant,
                onPressed: widget.onEdit,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: <Widget>[
              if (widget.isCorrect != null) ...<Widget>[
                _buildCorrectnessBadge(widget.isCorrect!),
                const SizedBox(width: AppSpace.sm),
                OutlinedButton.icon(
                  onPressed: _grading ? null : _handleGrade,
                  icon: _grading
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(CupertinoIcons.arrow_2_circlepath,
                          size: 14),
                  label: Text(_grading ? '判分中' : '重新判分'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ] else
                FilledButton.icon(
                  onPressed: _grading ? null : _handleGrade,
                  icon: _grading
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(CupertinoIcons.sparkles, size: 14),
                  label: Text(_grading ? '判分中…' : 'AI 判分'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCorrectnessBadge(bool isCorrect) {
    final color =
        isCorrect ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            isCorrect
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.xmark_circle_fill,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            isCorrect ? '判分正确' : '判分错误',
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _MasteryTag extends StatelessWidget {
  const _MasteryTag({required this.current});

  final QuestionRecord current;

  @override
  Widget build(BuildContext context) {
    final color = _masteryColor(context, current.masteryLevel);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppTag(
      label: _masteryLabel(current.masteryLevel),
      textColor: isDark ? Theme.of(context).colorScheme.onSurface : color,
      backgroundColor: color.withValues(alpha: isDark ? 0.16 : 0.1),
    );
  }
}

String _masteryLabel(MasteryLevel level) {
  switch (level) {
    case MasteryLevel.newQuestion:
      return '待复习';
    case MasteryLevel.reviewing:
      return '复习中';
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

class _AddTagButton extends StatelessWidget {
  const _AddTagButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.small),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.small),
          border: Border.all(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(CupertinoIcons.plus, size: 14, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text('添加标签',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _LearningProfileGrid extends StatelessWidget {
  const _LearningProfileGrid({
    required this.question,
    required this.editing,
    this.onToggleFavorite,
    this.onEditSource,
    this.onEditLearningContext,
  });

  final QuestionRecord question;
  final bool editing;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onEditSource;
  final VoidCallback? onEditLearningContext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final category = question.mistakeCategory?.label ?? '未分类';
    final nextReview = question.nextReviewAt == null
        ? '待安排'
        : _formatProfileDate(question.nextReviewAt!);

    final items = <_ProfileData>[
      _ProfileData(
          icon: CupertinoIcons.exclamationmark_triangle,
          label: '错因',
          value: category),
      _ProfileData(
          icon: CupertinoIcons.list_bullet,
          label: '题型',
          value: question.questionType?.label ?? '未设置',
          isAction: editing,
          onTap: onEditLearningContext),
      _ProfileData(
          icon: CupertinoIcons.clock,
          label: '下次复习',
          value: nextReview),
      _ProfileData(
          icon: question.isFavorite ? CupertinoIcons.star_fill : CupertinoIcons.star,
          label: '收藏',
          value: question.isFavorite ? '已收藏' : '未收藏',
          isAction: editing,
          onTap: onToggleFavorite),
      _ProfileData(
          icon: CupertinoIcons.folder,
          label: '来源',
          value: question.source ?? '未设置',
          isAction: editing,
          onTap: onEditSource),
      _ProfileData(
          icon: CupertinoIcons.person_crop_circle,
          label: '学习阶段',
          value: question.learningStage ?? '未设置',
          isAction: editing,
          onTap: onEditLearningContext),
      if (question.difficulty != null)
        _ProfileData(
            icon: CupertinoIcons.chart_bar,
            label: '层级',
            value: _difficultyLabel(question.difficulty!)),
      if (question.attemptStatus != null)
        _ProfileData(
            icon: CupertinoIcons.pencil_ellipsis_rectangle,
            label: '作答',
            value: _attemptStatusLabel(question.attemptStatus!)),
    ];

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      borderRadius: AppRadius.large,
      backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(AppStrings.detailLearningProfile,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpace.md),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: AppSpace.sm,
            crossAxisSpacing: AppSpace.sm,
            childAspectRatio: 2.8,
            children: items.map((item) => _ProfileTile(data: item)).toList(),
          ),
        ],
      ),
    );
  }
}

class _ProfileData {
  const _ProfileData({
    required this.icon,
    required this.label,
    required this.value,
    this.isAction = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isAction;
  final VoidCallback? onTap;
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.data});

  final _ProfileData data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: <Widget>[
          Icon(data.icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(data.label,
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.onSurfaceVariant)),
                Text(data.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface)),
              ],
            ),
          ),
          if (data.isAction)
            Icon(CupertinoIcons.pencil,
                size: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
        ],
      ),
    );

    if (!data.isAction || data.onTap == null) return child;
    return InkWell(
      onTap: data.onTap,
      borderRadius: BorderRadius.circular(AppRadius.small),
      child: child,
    );
  }
}

/// AI 分析输入快照：展示当时发给 AI 的题干文本与原图可用性，
/// 让用户清楚 AI 是基于什么材料得出的结论。
///
/// 由于 QuestionRecord 没有持久化"AI 输入文本/是否用图"字段，这里
/// 从现有字段推断：
/// - 输入文本：默认文字模式用 `normalizedQuestionText`（校对后），
///   视觉模式用 `extractedQuestionText`（OCR 原文）。两者一致时只展示一段。
/// - 原图可用性：检查 imagePath 非空且文件存在。
/// - AI 重构：若 `aiReconstructedText` 非空，提示 AI 重写了题干。
class _AiInputSnapshotCard extends StatelessWidget {
  const _AiInputSnapshotCard({required this.question});

  final QuestionRecord question;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final corrected = question.normalizedQuestionText;
    final original = question.extractedQuestionText;
    final aiReconstructed = question.aiReconstructedText;
    final hasImage = question.imagePath.isNotEmpty &&
        File(question.imagePath).existsSync();
    final sameText = original == corrected;

    return AppInfoSection(
      icon: CupertinoIcons.doc_text_search,
      title: 'AI 分析输入',
      iconColor: AppColors.slate,
      backgroundColor: isDark ? colorScheme.surface : AppColors.slateContainerLight,
      borderColor: isDark
          ? AppColors.slate.withValues(alpha: 0.28)
          : const Color(0xFFCBD5E1),
      titleColor: AppColors.slate,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 输入模式标签
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: <Widget>[
              _SnapshotChip(
                label: hasImage ? '原图可用' : '无原图',
                icon: hasImage
                    ? CupertinoIcons.photo
                    : CupertinoIcons.photo,
                color: hasImage ? AppColors.success : AppColors.danger,
              ),
              _SnapshotChip(
                label: sameText ? '文字模式（校对文本）' : '视觉模式（OCR 原文）',
                icon: CupertinoIcons.textformat,
                color: AppColors.info,
              ),
              if (aiReconstructed != null && aiReconstructed.isNotEmpty)
                _SnapshotChip(
                  label: 'AI 已重构题干',
                  icon: CupertinoIcons.wand_stars,
                  color: AppColors.accentAmber,
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          // 输入文本：默认展示校对文本；若与原文不一致，额外展示原文
          Text('发送给 AI 的题干',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: AppSpace.xs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: MathContentView(
              sameText ? corrected : original,
              contentFormat: question.contentFormat,
              style: TextStyle(fontSize: 12, color: colorScheme.onSurface, height: 1.4),
            ),
          ),
          if (!sameText) ...<Widget>[
            const SizedBox(height: AppSpace.xs),
            Text('（视觉模式同时发送原图与 OCR 原文）',
                style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: colorScheme.onSurfaceVariant)),
          ],
          if (aiReconstructed != null && aiReconstructed.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpace.md),
            Text('AI 重构后的题干',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentAmber)),
            const SizedBox(height: AppSpace.xs),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.accentAmber.withValues(alpha: 0.12)
                    : AppColors.accentAmberContainerLight,
                borderRadius: BorderRadius.circular(AppRadius.small),
                border: Border.all(
                    color: AppColors.accentAmber.withValues(alpha: 0.3)),
              ),
              child: MathContentView(
                aiReconstructed,
                contentFormat: QuestionContentFormat.latexMixed,
                style: TextStyle(
                    fontSize: 12,
                    color: isDark ? colorScheme.onSurface : const Color(0xFF92400E),
                    height: 1.4),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SnapshotChip extends StatelessWidget {
  const _SnapshotChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisTab extends StatelessWidget {
  const _AnalysisTab({
    required this.current,
    required this.result,
    required this.onSetCategory,
    required this.onAddAnalysis,
  });

  final QuestionRecord current;
  final AnalysisResult? result;
  final ValueChanged<MistakeCategory?> onSetCategory;
  final VoidCallback onAddAnalysis;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (result == null) {
      final displayStatus = inferQuestionDisplayStatus(current);
      final isAnalysisFailed =
          displayStatus == QuestionDisplayStatus.analysisFailed;
      final isRecognitionFailed =
          displayStatus == QuestionDisplayStatus.recognitionFailed;
      final hasError = current.lastAnalysisError != null &&
          current.lastAnalysisError!.isNotEmpty;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.md),
        child: AppCard(
          child: Column(
            children: <Widget>[
              Icon(
                  isAnalysisFailed || isRecognitionFailed
                      ? CupertinoIcons.exclamationmark_triangle
                      : CupertinoIcons.sparkles,
                  size: 40,
                  color: (isAnalysisFailed || isRecognitionFailed
                          ? AppColors.danger
                          : colorScheme.onSurface)
                      .withValues(alpha: 0.6)),
              const SizedBox(height: AppSpace.md),
              Text(
                isAnalysisFailed
                    ? (hasError
                        ? 'AI 分析失败：${current.lastAnalysisError}\n已保留原图与校对题干，可重试或切换 AI 引擎'
                        : 'AI 分析失败：已保留原图与校对题干，可重试')
                    : isRecognitionFailed
                        ? (hasError
                            ? '识别失败：${current.lastAnalysisError}\n原图已保留，可重试或切换识别引擎'
                            : '识别失败：原图已保留，可重试')
                        : '当前已保存识别结果，可继续交给普通 AI 完成答案、错因、知识点和练习分析。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: (isAnalysisFailed || isRecognitionFailed)
                      ? AppColors.danger
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              FilledButton.icon(
                onPressed: onAddAnalysis,
                icon: Icon(
                    isAnalysisFailed || isRecognitionFailed
                        ? CupertinoIcons.arrow_2_circlepath
                        : CupertinoIcons.camera,
                    size: 18),
                label: Text(isAnalysisFailed || isRecognitionFailed
                    ? '重试 AI 解析'
                    : '去添加'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpace.md),
      children: <Widget>[
        AppInfoSection(
          icon: CupertinoIcons.scope,
          title: '错误定位',
          iconColor: AppColors.warning,
          backgroundColor: AppColors.warningContainerLight,
          borderColor: AppColors.warning,
          titleColor: AppColors.warningDark,
          child: MathContentView(
            result!.mistakeReason,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? colorScheme.onSurface : AppColors.warningDark,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        AppInfoSection(
          icon: result!.visualAssumptionStatus == VisualAssumptionStatus.needsReview
              ? CupertinoIcons.exclamationmark_triangle
              : CupertinoIcons.checkmark_circle,
          title: result!.visualAssumptionStatus == VisualAssumptionStatus.needsReview
              ? AppStrings.detailPossibleAnswer
              : AppStrings.detailCorrectAnswer,
          iconColor: result!.visualAssumptionStatus == VisualAssumptionStatus.needsReview
              ? AppColors.warning
              : AppColors.success,
          backgroundColor: result!.visualAssumptionStatus == VisualAssumptionStatus.needsReview
              ? AppColors.warningContainerLight
              : AppColors.successContainerLight,
          borderColor: result!.visualAssumptionStatus == VisualAssumptionStatus.needsReview
              ? const Color(0xFFFED7AA)
              : const Color(0xFFBBF7D0),
          titleColor: result!.visualAssumptionStatus == VisualAssumptionStatus.needsReview
              ? AppColors.warningDark
              : AppColors.successDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              MathContentView(
                result!.finalAnswer,
                style: TextStyle(
                    fontSize: 14,
                    color: isDark ? colorScheme.onSurface : AppColors.successDark,
                    fontWeight: FontWeight.w600),
              ),
              if (_consistencyNotice(result!) != null) ...<Widget>[
                const SizedBox(height: AppSpace.md),
                _ConsistencyNotice(notice: _consistencyNotice(result!)!),
              ],
            ],
          ),
        ),

        const SizedBox(height: AppSpace.md),
        _MistakeCategoryCard(
          selected: current.mistakeCategory,
          onChanged: onSetCategory,
        ),
        const SizedBox(height: AppSpace.md),
        AppInfoSection(
          icon: CupertinoIcons.lightbulb,
          title: AppStrings.detailStudyAdvice,
          iconColor: AppColors.accentAmber,
          backgroundColor: AppColors.accentAmberContainerLight,
          borderColor: const Color(0xFFFDE68A),
          titleColor: const Color(0xFF92400E),
          collapsible: true,
          initiallyExpanded: false,
          child: MathContentView(
            result!.studyAdvice,
            style: TextStyle(
                fontSize: 14,
                color: isDark ? colorScheme.onSurface : const Color(0xFFB45309),
                height: 1.5),
          ),
        ),
        if (result!.knowledgePoints.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpace.lg),
          AppSectionTitle(AppStrings.detailKnowledgePoints,
              padding: const EdgeInsets.only(bottom: AppSpace.md)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: result!.knowledgePoints.map((p) => _KnowledgePointItem(text: p)).toList(),
          ),
        ],
        // Phase 6-3：结构化知识点关联区（主知识点 + 关联列表 + 添加/操作）
        _StructuredKnowledgeLinksCard(questionId: current.id),
        // Phase 4-C：待确认知识点（AI 返回但未匹配到受控节点的文本）
        _PendingKnowledgePointsCard(questionId: current.id),
        if (result!.steps.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpace.md),
          AppInfoSection(
            icon: CupertinoIcons.list_number,
            title: AppStrings.detailSolutionSteps,
            collapsible: true,
            initiallyExpanded: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: result!.steps
                  .asMap()
                  .entries
                  .map((e) => _SolutionStepItem(index: e.key, text: e.value))
                  .toList(),
            ),
          ),
        ],
        // AI 输入快照放在最末尾：让用户先看 AI 结论，再向下滚动审计输入材料。
        // 不放在顶部是为了不把已有的答案/知识点挤出首屏，避免回归测试与
        // 已有的视觉布局被迫调整。
        const SizedBox(height: AppSpace.lg),
        _AiInputSnapshotCard(question: current),
      ],
    );
  }

  _ConsistencyNoticeData? _consistencyNotice(AnalysisResult result) {
    switch (result.consistencyStatus) {
      case AnalysisConsistencyStatus.repaired:
        if (result.visualAssumptionStatus == VisualAssumptionStatus.needsReview) {
          return _ConsistencyNoticeData(
            text: result.consistencyNote.isNotEmpty
                ? result.consistencyNote
                : 'AI 已复核答案；图中关键标注含义仍需核对',
            icon: CupertinoIcons.exclamationmark_triangle,
            color: AppColors.warning,
            background: AppColors.warningContainerLight,
          );
        }
        return const _ConsistencyNoticeData(
          text: 'AI 已复核并修正答案',
          icon: CupertinoIcons.checkmark_shield,
          color: AppColors.success,
          background: Color(0xFFEFFDF5),
        );
      case AnalysisConsistencyStatus.needsReview:
        if (result.visualAssumptionStatus == VisualAssumptionStatus.needsReview) {
          return _ConsistencyNoticeData(
            text: result.consistencyNote.isNotEmpty
                ? result.consistencyNote
                : '图中关键标注含义需核对，当前为可能解法',
            icon: CupertinoIcons.exclamationmark_triangle,
            color: AppColors.warning,
            background: AppColors.warningContainerLight,
          );
        }
        return const _ConsistencyNoticeData(
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
}

class _KnowledgePointItem extends StatelessWidget {
  const _KnowledgePointItem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surface : AppColors.primaryContainerLight,
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(
          color: isDark ? colorScheme.outlineVariant : const Color(0xFFC7D2FE),
        ),
      ),
      child: MathContentView(
        text,
        style: TextStyle(
            fontSize: 12,
            height: 1.45,
            color: isDark ? colorScheme.onSurface : AppColors.primaryDark),
      ),
    );
  }
}

/// Phase 6-3：结构化知识点关联区。
///
/// 渲染当前题目已绑定的受控知识点关联列表：
/// - 主知识点（[QuestionKnowledgeLink.isPrimary] 为 true）：名称 + 掌握度
///   徽章 + 「在知识树中查看」入口，长按菜单可「取消主知识点」或「移除」。
/// - 关联知识点：名称 + 掌握度，长按菜单可「设为主知识点」或「移除」。
/// - 「+ 添加关联知识点」按钮：弹 [_KnowledgePointPickerDialog] 选择。
///
/// 数据来自 [structuredKnowledgeLinksProvider]，关联变更后通过
/// [invalidateQuestionList] 自动刷新。
class _StructuredKnowledgeLinksCard extends ConsumerWidget {
  const _StructuredKnowledgeLinksCard({required this.questionId});

  final String questionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linksAsync =
        ref.watch(structuredKnowledgeLinksProvider(questionId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: AppSpace.lg),
        Row(
          children: <Widget>[
            const Icon(CupertinoIcons.link, size: 18),
            const SizedBox(width: AppSpace.sm),
            const Text('知识点关联',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _addKnowledgePoint(context, ref),
              icon: const Icon(CupertinoIcons.add, size: 16),
              label: const Text('添加',
                  style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        linksAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpace.lg),
            child: Center(child: Text('加载中…')),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
            child: Text(
              '加载失败：$e',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          data: (views) {
            if (views.isEmpty) {
              return AppCard(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Column(
                  children: <Widget>[
                    Icon(
                      CupertinoIcons.tag,
                      size: 28,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      '尚未关联知识点，点击右上角"添加"绑定',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }
            // 主知识点排第一
            final sorted = List<StructuredKnowledgeLinkView>.from(views)
              ..sort((a, b) {
                if (a.isPrimary != b.isPrimary) {
                  return a.isPrimary ? -1 : 1;
                }
                return a.knowledgePoint.name
                    .compareTo(b.knowledgePoint.name);
              });
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: sorted
                  .map((v) => _StructuredKnowledgeLinkRow(
                        view: v,
                        questionId: questionId,
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Future<void> _addKnowledgePoint(BuildContext context, WidgetRef ref) async {
    List<KnowledgePoint> tree;
    try {
      tree = await ref.read(knowledgePointTreeProvider.future);
    } catch (_) {
      tree = const <KnowledgePoint>[];
    }
    if (!context.mounted) return;
    if (tree.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('暂无受控知识点'),
          content: const Text('请先在知识点管理页录入受控知识点，再进行关联。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    final selected = await showDialog<KnowledgePoint>(
      context: context,
      builder: (ctx) => _KnowledgePointPickerDialog(tree: tree),
    );
    if (selected == null) return;

    final linkRepo = ref.read(questionKnowledgeLinkRepositoryProvider);
    try {
      final existing =
          await linkRepo.linksForQuestion(questionId);
      final isFirst = existing.isEmpty;
      await linkRepo.addLink(QuestionKnowledgeLink(
        questionId: questionId,
        knowledgePointId: selected.id,
        source: LinkSource.manual,
        createdAt: DateTime.now(),
        isPrimary: isFirst,
      ));
      invalidateQuestionList(ref);
      invalidateKnowledgePointTree(ref);
    } catch (e) {
      debugPrint('[StructuredKP] add failed: $e');
    }
  }
}

class _StructuredKnowledgeLinkRow extends ConsumerWidget {
  const _StructuredKnowledgeLinkRow({
    required this.view,
    required this.questionId,
  });

  final StructuredKnowledgeLinkView view;
  final String questionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final masteryPct = view.masteryPercentage;
    final masteryColor = masteryPct == null
        ? colorScheme.onSurfaceVariant
        : _masteryColor(masteryPct);
    final masteryLabel = masteryPct == null
        ? '暂无数据'
        : '${masteryPct.round()}%';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppCard(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md, vertical: AppSpace.md),
        child: Row(
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: (view.isPrimary ? AppColors.primary : colorScheme.onSurfaceVariant)
                    .withValues(alpha: isDark ? 0.16 : 0.1),
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: Icon(
                view.isPrimary
                    ? CupertinoIcons.star_fill
                    : CupertinoIcons.star,
                size: 16,
                color: view.isPrimary
                    ? AppColors.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          view.knowledgePoint.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (view.isPrimary) ...<Widget>[
                        const SizedBox(width: AppSpace.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.primary
                                .withValues(alpha: isDark ? 0.16 : 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: AppColors.primary
                                  .withValues(alpha: isDark ? 0.24 : 0.4),
                            ),
                          ),
                          child: const Text(
                            '主',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: <Widget>[
                      Icon(
                        CupertinoIcons.chart_bar,
                        size: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '掌握度 $masteryLabel',
                        style: TextStyle(
                          fontSize: 12,
                          color: masteryColor,
                        ),
                      ),
                      if (view.link.source == LinkSource.ai) ...<Widget>[
                        const SizedBox(width: AppSpace.sm),
                        Text(
                          'AI',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ] else if (view.link.source ==
                          LinkSource.manual) ...<Widget>[
                        const SizedBox(width: AppSpace.sm),
                        Text(
                          '手动',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '在知识树中查看',
              icon: const Icon(CupertinoIcons.arrow_up_right_square,
                  size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: () => context.go(
                  '/knowledge-tree/detail/${view.knowledgePoint.id}'),
            ),
            PopupMenuButton<String>(
              tooltip: '更多操作',
              icon: const Icon(CupertinoIcons.ellipsis, size: 18),
              onSelected: (value) {
                switch (value) {
                  case 'set_primary':
                    _setPrimary(context, ref);
                  case 'remove':
                    _remove(context, ref);
                }
              },
              itemBuilder: (_) => <PopupMenuEntry<String>>[
                if (!view.isPrimary)
                  const PopupMenuItem(
                    value: 'set_primary',
                    child: Row(children: <Widget>[
                      Icon(CupertinoIcons.star, size: 18),
                      SizedBox(width: 8),
                      Text('设为主知识点'),
                    ]),
                  ),
                PopupMenuItem(
                  value: 'remove',
                  child: const Row(children: <Widget>[
                    Icon(CupertinoIcons.trash, size: 18, color: AppColors.danger),
                    SizedBox(width: 8),
                    Text('移除关联', style: TextStyle(color: AppColors.danger)),
                  ]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Color _masteryColor(double pct) {
    if (pct >= 86) return const Color(0xFF15803D);
    if (pct >= 61) return const Color(0xFF16A34A);
    if (pct >= 31) return const Color(0xFFD97706);
    return const Color(0xFFDC2626);
  }

  Future<void> _setPrimary(BuildContext context, WidgetRef ref) async {
    final linkRepo = ref.read(questionKnowledgeLinkRepositoryProvider);
    try {
      await linkRepo.setPrimary(questionId, view.knowledgePoint.id);
      invalidateQuestionList(ref);
      invalidateKnowledgePointTree(ref);
    } catch (e) {
      debugPrint('[StructuredKP] setPrimary failed: $e');
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除关联？'),
        content: Text('确认移除知识点「${view.knowledgePoint.name}」与本题的关联？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final linkRepo = ref.read(questionKnowledgeLinkRepositoryProvider);
    try {
      await linkRepo.removeLink(questionId, view.knowledgePoint.id);
      invalidateQuestionList(ref);
      invalidateKnowledgePointTree(ref);
    } catch (e) {
      debugPrint('[StructuredKP] remove failed: $e');
    }
  }
}

/// Phase 4-C：待确认知识点卡片。
///
/// 显示当前题目下 AI 返回但未匹配到受控节点的知识点文本，提供
/// 「映射到已有知识点」和「忽略」两个操作。映射后会创建结构化
/// [QuestionKnowledgeLink]，忽略则直接标记为已处理。空队列时
/// 返回 [SizedBox.shrink] 不占空间。
class _PendingKnowledgePointsCard extends ConsumerWidget {
  const _PendingKnowledgePointsCard({required this.questionId});

  final String questionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingKnowledgePointsForQuestionProvider(questionId));
    final pending = pendingAsync.valueOrNull ?? const <PendingKnowledgePointMapping>[];
    if (pending.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: AppSpace.lg),
        AppSectionTitle('待确认知识点',
            padding: const EdgeInsets.only(bottom: AppSpace.sm)),
        Text(
          'AI 返回但未匹配到受控知识点的文本，可手动映射或忽略。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpace.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: pending
                .map((m) => _PendingKnowledgePointRow(
                      mapping: m,
                      questionId: questionId,
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _PendingKnowledgePointRow extends ConsumerWidget {
  const _PendingKnowledgePointRow({
    required this.mapping,
    required this.questionId,
  });

  final PendingKnowledgePointMapping mapping;
  final String questionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: MathContentView(
              mapping.originalText,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          IconButton(
            tooltip: '映射到已有知识点',
            icon: const Icon(CupertinoIcons.link, size: 20),
            visualDensity: VisualDensity.compact,
            onPressed: () => _showMapDialog(context, ref),
          ),
          IconButton(
            tooltip: '忽略',
            icon: const Icon(CupertinoIcons.eye_slash, size: 20),
            visualDensity: VisualDensity.compact,
            onPressed: () => _ignore(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _showMapDialog(BuildContext context, WidgetRef ref) async {
    // 先确保知识点树已加载，避免在 loading 态误报"暂无受控知识点"。
    List<KnowledgePoint> tree;
    try {
      tree = await ref.read(knowledgePointTreeProvider.future);
    } catch (_) {
      tree = const <KnowledgePoint>[];
    }
    if (!context.mounted) return;
    if (tree.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('暂无受控知识点'),
          content: const Text('请先在知识点管理页录入受控知识点，再进行映射。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    // 简单的搜索过滤 + 列表选择对话框。
    final selected = await showDialog<KnowledgePoint>(
      context: context,
      builder: (ctx) => _KnowledgePointPickerDialog(tree: tree),
    );
    if (selected == null) return;

    final linkRepo = ref.read(questionKnowledgeLinkRepositoryProvider);
    final pendingRepo = ref.read(pendingKnowledgePointMappingRepositoryProvider);
    try {
      // 若当前题目还没有关联，新加的这一条会成为首条关联，自动设为主知识点。
      final existing = await linkRepo.linksForQuestion(questionId);
      final isFirst = existing.isEmpty;
      await linkRepo.addLink(QuestionKnowledgeLink(
        questionId: questionId,
        knowledgePointId: selected.id,
        source: LinkSource.manual,
        evidence: mapping.originalText,
        createdAt: DateTime.now(),
        isPrimary: isFirst,
      ));
      await pendingRepo.resolve(mapping.id,
          resolution: PendingKnowledgePointResolution.mapped);
      invalidateKnowledgePointTree(ref);
      invalidatePendingKnowledgePoints(ref);
      invalidateQuestionList(ref);
    } catch (e) {
      debugPrint('[PendingKP] map failed: $e');
    }
  }

  Future<void> _ignore(BuildContext context, WidgetRef ref) async {
    final pendingRepo = ref.read(pendingKnowledgePointMappingRepositoryProvider);
    try {
      await pendingRepo.resolve(mapping.id,
          resolution: PendingKnowledgePointResolution.ignored);
      invalidatePendingKnowledgePoints(ref);
    } catch (e) {
      debugPrint('[PendingKP] ignore failed: $e');
    }
  }
}

class _KnowledgePointPickerDialog extends StatefulWidget {
  const _KnowledgePointPickerDialog({required this.tree});

  final List<KnowledgePoint> tree;

  @override
  State<_KnowledgePointPickerDialog> createState() =>
      _KnowledgePointPickerDialogState();
}

class _KnowledgePointPickerDialogState
    extends State<_KnowledgePointPickerDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.tree
        : widget.tree
            .where((kp) =>
                kp.name.toLowerCase().contains(query) ||
                kp.aliases.any((a) => a.toLowerCase().contains(query)))
            .toList();
    return AlertDialog(
      title: const Text('选择受控知识点'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                prefixIcon: Icon(CupertinoIcons.search, size: 20),
                hintText: '搜索知识点名称或别名',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (ctx, index) {
                  final kp = filtered[index];
                  return ListTile(
                    dense: true,
                    title: Text(kp.name),
                    subtitle: kp.aliases.isEmpty
                        ? null
                        : Text(kp.aliases.join(' / '),
                            style: const TextStyle(fontSize: 11)),
                    onTap: () => Navigator.pop(ctx, kp),
                  );
                },
              ),
            ),
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('未找到匹配的知识点'),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

class _SolutionStepItem extends StatelessWidget {
  const _SolutionStepItem({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surface : const Color(0xFFFAFAFF),
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(
          color: isDark ? colorScheme.outlineVariant : const Color(0xFFE0E7FF),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isDark ? colorScheme.primary.withValues(alpha: 0.14) : AppColors.primaryContainerLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text('${index + 1}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? colorScheme.primary : AppColors.primaryDark)),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: MathContentView(
              text,
              style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface,
                  height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _PracticeTab extends StatelessWidget {
  const _PracticeTab({required this.current});

  final QuestionRecord current;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpace.md),
      children: <Widget>[
        _PracticeSummaryCard(current: current),
      ],
    );
  }
}

class _RecordTab extends ConsumerWidget {
  const _RecordTab({
    required this.current,
    required this.onForgot,
    required this.onHard,
    required this.onEasy,
  });

  final QuestionRecord current;
  final VoidCallback onForgot;
  final VoidCallback onHard;
  final VoidCallback onEasy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = const ReviewScheduleService().isDue(current);
    final logsAsync = ref.watch(reviewLogsForQuestionProvider(current.id));

    return ListView(
      padding: const EdgeInsets.all(AppSpace.md),
      children: <Widget>[
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _ProfileTile(
                data: _ProfileData(
                  icon: CupertinoIcons.number,
                  label: '复习次数',
                  value: '${current.reviewCount} 次',
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              _ProfileTile(
                data: _ProfileData(
                  icon: CupertinoIcons.calendar,
                  label: '上次复习',
                  value: current.lastReviewedAt == null
                      ? '从未'
                      : _formatProfileDate(current.lastReviewedAt!),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              _ProfileTile(
                data: _ProfileData(
                  icon: CupertinoIcons.clock,
                  label: '下次复习',
                  value: current.nextReviewAt == null
                      ? '待安排'
                      : _formatProfileDate(current.nextReviewAt!),
                ),
              ),
            ],
          ),
        ),
        if (due) ...<Widget>[
          const SizedBox(height: AppSpace.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('这次复习感觉如何？',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpace.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onForgot,
                        child: const Text('忘记了'),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onHard,
                        child: const Text('有点模糊'),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: FilledButton(
                        onPressed: onEasy,
                        child: const Text('掌握了'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        _ReviewHistoryTimeline(logsAsync: logsAsync),
      ],
    );
  }
}

/// 复习历史时间线（Phase 6-5）。
///
/// 按 [ReviewLog.reviewedAt] 降序展示复习事件，每条显示日期、
/// 复习结果（forgot/reviewing/mastered/reset 的中文映射）和
/// 复习后的掌握度徽章。
class _ReviewHistoryTimeline extends StatelessWidget {
  const _ReviewHistoryTimeline({required this.logsAsync});

  final AsyncValue<List<ReviewLog>> logsAsync;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(CupertinoIcons.list_bullet_indent, size: 18),
              const SizedBox(width: AppSpace.sm),
              const Text('复习历史', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              logsAsync.maybeWhen(
                data: (logs) => Text(
                  '${logs.length} 条',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          logsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpace.lg),
              child: Center(child: Text('加载中…')),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
              child: Text(
                '加载失败：$e',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            data: (logs) {
              if (logs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
                  child: Center(
                    child: Column(
                      children: <Widget>[
                        Icon(
                          CupertinoIcons.clock,
                          size: 32,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: AppSpace.sm),
                        Text(
                          '暂无复习记录',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final sorted = List<ReviewLog>.from(logs)
                ..sort((a, b) => b.reviewedAt.compareTo(a.reviewedAt));
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (int i = 0; i < sorted.length; i++)
                    _ReviewHistoryTimelineItem(
                      log: sorted[i],
                      isLast: i == sorted.length - 1,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ReviewHistoryTimelineItem extends StatelessWidget {
  const _ReviewHistoryTimelineItem({
    required this.log,
    required this.isLast,
  });

  final ReviewLog log;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final (resultLabel, resultColor) = _resultStyle(log.result);
    final isMastered = log.masteryAfter == MasteryLevel.mastered;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: 24,
            child: Column(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: resultColor,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _formatTimelineDate(log.reviewedAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: resultColor.withValues(alpha: isDark ? 0.16 : 0.1),
                          borderRadius: BorderRadius.circular(AppRadius.small),
                          border: Border.all(
                            color: isDark
                                ? resultColor.withValues(alpha: 0.24)
                                : colorScheme.outlineVariant
                                    .withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          resultLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark ? colorScheme.onSurface : resultColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Icon(
                        isMastered
                            ? CupertinoIcons.checkmark_circle
                            : CupertinoIcons.arrow_2_circlepath,
                        size: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _masteryLabel(log.masteryAfter),
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
        ],
      ),
    );
  }

  static (String, Color) _resultStyle(String result) {
    switch (result) {
      case 'forgot':
        return ('忘记', const Color(0xFFDC2626));
      case 'reviewing':
        return ('模糊', const Color(0xFFD97706));
      case 'mastered':
        return ('掌握', const Color(0xFF16A34A));
      case 'reset':
        return ('重置', const Color(0xFF6B7280));
      default:
        return (result, const Color(0xFF6B7280));
    }
  }

  static String _masteryLabel(MasteryLevel level) {
    switch (level) {
      case MasteryLevel.newQuestion:
        return '未复习';
      case MasteryLevel.reviewing:
        return '复习中';
      case MasteryLevel.mastered:
        return '已掌握';
    }
  }

  static String _formatTimelineDate(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thatDay = DateTime(local.year, local.month, local.day);
    final diffDays = today.difference(thatDay).inDays;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    if (diffDays == 0) return '今天 $hh:$mm';
    if (diffDays == 1) return '昨天 $hh:$mm';
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hh:$mm';
  }
}

class _MistakeCategoryCard extends StatelessWidget {
  const _MistakeCategoryCard({
    required this.selected,
    required this.onChanged,
  });

  final MistakeCategory? selected;
  final ValueChanged<MistakeCategory?> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(CupertinoIcons.tag, size: 18),
              const SizedBox(width: AppSpace.sm),
              const Text('错因分类', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (selected != null)
                TextButton(
                  onPressed: () => onChanged(null),
                  child: const Text('清除'),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: MistakeCategory.values.map((category) {
              return ChoiceChip(
                label: Text(category.label),
                selected: selected == category,
                onSelected: (_) => onChanged(category),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _PracticeSummaryCard extends ConsumerWidget {
  const _PracticeSummaryCard({required this.current});

  final QuestionRecord current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = AppColors.primary;

    return AppCard(
      borderRadius: AppRadius.large,
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
                child: const Icon(CupertinoIcons.arrow_2_circlepath,
                    size: 16, color: accent),
              ),
              const SizedBox(width: AppSpace.sm),
              Text(AppStrings.detailSimilarExercises,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface)),
              const Spacer(),
              Text(
                current.savedExercises.isEmpty
                    ? '暂无练习'
                    : '${current.savedExercises.where((e) => e.isCorrect != null).length}/${current.savedExercises.length} 已答',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            current.savedExercises.isEmpty
                ? '这道错题还没有可继续的练习题。'
                : '继续基于这道原题完成练习，已作答状态会保留。',
            style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpace.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: current.savedExercises.isEmpty
                  ? null
                  : () {
                      ref.read(currentPracticeContextProvider.notifier).state =
                          PracticeContext(
                        source: PracticeContextSource.notebook,
                        returnRoute: '/notebook/question/${current.id}',
                      );
                      ref.read(currentQuestionProvider.notifier).state = current;
                      context.go('/exercise/practice');
                    },
              icon: const Icon(CupertinoIcons.play_fill),
              label: Text(current.savedExercises.isEmpty ? '暂无可练习内容' : '继续练习'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BatchSiblingCard extends StatelessWidget {
  const _BatchSiblingCard(
      {required this.current, required this.group, this.onSelect});

  final QuestionRecord current;
  final QuestionBatchGroup group;
  final void Function(QuestionRecord question)? onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(CupertinoIcons.square_grid_2x2,
                  size: 16, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: AppSpace.xs),
              Text('同批题目',
                  key: const ValueKey('batchSiblingTitle'),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant)),
              const SizedBox(width: AppSpace.xs),
              Text('${group.questions.length} 题',
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: group.questions.map((question) {
              final selected = question.id == current.id;
              return GestureDetector(
                onTap: selected || onSelect == null ? null : () => onSelect!(question),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? colorScheme.primary : colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: selected
                            ? colorScheme.primary
                            : colorScheme.outlineVariant),
                  ),
                  child: Text(
                    _siblingLabel(question),
                    style: TextStyle(
                        fontSize: 12,
                        color: selected
                            ? colorScheme.onPrimary
                            : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _siblingLabel(QuestionRecord question) {
    final order = question.splitOrder;
    return order == null ? '同批题' : '第 $order 题';
  }
}

class _ConsistencyNoticeData {
  const _ConsistencyNoticeData({
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

class _ConsistencyNotice extends StatelessWidget {
  const _ConsistencyNotice({required this.notice});

  final _ConsistencyNoticeData notice;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? notice.color.withValues(alpha: 0.14) : notice.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: notice.color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(notice.icon, size: 15, color: notice.color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              notice.text,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: isDark ? Theme.of(context).colorScheme.onSurface : notice.color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _difficultyLabel(QuestionDifficulty value) => switch (value) {
      QuestionDifficulty.foundation => '基础',
      QuestionDifficulty.advanced => '提高',
      QuestionDifficulty.challenge => '压轴 / 挑战',
      QuestionDifficulty.custom => '自定义',
    };

String _attemptStatusLabel(AttemptStatus value) => switch (value) {
      AttemptStatus.notAttempted => '不会做',
      AttemptStatus.wrongAttempt => '做错了',
      AttemptStatus.incomplete => '未完成',
      AttemptStatus.unknown => '未判断',
    };

String _formatProfileDate(DateTime value) {
  final date = value.toLocal();
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$month-$day ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/services/analysis_result_submission_service.dart';
import 'package:smart_wrong_notebook/src/shared/models/question_display_status.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/cached_question_image.dart';

import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';

/// Phase 1 worksheet importer: imports multiple pages and deliberately routes
/// them through the proven single-page crop/correct/analyse flow. This keeps
/// every page reviewable before any AI request is made.
class WorksheetImportScreen extends ConsumerStatefulWidget {
  const WorksheetImportScreen({super.key});

  @override
  ConsumerState<WorksheetImportScreen> createState() =>
      _WorksheetImportScreenState();
}

class _WorksheetImportScreenState extends ConsumerState<WorksheetImportScreen> {
  final Set<int> _selected = <int>{};
  bool _selectionInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = ref.read(currentWorksheetImportProvider);
      if (session != null) {
        final pages = session.pages
            .where((page) => session.sourcePageIds.contains(page.id))
            .toList();
        if (pages.isNotEmpty) {
          setState(() {
            _selected.addAll(List<int>.generate(pages.length, (i) => i));
            _selectionInitialized = true;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentWorksheetImportProvider);
    final autoAnalyzing = ref.watch(worksheetAutoAnalyzeProvider);
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('试卷批量导入')),
        body: AppEmptyState(
          icon: CupertinoIcons.doc_on_clipboard,
          title: '没有待处理的试卷',
          description: '请从“拍照录题”中选择试卷批量导入，或返回首页重新开始。',
          action: FilledButton.icon(
            onPressed: () => context.go('/'),
            icon: const Icon(CupertinoIcons.house),
            label: const Text('返回首页'),
          ),
        ),
      );
    }
    final pages = session.pages
        .where((page) => session.sourcePageIds.contains(page.id))
        .toList();
    final queuedQuestions = session.pages
        .where((page) => !session.sourcePageIds.contains(page.id))
        .toList();
    final readyCount = queuedQuestions.where((item) =>
        inferQuestionDisplayStatus(item) == QuestionDisplayStatus.analyzed).length;
    final ocrDraftCount = queuedQuestions.where((item) =>
        inferQuestionDisplayStatus(item) == QuestionDisplayStatus.recognized).length;
    final failedCount = queuedQuestions
        .where((item) => inferQuestionDisplayStatus(item).isFailed)
        .length;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('试卷批量导入'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: _confirmCancelBatch,
        ),
        actions: <Widget>[
          if (queuedQuestions.isNotEmpty)
            TextButton(
              onPressed: autoAnalyzing ? null : _confirmCancelBatch,
              child: const Text('取消批次'),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('第 1 步：确认导入页面',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  SizedBox(height: 6),
                  Text('将逐页进入裁切、校对和 AI 分析流程。每页的题目仍可使用已有的文本拆分确认功能保存，避免自动切错题污染题库。',
                      style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _ImportOverviewCard(
              pageCount: pages.length,
              selectedPageCount: _selected.length,
              questionCount: queuedQuestions.length,
              readyCount: readyCount,
              ocrDraftCount: ocrDraftCount,
              pendingCount: queuedQuestions.length - readyCount - failedCount,
              failedCount: failedCount,
              autoAnalyzing: autoAnalyzing,
            ),
            Row(
              children: <Widget>[
                Text('已选 ${_selected.length}/${pages.length} 页',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() =>
                      _selected.addAll(List<int>.generate(pages.length, (i) => i))),
                  child: const Text('全选'),
                ),
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: const Text('清空'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (session.processedSourcePageCount > 0 && session.processedSourcePageCount < session.sourcePageCount)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.tonalIcon(
                  onPressed: () => _resumeFromLastProcessed(pages),
                  icon: const Icon(CupertinoIcons.play_circle),
                  label: Text('继续处理（已完成 ${session.processedSourcePageCount}/${session.sourcePageCount} 页）'),
                  style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                ),
              ),
            ...pages.asMap().entries.map((entry) => _PageTile(
                  page: entry.value,
                  index: entry.key,
                  selected: _selected.contains(entry.key),
                  processed: session.isSourcePageProcessed(entry.value.id),
                  onChanged: (value) => setState(() {
                    if (value) {
                      _selected.add(entry.key);
                    } else {
                      _selected.remove(entry.key);
                    }
                  }),
                  onTap: () => _startPage(entry.value),
                  onReselectImage: () => _reselectPageImage(entry.value),
                )),
            const SizedBox(height: 16),
            if (queuedQuestions.isNotEmpty)
              _QueueSummaryCard(
                questions: queuedQuestions,
                readyCount: readyCount,
                ocrDraftCount: ocrDraftCount,
                failedCount: failedCount,
                autoAnalyzing: autoAnalyzing,
                onStartOne: () => _startQueuedQuestion(queuedQuestions
                    .firstWhere((item) => item.contentStatus != ContentStatus.ready,
                        orElse: () => queuedQuestions.first)),
                onStartAll: () => _startAllQueuedQuestions(queuedQuestions),
                onStop: () => setWorksheetAutoAnalyze(ref, false),
                onSaveReady: () => _saveReadyQuestions(queuedQuestions),
                onRetryFailed: () => _retryFailedQuestions(queuedQuestions),
                onAnalyzeDrafts: () => _analyzeOcrDrafts(queuedQuestions),
                onOpen: _openQueuedQuestion,
                onRetryQuestion: _retryQuestion,
                onReeditQuestion: _reeditQueuedQuestion,
              ),
            if (queuedQuestions.isNotEmpty) const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _startRegionEditor(pages),
              icon: const Icon(CupertinoIcons.square_on_square),
              label: Text('整页框选多题（${_selected.length} 页）'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48)),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _selected.isEmpty ? null : () => _startFirstSelected(pages),
              icon: const Icon(CupertinoIcons.crop),
              label: Text('开始处理已选页面 (${_selected.length})'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50)),
            ),
            const SizedBox(height: 8),
            Text('本切片先完成多页导入与逐页可控处理；图像级自动题框、批量后台队列将在后续切片接入。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCancelBatch() async {
    final session = ref.read(currentWorksheetImportProvider);
    if (session == null) {
      if (mounted) context.go('/');
      return;
    }
    final candidates = session.pages
        .where((item) => !session.sourcePageIds.contains(item.id))
        .toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('取消本次试卷导入？'),
        content: Text(candidates.isEmpty
            ? '将退出导入流程。原始试卷页面不会写入错题本。'
            : '将放弃 ${candidates.length} 道待确认题目，并清理本次裁切生成的临时题图。已经保存到错题本的题目不会受影响。'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('继续导入')),
          FilledButton.tonal(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('取消并清理')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final storage = ref.read(imageStorageServiceProvider);
    for (final candidate in candidates) {
      await storage.deleteImage(candidate.imagePath);
    }
    await persistWorksheetImport(ref, null);
    await setWorksheetAutoAnalyze(ref, false);
    ref.read(currentQuestionProvider.notifier).state = null;
    if (!mounted) return;
    context.go('/');
  }

  Future<void> _openQueuedQuestion(QuestionRecord question) async {
    if (inferQuestionDisplayStatus(question) == QuestionDisplayStatus.recognized) {
      final worksheet = ref.read(currentWorksheetImportProvider);
      if (worksheet != null) {
        final next = worksheet.pages.map((item) => item.id == question.id
            ? item.copyWith(contentStatus: ContentStatus.processing) : item).toList();
        await persistWorksheetImport(ref, worksheet.copyWith(pages: next));
        question = next.firstWhere((item) => item.id == question.id);
      }
      ref.read(currentQuestionProvider.notifier).state = question;
      if (mounted) context.go('/analysis/loading');
      return;
    }
    ref.read(currentQuestionProvider.notifier).state = question;
    final status = inferQuestionDisplayStatus(question);
    context.go(status == QuestionDisplayStatus.analyzed ||
        status == QuestionDisplayStatus.needsConfirmation ||
        status == QuestionDisplayStatus.recognized
        ? '/analysis/result'
        : '/analysis/loading');
  }

  Future<void> _saveReadyQuestions(List<QuestionRecord> queuedQuestions) async {
    final ready = queuedQuestions.where((item) =>
        inferQuestionDisplayStatus(item) == QuestionDisplayStatus.analyzed).toList();
    if (ready.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AnalysisResultSubmissionService(
        ref.read(questionRepositoryProvider),
      ).submitAll(ready);
      invalidateQuestionList(ref);
      final worksheet = ref.read(currentWorksheetImportProvider);
      if (worksheet != null) {
        await persistWorksheetImport(
          ref,
          worksheet.copyWith(pages: worksheet.pages
              .where((page) => !ready.any((item) => item.id == page.id))
              .toList()),
        );
      }
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('已批量保存 ${ready.length} 道题到错题本')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('批量保存失败: $e')));
    }
  }

  Future<void> _retryQuestion(QuestionRecord question) async {
    final worksheet = ref.read(currentWorksheetImportProvider);
    if (worksheet == null) return;
    final next = worksheet.pages.map((item) => item.id == question.id
        ? item.copyWith(contentStatus: ContentStatus.processing) : item).toList();
    await persistWorksheetImport(ref, worksheet.copyWith(pages: next));
    final updated = next.firstWhere((item) => item.id == question.id);
    ref.read(currentQuestionProvider.notifier).state = updated;
    if (mounted) context.go('/analysis/loading');
  }

  Future<void> _retryFailedQuestions(List<QuestionRecord> queuedQuestions) async {
    final failed = queuedQuestions.where((item) => inferQuestionDisplayStatus(item).isFailed).toList();
    if (failed.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('重试 ${failed.length} 道失败题？'),
        content: const Text('会保留当前裁切题图与人工校对文字，仅重新调用普通 AI 分析，不会重新 OCR 或裁切。'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('开始重试')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final worksheet = ref.read(currentWorksheetImportProvider);
    if (worksheet == null) return;
    final ids = failed.map((item) => item.id).toSet();
    final next = worksheet.pages.map((item) => ids.contains(item.id)
        ? item.copyWith(contentStatus: ContentStatus.processing) : item).toList();
    await persistWorksheetImport(ref, worksheet.copyWith(pages: next));
    final first = next.firstWhere((item) => item.id == failed.first.id);
    ref.read(currentQuestionProvider.notifier).state = first;
    await setWorksheetAutoAnalyze(ref, true);
    if (mounted) context.go('/analysis/loading');
  }

  Future<void> _analyzeOcrDrafts(List<QuestionRecord> queuedQuestions) async {
    final drafts = queuedQuestions.where((item) =>
        inferQuestionDisplayStatus(item) == QuestionDisplayStatus.recognized).toList();
    if (drafts.isEmpty) return;
    final worksheet = ref.read(currentWorksheetImportProvider);
    if (worksheet != null) {
      final ids = drafts.map((item) => item.id).toSet();
      final next = worksheet.pages.map((item) => ids.contains(item.id)
          ? item.copyWith(contentStatus: ContentStatus.processing)
          : item).toList();
      await persistWorksheetImport(ref, worksheet.copyWith(pages: next));
      final first = next.firstWhere((item) => item.id == drafts.first.id);
      ref.read(currentQuestionProvider.notifier).state = first;
      await setWorksheetAutoAnalyze(ref, true);
      if (mounted) context.go('/analysis/loading');
    }
  }

  Future<void> _startAllQueuedQuestions(List<QuestionRecord> queuedQuestions) async {
    final next = queuedQuestions.firstWhere(
      (item) {
        final status = inferQuestionDisplayStatus(item);
        return status != QuestionDisplayStatus.analyzed &&
            status != QuestionDisplayStatus.recognized &&
            !status.isFailed;
      },
      orElse: () => queuedQuestions.firstWhere(
        (item) {
          final status = inferQuestionDisplayStatus(item);
          return status != QuestionDisplayStatus.analyzed &&
              status != QuestionDisplayStatus.recognized;
        },
        orElse: () => queuedQuestions.first,
      ),
    );
    await setWorksheetAutoAnalyze(ref, true);
    if (!mounted) return;
    _startQueuedQuestion(next);
  }

  void _startQueuedQuestion(QuestionRecord question) {
    ref.read(currentQuestionProvider.notifier).state = question;
    context.go('/analysis/loading');
  }

  void _startRegionEditor(List<QuestionRecord> pages) {
    if (_selected.isEmpty) return;
    final index = _selected.reduce((a, b) => a < b ? a : b);
    ref.read(currentQuestionProvider.notifier).state = pages[index];
    context.go('/worksheet/regions');
  }

  void _startFirstSelected(List<QuestionRecord> pages) {
    final index = _selected.reduce((a, b) => a < b ? a : b);
    _startPage(pages[index]);
  }

  void _resumeFromLastProcessed(List<QuestionRecord> pages) {
    final session = ref.read(currentWorksheetImportProvider);
    if (session == null) return;
    final lastId = session.lastProcessedId;
    if (lastId != null) {
      final lastIndex = pages.indexWhere((p) => p.id == lastId);
      if (lastIndex != -1 && lastIndex < pages.length - 1) {
        _startPage(pages[lastIndex + 1]);
        return;
      }
    }
    final unprocessed = pages.where((p) => !session.isSourcePageProcessed(p.id)).toList();
    if (unprocessed.isNotEmpty) {
      _startPage(unprocessed.first);
    }
  }

  void _startPage(QuestionRecord page) {
    ref.read(currentQuestionProvider.notifier).state = page;
    context.go('/capture/crop');
  }

  Future<void> _markPageProcessed(String pageId) async {
    final worksheet = ref.read(currentWorksheetImportProvider);
    if (worksheet == null) return;
    if (worksheet.isSourcePageProcessed(pageId)) return;
    final updated = worksheet.copyWith(
      processedSourcePageIds: {...worksheet.processedSourcePageIds, pageId},
      lastProcessedId: pageId,
    );
    await persistWorksheetImport(ref, updated);
  }

  /// 原图路径失效时让用户重新选择图片，写回到工作台对应页面。
  ///
  /// 选图后会把旧 imagePath（若仍存在）从磁盘删除，避免残留无效文件；
  /// 同步更新内存中的 session，让 `_PageTile` 立刻从"原图不可用"切回正常态。
  Future<void> _reselectPageImage(QuestionRecord page) async {
    final messenger = ScaffoldMessenger.of(context);
    final XFile? picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2560,
      maxHeight: 2560,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    final worksheet = ref.read(currentWorksheetImportProvider);
    if (worksheet == null) return;
    try {
      final storage = ref.read(imageStorageServiceProvider);
      final newPath = await storage.saveImage(File(picked.path));
      final oldPath = page.imagePath;
      final nextPages = worksheet.pages.map((item) => item.id == page.id
          ? item.copyWith(imagePath: newPath) : item).toList();
      await persistWorksheetImport(ref, worksheet.copyWith(pages: nextPages));
      // 旧文件若仍存在则清理；不阻塞主流程。
      if (oldPath.isNotEmpty && oldPath != newPath) {
        await storage.deleteImage(oldPath);
      }
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text('已重新选图，可继续裁切和校对'),
        duration: Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('重新选图失败: $e')));
    }
  }

  /// 识别完成但未校对的题目（OCR 草稿），让用户重新进入保存确认页校对文字。
  ///
  /// 这里不重新跑 OCR / AI：用户已经看过识别结果，只需补一遍人工校对并
  /// 保存到错题本。QuestionSaveConfirmationScreen 保存后会自动回到工作台。
  void _reeditQueuedQuestion(QuestionRecord question) {
    ref.read(currentQuestionProvider.notifier).state = question;
    context.go('/capture/save-confirmation');
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    required this.page,
    required this.index,
    required this.selected,
    required this.onChanged,
    required this.onTap,
    this.processed = false,
    this.onReselectImage,
  });

  final QuestionRecord page;
  final int index;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final VoidCallback onTap;
  final bool processed;
  final VoidCallback? onReselectImage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final available = page.imagePath.isNotEmpty && File(page.imagePath).existsSync();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 112,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? const Color(0xFF0F766E) : scheme.outlineVariant),
          ),
          child: Row(children: <Widget>[
            Checkbox(value: selected, onChanged: (v) => onChanged(v ?? false)),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 72,
                height: 88,
                child: available
                    ? Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          CachedQuestionImage(page.imagePath, fit: BoxFit.cover),
                          if (processed)
                            Container(
                              color: AppColors.success.withValues(alpha: 0.7),
                              child: const Center(child: Icon(CupertinoIcons.checkmark, color: Colors.white, size: 32)),
                            ),
                        ],
                      )
                    : _UnavailablePageThumbnail(onReselect: onReselectImage),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text('第 ${index + 1} 页', style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (processed)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: AppTag(
                          label: '已处理',
                          textColor: AppColors.success,
                          backgroundColor: AppColors.success.withValues(alpha: 0.15),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  available ? (processed ? '已完成裁切，可点击查看' : '点击进入裁切和校对') : '原图不可用，可重新选图',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            )),
            const Icon(CupertinoIcons.chevron_right, size: 18),
          ]),
        ),
      ),
    );
  }
}

/// 缩略图位置原图不可用时显示的占位块，提供"重新选图"入口。
class _UnavailablePageThumbnail extends StatelessWidget {
  const _UnavailablePageThumbnail({required this.onReselect});

  final VoidCallback? onReselect;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE5E7EB),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(CupertinoIcons.photo, size: 20, color: Color(0xFF6B7280)),
          const SizedBox(height: 4),
          if (onReselect != null)
            TextButton(
              onPressed: onReselect,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                minimumSize: const Size(0, 24),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 11),
              ),
              child: const Text('重新选图'),
            )
          else
            const Text(
              '原图不可用',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
        ],
      ),
    );
  }
}


class _QueueSummaryCard extends StatelessWidget {
  const _QueueSummaryCard({
    required this.questions,
    required this.readyCount,
    required this.ocrDraftCount,
    required this.failedCount,
    required this.autoAnalyzing,
    required this.onStartOne,
    required this.onStartAll,
    required this.onStop,
    required this.onSaveReady,
    required this.onRetryFailed,
    required this.onAnalyzeDrafts,
    required this.onOpen,
    required this.onRetryQuestion,
    required this.onReeditQuestion,
  });

  final List<QuestionRecord> questions;
  final int readyCount;
  final int ocrDraftCount;
  final int failedCount;
  final bool autoAnalyzing;
  final VoidCallback onStartOne;
  final VoidCallback onStartAll;
  final VoidCallback onStop;
  final VoidCallback onSaveReady;
  final VoidCallback onRetryFailed;
  final VoidCallback onAnalyzeDrafts;
  final ValueChanged<QuestionRecord> onOpen;
  final ValueChanged<QuestionRecord> onRetryQuestion;
  final ValueChanged<QuestionRecord> onReeditQuestion;

  @override
  Widget build(BuildContext context) {
    final pending = questions.length - readyCount - failedCount;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          const Icon(CupertinoIcons.clock, color: Color(0xFF4F46E5)),
          const SizedBox(width: 10),
          Expanded(child: Text('题目队列 ${questions.length} 道 · 已分析 $readyCount 道${failedCount > 0 ? ' · 失败 $failedCount 道' : ''}${pending > 0 ? ' · 待处理 $pending 道' : ''}。')),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
          TextButton(
            onPressed: autoAnalyzing || pending == 0 ? null : onStartOne,
            child: const Text('单题开始'),
          ),
          FilledButton.tonalIcon(
            onPressed: autoAnalyzing || pending == 0 ? null : onStartAll,
            icon: Icon(autoAnalyzing ? CupertinoIcons.pause_circle : CupertinoIcons.play_circle),
            label: Text(autoAnalyzing ? '正在自动处理' : '开始全部'),
          ),
          if (autoAnalyzing)
            IconButton(
              tooltip: '停止自动处理',
              onPressed: onStop,
              icon: const Icon(CupertinoIcons.stop_circle),
            ),
          if (failedCount > 0)
            OutlinedButton.icon(
              onPressed: autoAnalyzing ? null : onRetryFailed,
              icon: const Icon(CupertinoIcons.arrow_clockwise, size: 16),
              label: Text('重试失败题 ($failedCount)'),
            ),
          if (ocrDraftCount > 0)
            OutlinedButton.icon(
              onPressed: autoAnalyzing ? null : onAnalyzeDrafts,
              icon: const Icon(CupertinoIcons.sparkles, size: 16),
              label: Text('分析 OCR 草稿 ($ocrDraftCount)'),
            ),
          if (readyCount > 0)
            FilledButton.icon(
              onPressed: onSaveReady,
              icon: const Icon(CupertinoIcons.tray_arrow_down, size: 16),
              label: Text('保存已分析题目 ($readyCount)'),
            ),
        ]),
        if (questions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          const Text('本批结果', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ...questions.asMap().entries.map((entry) {
            final displayStatus = inferQuestionDisplayStatus(entry.value);
            return _QueueQuestionTile(
              index: entry.key,
              question: entry.value,
              onOpen: () => onOpen(entry.value),
              onRetry: displayStatus.isFailed ? () => onRetryQuestion(entry.value) : null,
              onReedit: displayStatus == QuestionDisplayStatus.recognized
                  ? () => onReeditQuestion(entry.value)
                  : null,
              autoAnalyzing: autoAnalyzing,
            );
          }),
        ],
      ]),
    );
  }
}

class _QueueQuestionTile extends StatelessWidget {
  const _QueueQuestionTile({
    required this.index,
    required this.question,
    required this.onOpen,
    this.onRetry,
    this.onReedit,
    this.autoAnalyzing = false,
  });

  final int index;
  final QuestionRecord question;
  final VoidCallback onOpen;
  final VoidCallback? onRetry;
  /// OCR 草稿（识别完成未校对）时显示，跳转保存确认页让用户补一遍人工校对。
  final VoidCallback? onReedit;
  final bool autoAnalyzing;

  @override
  Widget build(BuildContext context) {
    final displayStatus = inferQuestionDisplayStatus(question);
    final isFailed = displayStatus.isFailed;
    final isProcessing = displayStatus.isInProgress;
    final isOcrDraft = displayStatus == QuestionDisplayStatus.recognized;

    final Color color;
    final String label;
    switch (displayStatus) {
      case QuestionDisplayStatus.recognizing:
        color = AppColors.info;
        label = '识别中';
      case QuestionDisplayStatus.analyzing:
        color = AppColors.info;
        label = '分析中';
      case QuestionDisplayStatus.recognized:
        color = AppColors.info;
        label = 'OCR 草稿';
      case QuestionDisplayStatus.needsConfirmation:
        color = AppColors.warning;
        label = '待确认';
      case QuestionDisplayStatus.analyzed:
        color = AppColors.success;
        label = '已分析';
      case QuestionDisplayStatus.recognitionFailed:
        color = AppColors.danger;
        label = '识别失败';
      case QuestionDisplayStatus.analysisFailed:
        color = AppColors.danger;
        label = '分析失败';
    }

    return InkWell(
      onTap: isProcessing ? null : onOpen,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: <Widget>[
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(11)),
            child: isProcessing && autoAnalyzing
                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('${index + 1}', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(
            question.correctedText.trim().isEmpty ? '题图待识别' : question.correctedText.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: isProcessing ? Theme.of(context).colorScheme.onSurfaceVariant : null),
          )),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
          const SizedBox(width: 6),
          if (isFailed && onRetry != null && !autoAnalyzing)
            IconButton(
              icon: const Icon(CupertinoIcons.arrow_clockwise, size: 16),
              tooltip: '重试',
              onPressed: onRetry,
            )
          else if (isOcrDraft && onReedit != null && !autoAnalyzing)
            IconButton(
              icon: const Icon(CupertinoIcons.pencil, size: 16),
              tooltip: '重新校对',
              onPressed: onReedit,
            )
          else if (!isProcessing)
            const Icon(CupertinoIcons.chevron_right, size: 14),
        ]),
      ),
    );
  }
}


class _ImportOverviewCard extends StatelessWidget {
  const _ImportOverviewCard({
    required this.pageCount,
    required this.selectedPageCount,
    required this.questionCount,
    required this.readyCount,
    required this.ocrDraftCount,
    required this.pendingCount,
    required this.failedCount,
    required this.autoAnalyzing,
  });

  final int pageCount;
  final int selectedPageCount;
  final int questionCount;
  final int readyCount;
  final int ocrDraftCount;
  final int pendingCount;
  final int failedCount;
  final bool autoAnalyzing;

  @override
  Widget build(BuildContext context) {
    final analyzedCount = readyCount - ocrDraftCount;
    final total = analyzedCount + ocrDraftCount + pendingCount + failedCount;

    return Card(
      margin: EdgeInsets.zero,
      color: const Color(0xFFF8FAFC),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            const Icon(CupertinoIcons.chart_bar_square, color: Color(0xFF4F46E5)),
            const SizedBox(width: 8),
            Expanded(child: Text('本次导入总览 · $pageCount 页 / $questionCount 道题', style: const TextStyle(fontWeight: FontWeight.w700))),
            Text('已选 $selectedPageCount 页', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          ]),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              Column(children: <Widget>[
                Text('$analyzedCount', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
                const SizedBox(height: 2),
                const Text('已分析', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              ]),
              Column(children: <Widget>[
                Text('$ocrDraftCount', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF2563EB))),
                const SizedBox(height: 2),
                const Text('OCR 草稿', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              ]),
              Column(children: <Widget>[
                Text('$pendingCount', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                const SizedBox(height: 2),
                const Text('待处理', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              ]),
              Column(children: <Widget>[
                Text('$failedCount', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFFEA580C))),
                const SizedBox(height: 2),
                const Text('失败', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              ]),
            ],
          ),
          if (total > 0) ...<Widget>[
            const SizedBox(height: 10),
            ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: analyzedCount / total, minHeight: 7, backgroundColor: const Color(0xFFE2E8F0), color: const Color(0xFF16A34A))),
          ],
        ]),
      ),
    );
  }
}

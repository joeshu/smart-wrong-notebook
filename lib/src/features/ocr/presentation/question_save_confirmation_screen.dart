import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/shared/utils/duplicate_detector.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/cached_question_image.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/status_pill.dart';

class QuestionSaveConfirmationScreen extends ConsumerStatefulWidget {
  const QuestionSaveConfirmationScreen({super.key});

  @override
  ConsumerState<QuestionSaveConfirmationScreen> createState() =>
      _QuestionSaveConfirmationScreenState();
}

class _QuestionSaveConfirmationScreenState
    extends ConsumerState<QuestionSaveConfirmationScreen> {
  late final TextEditingController _textController;
  String? _errorMessage;

  // 错题去重检测相关状态。
  // _duplicateMatches 为 null 表示尚未检测完成；空列表表示无相似题。
  List<DuplicateMatch>? _duplicateMatches;
  bool _detecting = false;
  bool _warningDismissed = false;
  bool _hasViewedSimilar = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeDetectDuplicates();
  }

  Future<void> _maybeDetectDuplicates() async {
    if (_detecting || _duplicateMatches != null) return;
    final candidate = ref.read(currentQuestionProvider);
    if (candidate == null) return;

    setState(() => _detecting = true);
    try {
      final existing = await ref.read(questionRepositoryProvider).listAll();
      if (!mounted) return;
      final matches = await duplicateDetector.detectDuplicates(
        candidate,
        existing,
      );
      if (!mounted) return;
      setState(() {
        _duplicateMatches = matches;
        _detecting = false;
      });
    } catch (_) {
      if (!mounted) return;
      // 检测失败时不阻塞保存流程，按"无相似题"处理。
      setState(() {
        _duplicateMatches = const <DuplicateMatch>[];
        _detecting = false;
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(currentQuestionProvider);

    if (current == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('保存确认')),
        body: const Center(child: Text('未找到题目记录')),
      );
    }

    final hasImage =
        current.imagePath.isNotEmpty && File(current.imagePath).existsSync();

    final initialText = current.normalizedQuestionText.isNotEmpty
        ? current.normalizedQuestionText
        : current.extractedQuestionText;
    if (_textController.text != initialText) {
      _textController.value = TextEditingValue(
        text: initialText,
        selection: TextSelection.collapsed(offset: initialText.length),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('保存确认'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => context.go('/analysis/result'),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (_shouldShowWarning())
              _buildDuplicateWarning(_duplicateMatches!),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (hasImage)
                      GestureDetector(
                        onTap: () => _showFullImage(context, current.imagePath),
                        child: Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(maxHeight: 130),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Theme.of(context).colorScheme.outlineVariant),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedQuestionImage(
                              current.imagePath,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        height: 160,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Theme.of(context).colorScheme.outlineVariant),
                        ),
                        child: Center(
                            child: Text('暂无图片',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant))),
                      ),
                    const SizedBox(height: 16),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Row(
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? const Color(0xFF4F46E5).withValues(alpha: 0.18)
                                  : const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const Icon(CupertinoIcons.book,
                                    size: 14, color: Color(0xFF4F46E5)),
                                const SizedBox(width: 4),
                                Text(
                                  current.subject.label,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF4F46E5),
                                      fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text('保存前可编辑',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: <Widget>[
                        Text(
                          '确认题目内容',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        // Phase 10-4：接入统一 FieldStatus 徽章，
                        // 直观展示题干识别状态。OCR 置信度 < 0.6 视为待校对。
                        StatusPill(
                          label: '题干',
                          status: _questionFieldStatus(current),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '保存到错题本前，确认结构化题目文本，方便后续检索、分类与继续练习。',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _textController,
                      maxLines: 10,
                      minLines: 8,
                      onChanged: (_) {
                        setState(() {
                          _errorMessage = null;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: '如果识别结果为空，可以手动补充题目内容',
                        errorText: _errorMessage,
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.outlineVariant),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _FormulaPreviewCard(content: _textController.text),
                    if (_errorMessage != null) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(
                        _errorMessage!,
                        style:
                            const TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.go('/analysis/result'),
                      icon: const Icon(CupertinoIcons.chevron_left, size: 18),
                      label: const Text('返回结果页'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        final text = _textController.text.trim();
                        if (text.isEmpty) {
                          setState(() => _errorMessage = '请先补充题目内容，再保存到错题本');
                          return;
                        }
                        // 有相似题且用户尚未查看时，再提示一次确认。
                        if (_shouldConfirmSaveBeforeDuplicate()) {
                          final proceed = await _confirmSaveDespiteDuplicates();
                          if (!proceed) {
                            await _showSimilarQuestionsDialog();
                            return;
                          }
                        }
                        await _saveQuestion(current);
                      },
                      icon:
                          const Icon(CupertinoIcons.checkmark_alt, size: 18),
                      label: const Text('确认并保存到错题本'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
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

  /// Phase 10-4：根据题目 OCR 置信度与文本非空判断题干字段状态。
  ///
  /// - normalizedQuestionText 为空 → [FieldStatus.missing]（未识别）
  /// - 文本非空 且 ocrConfidence < 0.6 → [FieldStatus.needsReview]（待校对）
  /// - 文本非空 且 ocrConfidence >= 0.6 或置信度未知 → [FieldStatus.recognized]
  FieldStatus _questionFieldStatus(QuestionRecord q) {
    final text = q.normalizedQuestionText.isNotEmpty
        ? q.normalizedQuestionText
        : q.extractedQuestionText;
    if (text.trim().isEmpty) return FieldStatus.missing;
    final confidence = q.ocrConfidence;
    if (confidence != null && confidence < 0.6) {
      return FieldStatus.needsReview;
    }
    return FieldStatus.recognized;
  }

  /// 是否需要在保存前再提示一次相似题确认。
  bool _shouldConfirmSaveBeforeDuplicate() {
    final matches = _duplicateMatches;
    if (matches == null || matches.isEmpty) return false;
    return !_hasViewedSimilar;
  }

  /// 弹出"仍有相似题，是否仍要保存"确认框。
  /// 返回 true 表示用户选择"仍要保存"；返回 false 表示用户选择"查看相似题"。
  Future<bool> _confirmSaveDespiteDuplicates() async {
    final matches = _duplicateMatches;
    if (matches == null || matches.isEmpty) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('发现相似题'),
          content: Text('检测到 ${matches.length} 道相似题，仍要保存吗？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('查看相似题'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('仍要保存'),
            ),
          ],
        );
      },
    );
    // 标记用户已查看，避免反复弹窗。
    if (mounted) {
      setState(() => _hasViewedSimilar = true);
    }
    return result ?? false;
  }

  /// 弹出相似题列表对话框；点击列表项关闭对话框并跳转到该题详情页。
  Future<void> _showSimilarQuestionsDialog() async {
    final matches = _duplicateMatches;
    if (matches == null || matches.isEmpty) return;
    if (mounted) {
      setState(() => _hasViewedSimilar = true);
    }
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('相似题列表'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: matches.length,
              itemBuilder: (_, index) {
                final match = matches[index];
                final question = match.existingQuestion;
                final preview = _previewText(question);
                final percent = (match.overallScore * 100).round();
                return ListTile(
                  title: Text(
                    preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    '相似度 $percent% · 添加于 ${_formatDate(question.createdAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    context.go('/notebook/question/${question.id}');
                  },
                );
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  /// 实际执行保存：原保存流程，未做任何行为变更。
  Future<void> _saveQuestion(QuestionRecord current) async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() => _errorMessage = '请先补充题目内容，再保存到错题本');
      return;
    }

    final updated = current.copyWith(
      extractedQuestionText: current.extractedQuestionText.isNotEmpty
          ? current.extractedQuestionText
          : text,
      normalizedQuestionText: text,
    );
    ref.read(currentQuestionProvider.notifier).state = updated;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    await ref.read(questionRepositoryProvider).saveDraft(updated);
    invalidateQuestionList(ref);
    final worksheet = ref.read(currentWorksheetImportProvider);
    if (worksheet != null) {
      final remaining = worksheet.pages
          .where((page) => page.id != current.id)
          .toList();
      await persistWorksheetImport(
        ref,
        remaining.isEmpty ? null : worksheet.copyWith(pages: remaining),
      );
    }
    ref.read(currentQuestionProvider.notifier).state = null;
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('已保存到错题本'),
        duration: Duration(seconds: 2),
      ),
    );
    router.go(worksheet == null || worksheet.pages.length <= 1
        ? '/notebook'
        : '/worksheet/import');
  }

  bool _shouldShowWarning() {
    final matches = _duplicateMatches;
    if (matches == null || matches.isEmpty) return false;
    return !_warningDismissed;
  }

  Widget _buildDuplicateWarning(List<DuplicateMatch> matches) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark
        ? AppColors.accentAmber.withValues(alpha: 0.14)
        : AppColors.accentAmberContainerLight;
    final borderColor = AppColors.accentAmber.withValues(alpha: 0.4);
    final maxScore = matches.first.overallScore;
    final percent = (maxScore * 100).round();

    return Dismissible(
      key: const ValueKey<String>('duplicate-warning-bar'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) {
        setState(() {
          _warningDismissed = true;
          _hasViewedSimilar = true;
        });
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(
            AppSpace.lg, AppSpace.md, AppSpace.lg, 0),
        padding: const EdgeInsets.fromLTRB(AppSpace.md, 10, AppSpace.sm, 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(CupertinoIcons.exclamationmark_triangle,
                  color: AppColors.accentAmber, size: 20),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '检测到 ${matches.length} 道相似题（相似度 $percent%）',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 4,
                      children: <Widget>[
                        TextButton(
                          onPressed: _showSimilarQuestionsDialog,
                          style: TextButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10),
                            minimumSize: const Size(0, 28),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            '查看相似题',
                            style: TextStyle(
                              color: AppColors.accentAmber,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _hasViewedSimilar = true;
                              _warningDismissed = true;
                            });
                          },
                          style: TextButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10),
                            minimumSize: const Size(0, 28),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            '仍要保存',
                            style: TextStyle(
                              color: AppColors.accentAmber,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
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

  /// 取题干前 80 字作为列表预览文本。
  String _previewText(QuestionRecord question) {
    final text = question.normalizedQuestionText.isNotEmpty
        ? question.normalizedQuestionText
        : question.extractedQuestionText;
    if (text.length <= 80) return text;
    return '${text.substring(0, 80)}…';
  }

  String _formatDate(DateTime date) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }
}

class _FormulaPreviewCard extends StatelessWidget {
  const _FormulaPreviewCard({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final trimmed = content.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '公式预览',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          trimmed.isEmpty
              ? Text('暂无可预览内容',
                  style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant))
              : MathContentView(trimmed, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}

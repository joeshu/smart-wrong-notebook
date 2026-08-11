import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_split_session.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/cached_question_image.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/status_pill.dart';

const _mathPreviewFormat = QuestionContentFormat.latexMixed;

class QuestionSplitConfirmationScreen extends ConsumerStatefulWidget {
  const QuestionSplitConfirmationScreen({super.key});

  @override
  ConsumerState<QuestionSplitConfirmationScreen> createState() =>
      _QuestionSplitConfirmationScreenState();
}

class _QuestionSplitConfirmationScreenState
    extends ConsumerState<QuestionSplitConfirmationScreen> {
  int _activeIndex = 0;
  String? _errorMessage;
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentQuestionSplitSessionProvider);
    final source = session?.source;
    final drafts = session?.drafts ?? const <QuestionSplitDraft>[];
    final hasImage = source != null &&
        source.imagePath.isNotEmpty &&
        File(source.imagePath).existsSync();

    if (session == null || source == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('拆分保存')),
        body: const Center(child: Text('未找到待保存题目')),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final safeIndex =
        drafts.isEmpty ? 0 : _activeIndex.clamp(0, drafts.length - 1);
    final activeDraft = drafts.isEmpty ? null : drafts[safeIndex];
    final selectedCount =
        drafts.where((draft) => draft.canSave && draft.selected).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('拆分保存'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => context.go('/analysis/result'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF4F46E5).withValues(alpha: 0.18)
                              : const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(CupertinoIcons.square_split_2x2,
                            size: 18, color: Color(0xFF4F46E5)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text('逐题确认后保存',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                              '保存前按题整理，方便后续检索、复习和继续练习。',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: <Widget>[
                      _SummaryChip(
                        label: '候选 ${drafts.length} 题',
                        bgColor: isDark
                            ? const Color(0xFF4F46E5).withValues(alpha: 0.18)
                            : const Color(0xFFEEF2FF),
                        textColor: const Color(0xFF4F46E5),
                      ),
                      _SummaryChip(
                        label: '已选 $selectedCount 题',
                        bgColor: isDark
                            ? const Color(0xFF16A34A).withValues(alpha: 0.16)
                            : const Color(0xFFF0FDF4),
                        textColor: const Color(0xFF16A34A),
                      ),
                      _SummaryChip(
                        label: source.subject.label,
                        bgColor: isDark
                            ? const Color(0xFFD97706).withValues(alpha: 0.16)
                            : const Color(0xFFFFF7ED),
                        textColor: const Color(0xFFD97706),
                      ),
                    ],
                  ),                ],
              ),
            ),
            const SizedBox(height: 16),
            if (hasImage)
              GestureDetector(
                onTap: () => _showFullImage(context, source.imagePath),
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
                      source.imagePath,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            if (hasImage) const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('题目列表',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      TextButton.icon(
                        onPressed:
                            _isSaving ? null : () => _setAllSelected(true),
                        icon: const Icon(CupertinoIcons.checkmark_circle,
                            size: 16),
                        label: const Text('全选'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed:
                            _isSaving ? null : () => _setAllSelected(false),
                        icon: const Icon(CupertinoIcons.circle, size: 16),
                        label: const Text('清空'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...drafts.asMap().entries.map((entry) {
                    final index = entry.key;
                    final draft = entry.value;
                    final isActive = index == safeIndex;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Builder(
                        builder: (itemContext) => InkWell(
                        onTap: () => setState(() => _activeIndex = index),
                        onLongPress: () => _showDraftMenu(itemContext, index),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isActive
                                ? (isDark
                                    ? const Color(0xFF6366F1)
                                        .withValues(alpha: 0.18)
                                    : const Color(0xFFEEF2FF))
                                : colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isActive
                                  ? (isDark
                                      ? const Color(0xFF6366F1)
                                          .withValues(alpha: 0.45)
                                      : const Color(0xFFC7D2FE))
                                  : colorScheme.outlineVariant,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Transform.scale(
                                scale: 1.05,
                                child: Checkbox(
                                  value: draft.canSave && draft.selected,
                                  onChanged: draft.canSave
                                      ? (value) => _updateDraft(
                                            index,
                                            draft.copyWith(
                                                selected: value ?? false),
                                          )
                                      : null,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4)),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: isActive
                                                ? const Color(0xFF6366F1)
                                                : Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Center(
                                            child: Text(
                                              '${index + 1}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: isActive
                                                    ? Colors.white
                                                    : colorScheme
                                                        .onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: MathContentView(
                                            draft.text.trim().isEmpty
                                                ? '待补充题目内容'
                                                : draft.text,
                                            contentFormat: _mathPreviewFormat,
                                            mode: MathContentViewMode.compact,
                                            maxLines: 1,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: draft.canSave &&
                                                      draft.selected
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .onSurface
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(CupertinoIcons.chevron_right,
                                  size: 18,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant),
                              // Phase 10-4：每条拆分候选题旁加 FieldStatus 徽章，
                              // 直观展示该候选题的识别状态。
                              StatusPill(
                                label: '题${index + 1}',
                                status: draft.text.trim().isEmpty
                                    ? FieldStatus.missing
                                    : (draft.canSave
                                        ? FieldStatus.recognized
                                        : FieldStatus.needsReview),
                              ),
                            ],
                          ),
                        ),
                      ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (activeDraft != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Text('当前题目内容',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        // Phase 10-4：当前激活题目也接 FieldStatus 徽章。
                        StatusPill(
                          label: '当前题',
                          status: activeDraft.text.trim().isEmpty
                              ? FieldStatus.missing
                              : (activeDraft.canSave
                                  ? FieldStatus.recognized
                                  : FieldStatus.needsReview),
                        ),
                        const Spacer(),
                        Text('第 ${safeIndex + 1} 题',
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('支持轻量修改，保存时会按当前内容逐题落库。',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: ValueKey(activeDraft.id),
                      initialValue: _displayEditableText(activeDraft.text),
                      maxLines: 8,
                      minLines: 6,
                      onChanged: (value) => _updateDraft(
                          safeIndex, activeDraft.copyWith(text: value)),
                      decoration: InputDecoration(
                        hintText: '请输入题目内容',
                        filled: true,
                        fillColor: colorScheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color:
                                  Theme.of(context).colorScheme.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color:
                                  Theme.of(context).colorScheme.outlineVariant),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _FormulaPreviewCard(
                      content: activeDraft.text,
                      contentFormat: activeDraft.contentFormat,
                    ),
                  ],
                ),
              ),
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFFDC2626).withValues(alpha: 0.14)
                      : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: isDark
                          ? const Color(0xFFDC2626).withValues(alpha: 0.35)
                          : const Color(0xFFFECACA)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(CupertinoIcons.exclamationmark_triangle,
                        size: 18, color: Color(0xFFDC2626)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? const Color(0xFFDC2626)
                                : const Color(0xFFB91C1C)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
              FilledButton.icon(
                onPressed: _isSaving || selectedCount == 0
                    ? null
                    : () => _saveQuestions(_draftsForSelected(session)),
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.tray_arrow_down, size: 18),
                label:
                    Text(_isSaving ? '正在保存...' : '保存已勾选题目 ($selectedCount)'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50)),
              ),
              const SizedBox(height: 6),
              Text(
                selectedCount == 0
                    ? '请至少勾选一道题后再保存。'
                    : '将保存已勾选的 $selectedCount 道题；未勾选题目不会写入错题本。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateDraft(int index, QuestionSplitDraft updatedDraft) {
    final session = ref.read(currentQuestionSplitSessionProvider);
    if (session == null) return;

    final nextDrafts = [...session.drafts];
    nextDrafts[index] =
        updatedDraft.copyWith(text: _normalizeEditableText(updatedDraft.text));
    ref.read(currentQuestionSplitSessionProvider.notifier).state =
        session.copyWith(drafts: nextDrafts);

    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  /// 长按题目卡片弹出操作菜单：与上一题合并 / 在此处拆分 / 重新切分本题。
  Future<void> _showDraftMenu(BuildContext itemContext, int index) async {
    final renderBox = itemContext.findRenderObject() as RenderBox?;
    final offset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = renderBox?.size ?? Size.zero;
    final action = await showMenu<String>(
      context: itemContext,
      position: RelativeRect.fromLTRB(
        offset.dx + size.width / 2,
        offset.dy + size.height / 2,
        offset.dx + size.width / 2,
        offset.dy + size.height / 2,
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'merge',
          enabled: index > 0,
          child: const Text('与上一题合并'),
        ),
        const PopupMenuItem<String>(
          value: 'split',
          child: Text('在此处拆分'),
        ),
        const PopupMenuItem<String>(
          value: 'resplit',
          child: Text('重新切分本题'),
        ),
      ],
    );
    if (action == null) return;
    if (!mounted) return;
    switch (action) {
      case 'merge':
        _mergeWithPrevious(index);
        break;
      case 'split':
        await _splitAt(index);
        break;
      case 'resplit':
        await _resplitCurrent(index);
        break;
    }
  }

  /// 与上一题合并：把当前题的 text 拼到上一题末尾（中间加换行），删除当前题。
  void _mergeWithPrevious(int index) {
    final session = ref.read(currentQuestionSplitSessionProvider);
    if (session == null || index <= 0 || index >= session.drafts.length) {
      return;
    }
    final current = session.drafts[index];
    final previous = session.drafts[index - 1];
    final mergedText = '${previous.text}\n${current.text}';
    final nextDrafts = [...session.drafts];
    nextDrafts[index - 1] = previous.copyWith(
      text: mergedText,
      selected: previous.selected || current.selected,
    );
    nextDrafts.removeAt(index);
    ref.read(currentQuestionSplitSessionProvider.notifier).state =
        session.copyWith(drafts: nextDrafts);

    setState(() {
      if (_activeIndex >= index) {
        _activeIndex = (_activeIndex - 1).clamp(0, nextDrafts.length - 1);
      }
      _errorMessage = null;
    });
  }

  /// 在此处拆分：弹出对话框让用户输入拆分关键词，在该关键词首次出现处拆成两题。
  Future<void> _splitAt(int index) async {
    final session = ref.read(currentQuestionSplitSessionProvider);
    if (session == null || index < 0 || index >= session.drafts.length) {
      return;
    }
    final draft = session.drafts[index];

    final controller = TextEditingController();
    final keyword = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('在此处拆分'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('输入拆分关键词，将在该关键词首次出现处拆分为两题：'),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 120),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(dialogContext)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      draft.text.isEmpty ? '（空内容）' : draft.text,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: '例如：第2题、2.、(2)',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(controller.text.trim()),
              child: const Text('拆分'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (!mounted) return;
    if (keyword == null || keyword.isEmpty) return;

    final pos = draft.text.indexOf(keyword);
    if (pos <= 0) {
      setState(() => _errorMessage = '未找到关键词「$keyword」，无法拆分');
      return;
    }
    final firstPart = draft.text.substring(0, pos).trim();
    final secondPart = draft.text.substring(pos).trim();
    if (firstPart.isEmpty || secondPart.isEmpty) {
      setState(() => _errorMessage = '拆分后某一部分为空，请换个关键词');
      return;
    }

    final nextDrafts = [...session.drafts];
    // 前半部分保留原 draft id，后半部分新增 draft
    nextDrafts[index] = draft.copyWith(text: firstPart);
    nextDrafts.insert(
      index + 1,
      QuestionSplitDraft(
        id: '${draft.id}-split-${DateTime.now().millisecondsSinceEpoch}',
        text: secondPart,
        selected: draft.selected,
        originalOrder: draft.originalOrder,
        contentFormat: draft.contentFormat,
        canSave: draft.canSave,
        disabledReason: draft.disabledReason,
      ),
    );
    ref.read(currentQuestionSplitSessionProvider.notifier).state =
        session.copyWith(drafts: nextDrafts);
    setState(() => _errorMessage = null);
  }

  /// 重新切分本题：调用 question_split_service 重新切分当前题，可能变成多题。
  Future<void> _resplitCurrent(int index) async {
    final session = ref.read(currentQuestionSplitSessionProvider);
    if (session == null || index < 0 || index >= session.drafts.length) {
      return;
    }
    final draft = session.drafts[index];
    final splitter = ref.read(questionSplitServiceProvider);

    setState(() => _errorMessage = null);
    try {
      final result = await splitter.split(
        draft.text,
        subject: session.source.subject,
      );
      if (!mounted) return;
      if (result.candidates.length <= 1) {
        setState(() => _errorMessage = '未能进一步拆分当前题目');
        return;
      }
      final nextDrafts = [...session.drafts];
      final newDrafts = result.candidates
          .map((candidate) => QuestionSplitDraft(
                id: '${draft.id}-resplit-${candidate.order}',
                text: candidate.text,
                selected: draft.selected,
                originalOrder: draft.originalOrder,
                contentFormat: draft.contentFormat,
                canSave: draft.canSave,
                disabledReason: draft.disabledReason,
              ))
          .toList();
      nextDrafts.replaceRange(index, index + 1, newDrafts);
      ref.read(currentQuestionSplitSessionProvider.notifier).state =
          session.copyWith(drafts: nextDrafts);
      setState(() => _errorMessage = null);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = '重新切分失败：$e');
    }
  }

  void _setAllSelected(bool selected) {
    final session = ref.read(currentQuestionSplitSessionProvider);
    if (session == null) return;
    ref.read(currentQuestionSplitSessionProvider.notifier).state =
        session.copyWith(
      drafts: session.drafts
          .map((draft) => draft.copyWith(
                selected: draft.canSave ? selected : false,
              ))
          .toList(),
    );
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  String _displayEditableText(String text) => text
      .replaceAll(r'\\(', r'\(')
      .replaceAll(r'\\)', r'\)')
      .replaceAll(r'\\[', r'\[')
      .replaceAll(r'\\]', r'\]');

  String _normalizeEditableText(String text) => text
      .replaceAll(r'\\(', r'\(')
      .replaceAll(r'\\)', r'\)')
      .replaceAll(r'\\[', r'\[')
      .replaceAll(r'\\]', r'\]');

  List<QuestionSplitDraft> _draftsForSelected(QuestionSplitSession session) {
    return session.drafts
        .where((draft) => draft.canSave && draft.selected)
        .toList();
  }

  Future<void> _saveQuestions(List<QuestionSplitDraft> draftsToSave) async {
    final session = ref.read(currentQuestionSplitSessionProvider);
    if (session == null || _isSaving) return;

    final normalizedDrafts = draftsToSave
        .map(
            (draft) => draft.copyWith(text: _normalizeEditableText(draft.text)))
        .toList();
    if (normalizedDrafts.isEmpty) {
      setState(() => _errorMessage = '请至少选择一道解析成功的题目后再保存');
      return;
    }

    if (normalizedDrafts.any((draft) => draft.text.trim().isEmpty)) {
      setState(() => _errorMessage = '保存范围内有空内容，请补充后再保存');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final records = normalizedDrafts.asMap().entries.map((entry) {
        return buildSplitQuestionRecord(
          source: session.source,
          draft: entry.value,
          sortOrder: entry.key + 1,
        );
      }).toList();

      final messenger = ScaffoldMessenger.of(context);
      final router = GoRouter.of(context);
      await ref.read(questionRepositoryProvider).saveDrafts(records);
      invalidateQuestionList(ref);
      final worksheet = ref.read(currentWorksheetImportProvider);
      if (worksheet != null) {
        final remaining = worksheet.pages
            .where((page) => page.id != session.source.id)
            .toList();
        await persistWorksheetImport(
          ref,
          remaining.isEmpty ? null : worksheet.copyWith(pages: remaining),
        );
      }
      ref.read(currentQuestionProvider.notifier).state = records.first;
      ref.read(currentQuestionSplitSessionProvider.notifier).state = null;
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('已保存 ${records.length} 道题到错题本'),
          duration: const Duration(seconds: 2),
        ),
      );
      router.go(worksheet == null || worksheet.pages.length <= 1
          ? '/notebook/question/${records.first.id}'
          : '/worksheet/import');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = '保存失败：$e';
      });
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

class _FormulaPreviewCard extends StatelessWidget {
  const _FormulaPreviewCard({required this.content, this.contentFormat});

  final String content;
  final QuestionContentFormat? contentFormat;

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
              : MathContentView(
                  trimmed,
                  contentFormat: contentFormat,
                  style: const TextStyle(fontSize: 14),
                ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.bgColor,
    required this.textColor,
  });

  final String label;
  final Color bgColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 12, color: textColor, fontWeight: FontWeight.w500),
      ),
    );
  }
}

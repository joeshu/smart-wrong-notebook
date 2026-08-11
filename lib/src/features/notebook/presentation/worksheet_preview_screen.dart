import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_type.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';

/// Phase 8-4：试卷预览页。
///
/// 从 [worksheetPreviewQuestionIdsProvider] 读取题目 ID 列表（保留顺序），
/// 用 `ListView.builder` 懒加载渲染每题一卡片：题号 + 题干（MathContentView）
/// + 答题空白区。预览是只读视图，不修改已选题目。
class WorksheetPreviewScreen extends ConsumerStatefulWidget {
  const WorksheetPreviewScreen({super.key});

  @override
  ConsumerState<WorksheetPreviewScreen> createState() =>
      _WorksheetPreviewScreenState();
}

class _WorksheetPreviewScreenState
    extends ConsumerState<WorksheetPreviewScreen> {
  @override
  Widget build(BuildContext context) {
    final ids = ref.watch(worksheetPreviewQuestionIdsProvider);
    final questionsAsync = ref.watch(questionListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(ids.isEmpty ? '试卷预览' : '试卷预览（${ids.length} 题）'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => context.pop(),
        ),
      ),
      body: questionsAsync.when(
        loading: () => const AppListSkeleton(),
        error: (error, _) => AppErrorState(
          error: error,
          onRetry: () => ref.invalidate(questionListProvider),
        ),
        data: (all) {
          if (ids.isEmpty) {
            return AppEmptyState(
              icon: CupertinoIcons.doc_text,
              title: '暂无可预览的题目',
              description: '请返回组卷工作台选择题目后再预览。',
              action: FilledButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(CupertinoIcons.chevron_left),
                label: const Text('返回工作台'),
              ),
            );
          }
          final byId = {for (final q in all) q.id: q};
          final ordered = ids
              .map((id) => byId[id])
              .whereType<QuestionRecord>()
              .toList();
          if (ordered.isEmpty) {
            return const AppEmptyState(
              icon: CupertinoIcons.doc_text,
              title: '题目加载失败',
              description: '所选题目在本地题库中已不存在。',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: ordered.length,
            itemBuilder: (context, index) =>
                _PreviewQuestionCard(index: index, question: ordered[index]),
          );
        },
      ),
    );
  }
}

/// 单题预览卡：题号 + 题干 + 答题空白区。
class _PreviewQuestionCard extends StatelessWidget {
  const _PreviewQuestionCard({
    required this.index,
    required this.question,
  });

  final int index;
  final QuestionRecord question;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = question.normalizedQuestionText.isNotEmpty
        ? question.normalizedQuestionText
        : question.extractedQuestionText;
    final format = question.contentFormat == QuestionContentFormat.latexMixed
        ? QuestionContentFormat.latexMixed
        : QuestionContentFormat.plain;
    final subtitleParts = <String>[
      question.subject.label,
      if (question.learningStage != null) question.learningStage!,
      if (question.source != null) question.source!,
      if (question.questionType != null) question.questionType!.label,
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    subtitleParts.join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 题干渲染：MathContentView 自动处理 LaTeX 混排
            MathContentView(
              text,
              contentFormat: format,
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 16),
            // 答题空白区
            Container(
              width: double.infinity,
              height: 80,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(color: scheme.outlineVariant, width: 2),
                ),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  '解：',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

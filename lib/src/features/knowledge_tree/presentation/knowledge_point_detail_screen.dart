import 'package:flutter/cupertino.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/features/notebook/application/knowledge_point_practice_controller.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/cached_question_image.dart';

/// 知识点详情页（Phase 5-4）。
///
/// 展示单个知识点的面包屑路径、掌握度、统计、关联错题列表与专项练习入口。
class KnowledgePointDetailScreen extends ConsumerStatefulWidget {
  const KnowledgePointDetailScreen({super.key, required this.knowledgePointId});

  final String knowledgePointId;

  @override
  ConsumerState<KnowledgePointDetailScreen> createState() =>
      _KnowledgePointDetailScreenState();
}

class _KnowledgePointDetailScreenState
    extends ConsumerState<KnowledgePointDetailScreen> {
  bool _buildingPractice = false;

  @override
  Widget build(BuildContext context) {
    final detailAsync =
        ref.watch(knowledgePointDetailProvider(widget.knowledgePointId));
    return Scaffold(
      appBar: AppBar(title: const Text('知识点详情')),
      body: detailAsync.when(
        loading: () => const AppLoadingState(),
        error: (e, _) => AppErrorState(message: '加载失败：$e'),
        data: (detail) => _buildBody(context, detail),
      ),
    );
  }

  Widget _buildBody(BuildContext context, KnowledgePointDetail detail) {
    final mastery = detail.mastery;
    final pending = detail.questions
        .where((q) =>
            q.masteryLevel == MasteryLevel.reviewing ||
            q.masteryLevel == MasteryLevel.newQuestion)
        .length;
    final mastered = detail.questions
        .where((q) => q.masteryLevel == MasteryLevel.mastered)
        .length;
    final correctRate = detail.questions.isEmpty
        ? 0.0
        : mastered / detail.questions.length * 100;

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.xxl),
      children: <Widget>[
        // 面包屑 + 名称
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                detail.point.subject?.label ?? '未分类科目',
                style: const TextStyle(fontSize: 12, color: AppColors.slate),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                detail.point.name,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpace.md),
              if (mastery != null) ...<Widget>[
                Row(
                  children: <Widget>[
                    Text('掌握度：',
                        style: TextStyle(
                            color: Colors.grey.shade700, fontSize: 13)),
                    _MasteryBadge(percentage: mastery.masteryPercentage),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: mastery.masteryPercentage / 100,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _masteryColor(mastery.masteryPercentage),
                    ),
                    minHeight: 10,
                  ),
                ),
              ] else
                Text('暂无掌握度数据',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        // 统计三宫格
        Row(
          children: <Widget>[
            Expanded(
                child: _StatCell(
                    label: '错题', value: '${detail.questions.length}')),
            const SizedBox(width: AppSpace.sm),
            Expanded(
                child: _StatCell(label: '待复习', value: '$pending')),
            const SizedBox(width: AppSpace.sm),
            Expanded(
                child: _StatCell(
                    label: '正确率',
                    value: '${correctRate.toStringAsFixed(0)}%')),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        // 专项练习入口
        FilledButton.icon(
          onPressed: detail.questions.isEmpty || _buildingPractice
              ? null
              : () => _startPractice(context, detail),
          icon: _buildingPractice
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(CupertinoIcons.play_fill, size: 18),
          label: Text(_buildingPractice ? '正在生成练习…' : '专项练习（基于该知识点）'),
        ),
        if (detail.questions.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpace.sm),
          // Phase 8-4：将该知识点关联错题送入组卷工作台。
          OutlinedButton.icon(
            onPressed: () {
              ref.read(worksheetDraftQuestionIdsProvider.notifier).state =
                  detail.questions.map((q) => q.id).toList();
              context.go('/worksheet');
            },
            icon: const Icon(CupertinoIcons.rectangle_stack, size: 18),
            label: const Text('加入组卷工作台'),
          ),
          const SizedBox(height: AppSpace.sm),
          // Phase 11-1：把该知识点关联错题 ID 通过路由 query 传给导出工作台。
          OutlinedButton.icon(
            onPressed: () {
              final idsParam =
                  detail.questions.map((q) => q.id).join(',');
              context.push('/settings/export-workbench?ids=$idsParam');
            },
            icon: const Icon(CupertinoIcons.arrow_up_doc, size: 18),
            label: const Text('导出该知识点错题'),
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        // 错题列表
        const AppSectionTitle('关联错题'),
        const SizedBox(height: AppSpace.sm),
        if (detail.questions.isEmpty)
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Center(
                child: Text('该知识点暂无关联错题',
                    style: TextStyle(color: Colors.grey.shade500)),
              ),
            ),
          )
        else
          AppCard(
            child: Column(
              children: <Widget>[
                for (final q in detail.questions)
                  _QuestionRow(
                    question: q,
                    onTap: () {
                      ref.read(currentQuestionProvider.notifier).state = q;
                      context.go('/notebook/question/${q.id}');
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _startPractice(
      BuildContext context, KnowledgePointDetail detail) async {
    setState(() => _buildingPractice = true);
    try {
      final controller =
          KnowledgePointPracticeController(ref.read(aiAnalysisServiceProvider));
      final prepared = await controller.buildRound(
        knowledgePoint: detail.point.name,
        questions: detail.questions,
      );
      await ref.read(questionRepositoryProvider).update(prepared);
      invalidateQuestionList(ref);
      ref.read(currentPracticeContextProvider.notifier).state = PracticeContext(
        source: PracticeContextSource.notebook,
        returnRoute: '/knowledge-tree',
      );
      ref.read(currentQuestionProvider.notifier).state = prepared;
      if (!mounted) return;
      context.go('/exercise/practice');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成练习失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _buildingPractice = false);
    }
  }

  Color _masteryColor(double pct) {
    if (pct >= 86) return const Color(0xFF059669);
    if (pct >= 61) return const Color(0xFF10B981);
    if (pct >= 31) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }
}

class _MasteryBadge extends StatelessWidget {
  const _MasteryBadge({required this.percentage});
  final double percentage;

  @override
  Widget build(BuildContext context) {
    Color color;
    if (percentage >= 86) {
      color = const Color(0xFF059669);
    } else if (percentage >= 61) {
      color = const Color(0xFF10B981);
    } else if (percentage >= 31) {
      color = const Color(0xFFF59E0B);
    } else {
      color = const Color(0xFFEF4444);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${percentage.toStringAsFixed(0)}%',
        style: TextStyle(
            color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
        child: Column(
          children: <Widget>[
            Text(value,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.slate)),
          ],
        ),
      ),
    );
  }
}

class _QuestionRow extends StatelessWidget {
  const _QuestionRow({required this.question, required this.onTap});
  final QuestionRecord question;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final masteryLabel = switch (question.masteryLevel) {
      MasteryLevel.mastered => '已掌握',
      MasteryLevel.reviewing => '复习中',
      MasteryLevel.newQuestion => '新题',
    };
    final masteryColor = switch (question.masteryLevel) {
      MasteryLevel.mastered => const Color(0xFF10B981),
      MasteryLevel.reviewing => const Color(0xFFF59E0B),
      MasteryLevel.newQuestion => const Color(0xFFEF4444),
    };
    return ListTile(
      dense: true,
      leading: question.imagePath.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 44,
                height: 44,
                child: CachedQuestionImage(
                  question.imagePath,
                  filename: question.id,
                  fit: BoxFit.cover,
                ),
              ),
            )
          : null,
      title: Text(
        question.correctedText.isEmpty
            ? question.normalizedQuestionText
            : question.correctedText,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        '${question.subject.label} · $masteryLabel',
        style: TextStyle(fontSize: 12, color: masteryColor),
      ),
      trailing: const Icon(CupertinoIcons.chevron_right, size: 16, color: AppColors.slate),
      onTap: onTap,
    );
  }
}

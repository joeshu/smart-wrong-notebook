import 'package:flutter/cupertino.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/core/constants/app_strings.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

/// 「知识树」Tab 根页面（Phase 5）。
///
/// 展示受控知识点树的层级结构、掌握度热力图、薄弱知识点 TOP5
/// 与全局掌握度分布。点击节点跳转知识点详情页。
class KnowledgeTreeScreen extends ConsumerStatefulWidget {
  const KnowledgeTreeScreen({super.key});

  @override
  ConsumerState<KnowledgeTreeScreen> createState() =>
      _KnowledgeTreeScreenState();
}

class _KnowledgeTreeScreenState extends ConsumerState<KnowledgeTreeScreen> {
  Subject? _selectedSubject;

  @override
  Widget build(BuildContext context) {
    final overviewAsync = ref.watch(knowledgeTreeOverviewProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.knowledgeTreeTab),
        actions: <Widget>[
          IconButton(
            icon: const Icon(CupertinoIcons.pencil),
            tooltip: '管理知识树',
            onPressed: () => context.push('/knowledge-tree/manage'),
          ),
        ],
      ),
      body: overviewAsync.when(
        loading: () => const AppLoadingState(),
        error: (e, _) => AppErrorState(message: '知识树加载失败：$e'),
        data: (overview) => _buildBody(context, overview),
      ),
    );
  }

  Widget _buildBody(BuildContext context, KnowledgeTreeOverview overview) {
    if (overview.nodes.isEmpty) {
      return const AppEmptyState(
        icon: CupertinoIcons.tree,
        title: '暂无知识点',
        description: '添加错题并由 AI 分析后，知识点会自动归类到这里。',
      );
    }
    final filtered = _filterBySubject(overview.nodes);
    // 按 parentId 构建树
    final roots = filtered.where((n) => n.point.isRoot).toList()
      ..sort((a, b) => a.point.sortOrder.compareTo(b.point.sortOrder));
    final byParent = <String, List<KnowledgeTreeNodeView>>{};
    for (final n in filtered) {
      if (n.point.parentId != null) {
        byParent.putIfAbsent(n.point.parentId!, () => []).add(n);
      }
    }
    for (final list in byParent.values) {
      list.sort((a, b) => a.point.sortOrder.compareTo(b.point.sortOrder));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.xxl),
      children: <Widget>[
        _SubjectFilter(
          selected: _selectedSubject,
          onChanged: (s) => setState(() => _selectedSubject = s),
        ),
        const SizedBox(height: AppSpace.md),
        _MasteryDistributionCard(
          mastered: overview.masteredCount,
          reviewing: overview.reviewingCount,
          newCount: overview.newCount,
        ),
        const SizedBox(height: AppSpace.md),
        _WeakTopCard(weakTop5: overview.weakTop5),
        const SizedBox(height: AppSpace.md),
        const AppSectionTitle('知识树'),
        const SizedBox(height: AppSpace.sm),
        AppCard(
          child: Column(
            children: <Widget>[
              for (final root in roots)
                _KnowledgeTreeTile(
                  node: root,
                  byParent: byParent,
                  depth: 0,
                  onTap: (n) => _openDetail(context, n),
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<KnowledgeTreeNodeView> _filterBySubject(
      List<KnowledgeTreeNodeView> nodes) {
    if (_selectedSubject == null) return nodes;
    // 保留指定科目节点 + 其子孙（通过 parentId 链回溯到根判断）
    final byId = {for (final n in nodes) n.point.id: n};
    bool matchesSubject(KnowledgePoint kp) {
      if (kp.subject == _selectedSubject) return true;
      var current = kp;
      while (current.parentId != null) {
        final parent = byId[current.parentId]?.point;
        if (parent == null) return false;
        if (parent.subject == _selectedSubject) return true;
        current = parent;
      }
      return false;
    }
    return nodes.where((n) => matchesSubject(n.point)).toList();
  }

  void _openDetail(BuildContext context, KnowledgeTreeNodeView node) {
    context.push('/knowledge-tree/detail/${node.point.id}');
  }
}

/// 科目筛选 chip 行。
class _SubjectFilter extends StatelessWidget {
  const _SubjectFilter({required this.selected, required this.onChanged});

  final Subject? selected;
  final ValueChanged<Subject?> onChanged;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      _Chip(
        label: '全部',
        selected: selected == null,
        onTap: () => onChanged(null),
      ),
      for (final s in Subject.values)
        _Chip(
          label: s.label,
          selected: selected == s,
          onTap: () => onChanged(s),
        ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: chips),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpace.sm),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: scheme.primaryContainer,
        labelStyle: TextStyle(
          color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// 全局掌握度分布卡。
class _MasteryDistributionCard extends StatelessWidget {
  const _MasteryDistributionCard({
    required this.mastered,
    required this.reviewing,
    required this.newCount,
  });

  final int mastered;
  final int reviewing;
  final int newCount;

  @override
  Widget build(BuildContext context) {
    final total = mastered + reviewing + newCount;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const AppSectionTitle('掌握度分布'),
          const SizedBox(height: AppSpace.sm),
          if (total == 0)
            const Text('暂无题目数据', style: TextStyle(color: AppColors.slate))
          else ...<Widget>[
            _DistributionBar(
              label: '掌握',
              count: mastered,
              total: total,
              color: const Color(0xFF10B981),
            ),
            const SizedBox(height: AppSpace.xs),
            _DistributionBar(
              label: '一般',
              count: reviewing,
              total: total,
              color: const Color(0xFFF59E0B),
            ),
            const SizedBox(height: AppSpace.xs),
            _DistributionBar(
              label: '模糊',
              count: newCount,
              total: total,
              color: const Color(0xFFEF4444),
            ),
          ],
        ],
      ),
    );
  }
}

class _DistributionBar extends StatelessWidget {
  const _DistributionBar({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : count / total;
    return Row(
      children: <Widget>[
        SizedBox(width: 40, child: Text(label)),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        SizedBox(
          width: 72,
          child: Text(
            '$count 题 · ${(ratio * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 12, color: AppColors.slate),
          ),
        ),
      ],
    );
  }
}

/// 薄弱知识点 TOP5 卡。
class _WeakTopCard extends StatelessWidget {
  const _WeakTopCard({required this.weakTop5});

  final List<KnowledgeTreeNodeView> weakTop5;

  @override
  Widget build(BuildContext context) {
    if (weakTop5.isEmpty) return const SizedBox.shrink();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const AppSectionTitle('薄弱知识点 TOP5'),
          const SizedBox(height: AppSpace.sm),
          for (var i = 0; i < weakTop5.length; i++)
            _WeakTile(index: i + 1, node: weakTop5[i]),
        ],
      ),
    );
  }
}

class _WeakTile extends StatelessWidget {
  const _WeakTile({required this.index, required this.node});
  final int index;
  final KnowledgeTreeNodeView node;

  @override
  Widget build(BuildContext context) {
    final pct = node.masteryPercentage ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 20,
            child: Text('$index',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text(node.point.name)),
          _MasteryPill(percentage: pct),
          const SizedBox(width: AppSpace.sm),
          if (node.mastery != null)
            Text(
              '${node.mastery!.totalQuestions} 错题',
              style: const TextStyle(fontSize: 12, color: AppColors.slate),
            ),
        ],
      ),
    );
  }
}

/// 递归树节点 Tile。
class _KnowledgeTreeTile extends StatefulWidget {
  const _KnowledgeTreeTile({
    required this.node,
    required this.byParent,
    required this.depth,
    required this.onTap,
  });

  final KnowledgeTreeNodeView node;
  final Map<String, List<KnowledgeTreeNodeView>> byParent;
  final int depth;
  final ValueChanged<KnowledgeTreeNodeView> onTap;

  @override
  State<_KnowledgeTreeTile> createState() => _KnowledgeTreeTileState();
}

class _KnowledgeTreeTileState extends State<_KnowledgeTreeTile> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final children = widget.byParent[widget.node.point.id] ?? const <KnowledgeTreeNodeView>[];
    final hasChildren = children.isNotEmpty;
    final mastery = widget.node.mastery;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          onTap: () => widget.onTap(widget.node),
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: widget.depth * 16.0 + 8,
              top: AppSpace.sm,
              bottom: AppSpace.sm,
              end: AppSpace.sm,
            ),
            child: Row(
              children: <Widget>[
                if (hasChildren)
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Icon(
                      _expanded
                          ? CupertinoIcons.chevron_down
                          : CupertinoIcons.chevron_right,
                      size: 16,
                      color: AppColors.slate,
                    ),
                  )
                else
                  const SizedBox(width: 16),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                    child: Text(widget.node.point.name,
                        style: const TextStyle(fontSize: 14))),
                if (mastery != null) ...<Widget>[
                  _MasteryPill(percentage: mastery.masteryPercentage),
                  const SizedBox(width: AppSpace.sm),
                  Text(
                    '${mastery.totalQuestions} 题',
                    style: const TextStyle(fontSize: 12, color: AppColors.slate),
                  ),
                ] else
                  Text(
                    '无题',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
              ],
            ),
          ),
        ),
        if (hasChildren && _expanded)
          for (final child in children)
            _KnowledgeTreeTile(
              node: child,
              byParent: widget.byParent,
              depth: widget.depth + 1,
              onTap: widget.onTap,
            ),
      ],
    );
  }
}

/// 掌握度百分比胶囊（4 档热力图配色）。
class _MasteryPill extends StatelessWidget {
  const _MasteryPill({required this.percentage});
  final double percentage;

  @override
  Widget build(BuildContext context) {
    final color = _masteryColor(percentage);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '${percentage.toStringAsFixed(0)}%',
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// 4 档颜色映射：0-30 红 / 31-60 橙 / 61-85 绿 / 86-100 深绿。
  static Color _masteryColor(double pct) {
    if (pct >= 86) return const Color(0xFF059669);
    if (pct >= 61) return const Color(0xFF10B981);
    if (pct >= 31) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }
}

import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point_seed.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point_template.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

/// 知识树管理页面（Phase 9-1）。
///
/// 接入 [KnowledgePointManagementService]，提供新增 / 重命名 / 移动 / 合并 /
/// 删除 / 启用停用 等树形编辑能力。入口：知识树页面 AppBar 编辑按钮。
class KnowledgeTreeManagementScreen extends ConsumerStatefulWidget {
  const KnowledgeTreeManagementScreen({super.key});

  @override
  ConsumerState<KnowledgeTreeManagementScreen> createState() =>
      _KnowledgeTreeManagementScreenState();
}

class _KnowledgeTreeManagementScreenState
    extends ConsumerState<KnowledgeTreeManagementScreen> {
  @override
  Widget build(BuildContext context) {
    // watch knowledgePointTreeProvider：含已停用节点，受版本号触发刷新。
    final treeAsync = ref.watch(knowledgePointTreeProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('知识树管理'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => context.pop(),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(CupertinoIcons.add_circled),
            tooltip: '新增根节点',
            onPressed: () => _createNode(parent: null),
          ),
          PopupMenuButton<String>(
            icon: const Icon(CupertinoIcons.ellipsis_circle),
            tooltip: '更多操作',
            onSelected: (value) {
              switch (value) {
                case 'apply_template':
                  _openTemplateDialog();
                  break;
                case 'export_json':
                  _exportAsJson();
                  break;
                case 'reset_default':
                  _resetToDefault();
                  break;
              }
            },
            itemBuilder: (ctx) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'apply_template',
                child: Row(children: <Widget>[
                  Icon(CupertinoIcons.rectangle_stack, size: 20),
                  SizedBox(width: 12),
                  Text('应用模板'),
                ]),
              ),
              const PopupMenuItem<String>(
                value: 'export_json',
                child: Row(children: <Widget>[
                  Icon(CupertinoIcons.square_arrow_up, size: 20),
                  SizedBox(width: 12),
                  Text('导出为 JSON'),
                ]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'reset_default',
                child: Row(children: <Widget>[
                  Icon(CupertinoIcons.refresh, color: AppColors.warning, size: 20),
                  SizedBox(width: 12),
                  Text('重置为默认', style: TextStyle(color: AppColors.warning)),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: treeAsync.when(
        loading: () => const AppLoadingState(),
        error: (e, _) => AppErrorState(message: '加载失败：$e'),
        data: (points) {
          if (points.isEmpty) {
            return AppEmptyState(
              icon: CupertinoIcons.tree,
              title: '暂无知识点',
              description: '点击右上角"新增根节点"开始构建你的知识树。',
              action: FilledButton.icon(
                onPressed: () => _createNode(parent: null),
                icon: const Icon(CupertinoIcons.add, size: 18),
                label: const Text('新增根节点'),
              ),
            );
          }
          return _buildBody(points);
        },
      ),
    );
  }

  Widget _buildBody(List<KnowledgePoint> points) {
    final roots = points.where((p) => p.isRoot).toList()
      ..sort((a, b) {
        final cmp = a.sortOrder.compareTo(b.sortOrder);
        if (cmp != 0) return cmp;
        return a.name.compareTo(b.name);
      });
    final byParent = <String, List<KnowledgePoint>>{};
    for (final p in points) {
      if (p.parentId != null) {
        byParent.putIfAbsent(p.parentId!, () => <KnowledgePoint>[]).add(p);
      }
    }
    for (final list in byParent.values) {
      list.sort((a, b) {
        final cmp = a.sortOrder.compareTo(b.sortOrder);
        if (cmp != 0) return cmp;
        return a.name.compareTo(b.name);
      });
    }
    final enabledCount = points.where((p) => p.enabled).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.xxl),
      children: <Widget>[
        AppCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md, vertical: AppSpace.sm),
            child: Row(
              children: <Widget>[
                const Icon(CupertinoIcons.info_circle,
                    size: 16, color: AppColors.slate),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    '共 ${points.length} 个知识点（已启用 $enabledCount）',
                    style: const TextStyle(fontSize: 13, color: AppColors.slate),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        AppCard(
          child: Column(
            children: <Widget>[
              for (final root in roots)
                _ManagementTile(
                  point: root,
                  byParent: byParent,
                  depth: 0,
                  onMenu: (point) => _openNodeMenu(point, points),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // --- 操作入口 ---

  Future<void> _createNode({required KnowledgePoint? parent}) async {
    final result = await showDialog<_NodeEditResult>(
      context: context,
      builder: (ctx) => _NodeEditDialog(
        title: parent == null ? '新增根节点' : '新增子节点',
        initialName: '',
        initialSubject: parent?.subject,
        parentName: parent?.name,
      ),
    );
    if (result == null || result.name.trim().isEmpty) return;
    final svc = ref.read(knowledgePointManagementServiceProvider);
    await svc.create(
      name: result.name.trim(),
      parentId: parent?.id,
      subject: result.subject,
    );
    invalidateKnowledgePointTree(ref);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已新增知识点「${result.name.trim()}」')),
    );
  }

  Future<void> _renameNode(KnowledgePoint point) async {
    final result = await showDialog<_NodeEditResult>(
      context: context,
      builder: (ctx) => _NodeEditDialog(
        title: '重命名',
        initialName: point.name,
        initialSubject: point.subject,
        nameOnly: true,
      ),
    );
    if (result == null || result.name.trim().isEmpty) return;
    final svc = ref.read(knowledgePointManagementServiceProvider);
    await svc.rename(point.id, result.name.trim());
    invalidateKnowledgePointTree(ref);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已重命名')),
    );
  }

  Future<void> _toggleEnabled(KnowledgePoint point) async {
    final svc = ref.read(knowledgePointManagementServiceProvider);
    await svc.setEnabled(point.id, !point.enabled);
    invalidateKnowledgePointTree(ref);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(point.enabled ? '已停用' : '已启用')),
    );
  }

  Future<void> _moveNode(KnowledgePoint point, List<KnowledgePoint> all) async {
    final descendants = _collectDescendants(point, all);
    final candidates = <KnowledgePoint>[]
      ..addAll(all.where((p) =>
          p.id != point.id && !descendants.contains(p.id)))
      ..sort((a, b) {
        final cmp = (a.sortOrder).compareTo(b.sortOrder);
        if (cmp != 0) return cmp;
        return a.name.compareTo(b.name);
      });
    final newParentId = await showDialog<String>(
      context: context,
      builder: (ctx) => _ParentPickerDialog(
        title: '移动到...',
        candidates: candidates,
        currentParentId: point.parentId,
      ),
    );
    if (newParentId == null) return;
    // "_root_" 表示用户选了"作为根节点"
    final targetId = newParentId == _rootSentinel ? null : newParentId;
    if (targetId == point.parentId) return;
    final svc = ref.read(knowledgePointManagementServiceProvider);
    try {
      await svc.move(point.id, targetId);
      invalidateKnowledgePointTree(ref);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已移动')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('移动失败：$e')),
      );
    }
  }

  Future<void> _mergeNode(KnowledgePoint point, List<KnowledgePoint> all) async {
    final candidates = <KnowledgePoint>[]
      ..addAll(all.where((p) => p.id != point.id))
      ..sort((a, b) => a.name.compareTo(b.name));
    final targetId = await showDialog<String>(
      context: context,
      builder: (ctx) => _ParentPickerDialog(
        title: '合并到...',
        candidates: candidates,
        currentParentId: null,
        mergeMode: true,
        sourceName: point.name,
      ),
    );
    if (targetId == null || targetId == _rootSentinel) return;
    final confirmed = await _confirm(
      title: '确认合并',
      content: '将「${point.name}」合并到「${all.firstWhere((p) => p.id == targetId).name}」？\n'
          '「${point.name}」的子节点会转移到目标下，知识点本身会被删除。该操作不可撤销。',
      danger: true,
    );
    if (!confirmed) return;
    final svc = ref.read(knowledgePointManagementServiceProvider);
    try {
      await svc.merge(point.id, targetId);
      invalidateKnowledgePointTree(ref);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已合并')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('合并失败：$e')),
      );
    }
  }

  Future<void> _deleteNode(KnowledgePoint point) async {
    final confirmed = await _confirm(
      title: '确认删除',
      content: '删除知识点「${point.name}」？\n'
          '其子节点会保留并升级为父节点的直接子节点。该操作不可撤销。',
      danger: true,
    );
    if (!confirmed) return;
    final svc = ref.read(knowledgePointManagementServiceProvider);
    final ok = await svc.delete(point.id);
    invalidateKnowledgePointTree(ref);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已删除' : '知识点不存在，未删除')),
    );
  }

  // --- Phase 9-2 模板操作 ---

  /// 应用模板：选择模板 → 选 replace/merge → 执行。
  Future<void> _openTemplateDialog() async {
    final templates = KnowledgePointTemplateRegistry.builtins();
    final template = await showDialog<KnowledgePointTemplate>(
      context: context,
      builder: (ctx) => _TemplatePickerDialog(templates: templates),
    );
    if (template == null || !mounted) return;
    final mode = await showDialog<TemplateApplyMode>(
      context: context,
      builder: (ctx) => _TemplatePreviewDialog(template: template),
    );
    if (mode == null || !mounted) return;
    final confirmed = await _confirm(
      title: mode == TemplateApplyMode.replace ? '覆盖知识树' : '合并知识树',
      content: mode == TemplateApplyMode.replace
          ? '将清空当前所有知识点，并应用「${template.name}」（共 ${template.points.length} 个）。该操作不可撤销。'
          : '将「${template.name}」中 ${template.points.length} 个知识点按 ID 合并到当前知识树（已存在的 ID 跳过）。',
      danger: mode == TemplateApplyMode.replace,
    );
    if (!confirmed) return;
    final repo = ref.read(knowledgePointRepositoryProvider);
    if (mode == TemplateApplyMode.replace) {
      await repo.saveAll(template.points);
    } else {
      final existing = await repo.loadAll();
      final existingIds = existing.map((p) => p.id).toSet();
      final toAdd = template.points
          .where((p) => !existingIds.contains(p.id))
          .toList();
      if (toAdd.isNotEmpty) {
        await repo.upsertAll(toAdd);
      }
    }
    invalidateKnowledgePointTree(ref);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已应用模板「${template.name}」')),
    );
  }

  /// 导出当前知识树为 JSON，显示在对话框中并复制到剪贴板。
  Future<void> _exportAsJson() async {
    final svc = ref.read(knowledgePointManagementServiceProvider);
    final all = await svc.all();
    if (all.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前知识树为空，无内容可导出')),
      );
      return;
    }
    final json = const JsonEncoder.withIndent('  ')
        .convert(all.map((p) => p.toJson()).toList());
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _JsonExportDialog(json: json, count: all.length),
    );
  }

  /// 重置为默认：二次确认 → 全量覆盖为 KnowledgePointSeed.builtins()。
  Future<void> _resetToDefault() async {
    final confirmed = await _confirm(
      title: '重置为默认',
      content: '将清空当前所有知识点，并恢复为内置默认目录（${KnowledgePointSeed.builtins().length} 个）。该操作不可撤销。',
      danger: true,
    );
    if (!confirmed) return;
    final repo = ref.read(knowledgePointRepositoryProvider);
    await repo.saveAll(KnowledgePointSeed.builtins());
    invalidateKnowledgePointTree(ref);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已重置为默认知识树')),
    );
  }

  // --- 辅助 ---

  Set<String> _collectDescendants(KnowledgePoint point, List<KnowledgePoint> all) {
    final byParent = <String, List<KnowledgePoint>>{};
    for (final p in all) {
      if (p.parentId != null) {
        byParent.putIfAbsent(p.parentId!, () => <KnowledgePoint>[]).add(p);
      }
    }
    final result = <String>{};
    void visit(String id) {
      for (final child in byParent[id] ?? const <KnowledgePoint>[]) {
        if (result.add(child.id)) visit(child.id);
      }
    }
    visit(point.id);
    return result;
  }

  Future<void> _openNodeMenu(
      KnowledgePoint point, List<KnowledgePoint> all) async {
    final action = await showModalBottomSheet<_NodeAction>(
      context: context,
      builder: (ctx) => _NodeActionSheet(point: point),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _NodeAction.add:
        await _createNode(parent: point);
      case _NodeAction.rename:
        await _renameNode(point);
      case _NodeAction.move:
        await _moveNode(point, all);
      case _NodeAction.merge:
        await _mergeNode(point, all);
      case _NodeAction.toggle:
        await _toggleEnabled(point);
      case _NodeAction.delete:
        await _deleteNode(point);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String content,
    bool danger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// "作为根节点"选项的哨兵值，避免与真实 ID 冲突。
const String _rootSentinel = '__root__';

/// 节点操作菜单项。
enum _NodeAction { add, rename, move, merge, toggle, delete }

/// 节点编辑对话框返回结果。
class _NodeEditResult {
  _NodeEditResult({required this.name, this.subject});
  final String name;
  final Subject? subject;
}

/// 递归树节点 Tile（管理版）。
class _ManagementTile extends StatefulWidget {
  const _ManagementTile({
    required this.point,
    required this.byParent,
    required this.depth,
    required this.onMenu,
  });

  final KnowledgePoint point;
  final Map<String, List<KnowledgePoint>> byParent;
  final int depth;
  final ValueChanged<KnowledgePoint> onMenu;

  @override
  State<_ManagementTile> createState() => _ManagementTileState();
}

class _ManagementTileState extends State<_ManagementTile> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final children =
        widget.byParent[widget.point.id] ?? const <KnowledgePoint>[];
    final hasChildren = children.isNotEmpty;
    final point = widget.point;
    final disabled = !point.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          onTap: () => widget.onMenu(point),
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
                  child: Text(
                    point.name,
                    style: TextStyle(
                      fontSize: 14,
                      color: disabled ? Colors.grey.shade500 : null,
                      decoration: disabled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                if (point.subject != null) ...<Widget>[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: point.subject!.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      point.subject!.label,
                      style: TextStyle(
                        fontSize: 12,
                        color: point.subject!.color,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.xs),
                ],
                if (disabled)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text(
                      '已停用',
                      style: TextStyle(fontSize: 12, color: AppColors.slate),
                    ),
                  ),
                IconButton(
                  icon: const Icon(CupertinoIcons.ellipsis_circle, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 32, minHeight: 32),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => widget.onMenu(point),
                ),
              ],
            ),
          ),
        ),
        if (hasChildren && _expanded)
          for (final child in children)
            _ManagementTile(
              point: child,
              byParent: widget.byParent,
              depth: widget.depth + 1,
              onMenu: widget.onMenu,
            ),
      ],
    );
  }
}

/// 节点操作 ActionSheet。
class _NodeActionSheet extends StatelessWidget {
  const _NodeActionSheet({required this.point});
  final KnowledgePoint point;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
                vertical: AppSpace.sm, horizontal: AppSpace.lg),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                point.name,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.slate),
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading:
                const Icon(CupertinoIcons.add_circled, color: AppColors.primary),
            title: const Text('新增子节点'),
            onTap: () => Navigator.pop(context, _NodeAction.add),
          ),
          ListTile(
            leading: const Icon(CupertinoIcons.pencil, color: AppColors.info),
            title: const Text('重命名'),
            onTap: () => Navigator.pop(context, _NodeAction.rename),
          ),
          ListTile(
            leading: const Icon(CupertinoIcons.folder,
                color: AppColors.accentTeal),
            title: const Text('移动到...'),
            onTap: () => Navigator.pop(context, _NodeAction.move),
          ),
          ListTile(
            leading: const Icon(CupertinoIcons.link,
                color: AppColors.accentPurple),
            title: const Text('合并到...'),
            onTap: () => Navigator.pop(context, _NodeAction.merge),
          ),
          ListTile(
            leading: Icon(
              point.enabled
                  ? CupertinoIcons.pause_circle
                  : CupertinoIcons.play_circle,
              color: AppColors.warning,
            ),
            title: Text(point.enabled ? '停用' : '启用'),
            onTap: () => Navigator.pop(context, _NodeAction.toggle),
          ),
          ListTile(
            leading: const Icon(CupertinoIcons.delete, color: AppColors.danger),
            title: const Text('删除',
                style: TextStyle(color: AppColors.danger)),
            onTap: () => Navigator.pop(context, _NodeAction.delete),
          ),
          const SizedBox(height: AppSpace.sm),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}

/// 新增 / 重命名对话框。
class _NodeEditDialog extends StatefulWidget {
  const _NodeEditDialog({
    required this.title,
    required this.initialName,
    required this.initialSubject,
    this.parentName,
    this.nameOnly = false,
  });

  final String title;
  final String initialName;
  final Subject? initialSubject;
  final String? parentName;
  final bool nameOnly;

  @override
  State<_NodeEditDialog> createState() => _NodeEditDialogState();
}

class _NodeEditDialogState extends State<_NodeEditDialog> {
  late final TextEditingController _nameController;
  Subject? _subject;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _subject = widget.initialSubject;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (widget.parentName != null) ...<Widget>[
            Text('父节点：${widget.parentName}',
                style: const TextStyle(fontSize: 12, color: AppColors.slate)),
            const SizedBox(height: AppSpace.sm),
          ],
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '名称',
              border: OutlineInputBorder(),
            ),
          ),
          if (!widget.nameOnly) ...<Widget>[
            const SizedBox(height: AppSpace.md),
            const Text('科目（可选）',
                style: TextStyle(fontSize: 12, color: AppColors.slate)),
            const SizedBox(height: AppSpace.xs),
            DropdownButtonFormField<Subject?>(
              value: _subject,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: <DropdownMenuItem<Subject?>>[
                const DropdownMenuItem<Subject?>(
                  value: null,
                  child: Text('不指定'),
                ),
                for (final s in Subject.values)
                  DropdownMenuItem<Subject?>(
                    value: s,
                    child: Text(s.label),
                  ),
              ],
              onChanged: (v) => setState(() => _subject = v),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              _NodeEditResult(
                name: _nameController.text,
                subject: _subject,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 父节点选择对话框（移动 / 合并用）。
class _ParentPickerDialog extends StatelessWidget {
  const _ParentPickerDialog({
    required this.title,
    required this.candidates,
    required this.currentParentId,
    this.mergeMode = false,
    this.sourceName,
  });

  final String title;
  final List<KnowledgePoint> candidates;
  final String? currentParentId;
  final bool mergeMode;
  final String? sourceName;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (sourceName != null) ...<Widget>[
              Text(
                mergeMode
                    ? '源节点：$sourceName'
                    : '当前父节点：${currentParentId == null ? "（根节点）" : currentParentId}',
                style: const TextStyle(fontSize: 12, color: AppColors.slate),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  if (!mergeMode)
                    ListTile(
                      leading:
                          const Icon(CupertinoIcons.tray, color: AppColors.slate),
                      title: const Text('作为根节点'),
                      onTap: () =>
                          Navigator.pop(context, _rootSentinel),
                    ),
                  for (final p in candidates)
                    ListTile(
                      dense: true,
                      title: Text(p.name),
                      subtitle: Text(
                        p.subject?.label ?? '未指定科目',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: p.id == currentParentId
                          ? const Text('当前',
                              style:
                                  TextStyle(fontSize: 12, color: AppColors.slate))
                          : null,
                      onTap: () => Navigator.pop(context, p.id),
                    ),
                ],
              ),
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

/// 模板选择对话框（Phase 9-2）。
class _TemplatePickerDialog extends StatelessWidget {
  const _TemplatePickerDialog({required this.templates});
  final List<KnowledgePointTemplate> templates;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('应用模板'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final t in templates)
              ListTile(
                leading: const Icon(CupertinoIcons.rectangle_stack,
                    color: AppColors.primary),
                title: Text(t.name),
                subtitle: Text(
                  '${t.description}\n根节点 ${t.rootCount} · 共 ${t.points.length} 个',
                  style: const TextStyle(fontSize: 11),
                ),
                isThreeLine: true,
                onTap: () => Navigator.pop(context, t),
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

/// 模板预览 + 应用方式选择对话框。
class _TemplatePreviewDialog extends StatelessWidget {
  const _TemplatePreviewDialog({required this.template});
  final KnowledgePointTemplate template;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('应用「${template.name}」'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(template.description,
              style: const TextStyle(fontSize: 13, color: AppColors.slate)),
          const SizedBox(height: AppSpace.sm),
          Text('根节点 ${template.rootCount} · 共 ${template.points.length} 个知识点',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: AppSpace.md),
          const Text('选择应用方式：',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpace.xs),
          ListTile(
            dense: true,
            leading: const Icon(CupertinoIcons.refresh,
                color: AppColors.danger),
            title: const Text('覆盖'),
            subtitle: const Text('清空当前所有知识点，写入模板内容', style: TextStyle(fontSize: 11)),
            onTap: () => Navigator.pop(context, TemplateApplyMode.replace),
          ),
          ListTile(
            dense: true,
            leading: const Icon(CupertinoIcons.plus_app,
                color: AppColors.success),
            title: const Text('合并'),
            subtitle: const Text('保留当前知识点，按 ID 合并（已存在跳过）',
                style: TextStyle(fontSize: 11)),
            onTap: () => Navigator.pop(context, TemplateApplyMode.merge),
          ),
        ],
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

/// JSON 导出对话框：显示 JSON 文本 + 复制按钮。
class _JsonExportDialog extends StatelessWidget {
  const _JsonExportDialog({required this.json, required this.count});
  final String json;
  final int count;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('已导出 $count 个知识点'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Icon(CupertinoIcons.checkmark_circle_fill,
                    color: AppColors.success, size: 16),
                SizedBox(width: AppSpace.xs),
                Text('JSON 已复制到剪贴板',
                    style: TextStyle(fontSize: 12, color: AppColors.success)),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Container(
              constraints: const BoxConstraints(maxHeight: 280),
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  json,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: json));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已再次复制到剪贴板')),
              );
            }
          },
          child: const Text('再次复制'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

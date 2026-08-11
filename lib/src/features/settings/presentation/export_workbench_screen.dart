import 'dart:io';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/repositories/knowledge_point_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_knowledge_link_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/shared/utils/app_share_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/anki_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/csv_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_content_options.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_file_preview_screen.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_file_writer.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_history_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_options_dialog.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_template.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_preview_screen.dart';
import 'package:smart_wrong_notebook/src/shared/utils/json_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/markdown_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/pdf_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/worksheet_export_mode.dart';

/// 导出工作台支持的输出格式。
enum ExportFormat { html, pdf, markdown, anki, csv, json }

/// 导出工作台：集中所有导出能力的统一入口页。
///
/// 页面分区（自上而下）：
/// 1. 模板选择：错题报告 / 学习报告 / 复习卡
/// 2. 格式选择：HTML / PDF / Markdown / Anki / CSV / JSON（HTML 与 PDF 互斥）
/// 3. 筛选与内容选项：调用 [showExportOptionsDialog] 复用既有对话框
/// 4. 排版选项：仅当选中 PDF 时展示，复用 [PdfLayoutOptions]
/// 5. 预览：仅当选中 HTML 时可用，跳转 [HtmlPreviewScreen]
/// 6. 导出：底部 sticky 按钮，按选中格式依次调用对应导出服务
class ExportWorkbenchScreen extends ConsumerStatefulWidget {
  const ExportWorkbenchScreen({
    super.key,
    this.initialQuestionIds = const <String>[],
    this.showBackButton = false,
  });

  /// 入口页预填的题目 ID 列表。
  ///
  /// 由"导出选中题""导出本组卷""导出该知识点错题"等入口通过路由 query
  /// 传入，工作台首帧会用该集合在题库中筛出对应题目并自动构造一份
  /// [ExportOptions]，跳过用户手动点开筛选对话框的步骤。空集合表示
  /// 不预填，沿用原"默认导出全部题目"的行为。
  final List<String> initialQuestionIds;
  final bool showBackButton;

  @override
  ConsumerState<ExportWorkbenchScreen> createState() =>
      _ExportWorkbenchScreenState();
}

class _ExportWorkbenchScreenState extends ConsumerState<ExportWorkbenchScreen> {
  ExportTemplateType _selectedTemplate = ExportTemplateType.mistakeReport;
  final Set<ExportFormat> _selectedFormats = <ExportFormat>{
    ExportFormat.html,
  };
  ExportOptions? _exportOptions;
  PdfLayoutOptions _layoutOptions = const PdfLayoutOptions();
  bool _isExporting = false;
  double _exportProgress = 0;
  bool _initialOptionsApplied = false;

  @override
  Widget build(BuildContext context) {
    final questionsAsync = ref.watch(questionListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('导出与分享'),
        automaticallyImplyLeading: widget.showBackButton,
        leading: widget.showBackButton
            ? IconButton(
                icon: const Icon(CupertinoIcons.chevron_left),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
      ),
      body: questionsAsync.when(
        data: (questions) {
          _ensureInitialOptions(questions);
          return _buildBody(context, questions);
        },
        loading: () => const AppListSkeleton(),
        error: (e, _) => AppErrorState(
          error: e,
          onRetry: () => ref.invalidate(questionListProvider),
        ),
      ),
      bottomNavigationBar: _buildExportBar(context),
    );
  }

  /// 第一次拿到题库时，若入口传入了 [ExportWorkbenchScreen.initialQuestionIds]
  /// 则同步构造一份预填的 [ExportOptions]，跳过手动筛选。
  void _ensureInitialOptions(List<QuestionRecord> questions) {
    if (_initialOptionsApplied) return;
    _initialOptionsApplied = true;
    if (widget.initialQuestionIds.isEmpty) return;
    final idSet = widget.initialQuestionIds.toSet();
    final filtered =
        questions.where((q) => idSet.contains(q.id)).toList(growable: false);
    if (filtered.isEmpty) return;
    _exportOptions = ExportOptions(
      mode: WorksheetExportMode.answer,
      filtered: filtered,
      templateType: _selectedTemplate,
      contentOptions: const ExportContentOptions(),
    );
  }

  Widget _buildBody(BuildContext context, List<QuestionRecord> questions) {
    final showLayoutOptions = _selectedFormats.contains(ExportFormat.pdf);
    final showPreview = _selectedFormats.contains(ExportFormat.html);
    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(child: _buildTemplateSection(context)),
        SliverToBoxAdapter(child: _buildFormatSection(context)),
        SliverToBoxAdapter(child: _buildFilterSection(context, questions)),
        if (showLayoutOptions)
          SliverToBoxAdapter(child: _buildLayoutSection(context)),
        SliverToBoxAdapter(child: _buildHistorySection(context)),
        SliverToBoxAdapter(child: _buildPreviewSection(context, showPreview)),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _buildHistorySection(BuildContext context) {
    final formats = <String>{'全部'}..addAll(_historyFormats);
    return _Section(
      title: '导出历史',
      description: '最近导出的资料可从这里查看、分享或删除',
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                children: formats.map((format) => ChoiceChip(
                  label: Text(format),
                  selected: _historyFormatFilter == format,
                  onSelected: (_) => setState(() => _historyFormatFilter = format),
                )).toList(growable: false),
              ),
            ),
          ),
          FutureBuilder<List<_ExportHistoryItem>>(
            future: _loadExportHistoryItems(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                );
              }
              final allItems = snapshot.data ?? const <_ExportHistoryItem>[];
              final items = _historyFormatFilter == '全部'
                  ? allItems
                  : allItems.where((item) => item.entry.format == _historyFormatFilter).toList();
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: _SummaryBox(
                    icon: CupertinoIcons.clock,
                    text: '暂无符合条件的导出记录。完成一次导出后，记录会显示在这里。',
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: items.take(10).map((item) => _ExportHistoryListTile(
                    item: item,
                    onDelete: () => _deleteExportHistoryItem(context, item),
                    onPreview: () => _previewExportFile(context, item.file!),
                    onShare: () => _shareExportHistoryItem(context, item),
                  )).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Set<String> get _historyFormats => <String>{
        'HTML', 'PDF', 'Markdown', 'CSV', 'JSON', 'TXT', 'Anki',
      };

  String _historyFormatFilter = '全部';

  Future<List<_ExportHistoryItem>> _loadExportHistoryItems() async {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/exports');
    final entries = await ExportHistoryService.list();
    return entries.map((entry) {
      final file = entry.fileName == null
          ? null
          : File('${exportDir.path}/${entry.fileName}');
      return _ExportHistoryItem(entry: entry, file: file);
    }).toList(growable: false);
  }

  Future<void> _deleteExportHistoryItem(
    BuildContext context,
    _ExportHistoryItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除导出记录？'),
        content: Text('将删除「${item.displayName}」及其历史记录。'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton.tonal(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (item.file != null && await item.file!.exists()) await item.file!.delete();
      await ExportHistoryService.remove(item.entry);
      if (mounted) setState(() {});
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除导出记录')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败：$e')));
    }
  }

  Future<void> _previewExportFile(BuildContext context, File file) async {
    if (!await file.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件不可用，请重新导出')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ExportFilePreviewScreen(file: file),
      ),
    );
  }

  Future<void> _shareExportHistoryItem(
    BuildContext context,
    _ExportHistoryItem item,
  ) async {
    if (item.file == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('该历史记录缺少文件信息，请重新导出')));
      return;
    }
    await AppShareService.shareFile(context, item.file!.path);
  }

  Widget _buildTemplateSection(BuildContext context) {
    return _Section(
      title: '选择模板',
      description: '不同模板预设了内容字段，可在下方继续微调',
      child: SizedBox(
        height: 158,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: ExportTemplateType.values.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final template = ExportTemplateType.values[index];
            return _TemplateCard(
              template: template,
              selected: _selectedTemplate == template,
              onTap: () => setState(() => _selectedTemplate = template),
            );
          },
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 格式选择区
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildFormatSection(BuildContext context) {
    // Phase 11-3：按用途分组：文档类（可读报告）vs 数据类（结构化交换）
    const documentFormats = <ExportFormat>[
      ExportFormat.html,
      ExportFormat.pdf,
      ExportFormat.markdown,
    ];
    const dataFormats = <ExportFormat>[
      ExportFormat.anki,
      ExportFormat.csv,
      ExportFormat.json,
    ];
    return _Section(
      title: '导出格式',
      description: '可多选；HTML 与 PDF 互斥，选其中一个会自动取消另一个',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 文档类
            _FormatGroupLabel(
              label: '文档类',
              hint: '适合阅读、打印、分享',
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final format in documentFormats)
                  FilterChip(
                    label: Text(_formatLabel(format)),
                    avatar: Icon(_formatIcon(format), size: 16),
                    selected: _selectedFormats.contains(format),
                    onSelected: (_) => _toggleFormat(format),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // 数据类
            _FormatGroupLabel(
              label: '数据类',
              hint: '适合导入其它应用或备份',
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final format in dataFormats)
                  FilterChip(
                    label: Text(_formatLabel(format)),
                    avatar: Icon(_formatIcon(format), size: 16),
                    selected: _selectedFormats.contains(format),
                    onSelected: (_) => _toggleFormat(format),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _toggleFormat(ExportFormat format) {
    setState(() {
      if (_selectedFormats.contains(format)) {
        _selectedFormats.remove(format);
      } else {
        _selectedFormats.add(format);
        // HTML 与 PDF 互斥：选 HTML 自动取消 PDF，反之亦然。
        if (format == ExportFormat.html) {
          _selectedFormats.remove(ExportFormat.pdf);
        } else if (format == ExportFormat.pdf) {
          _selectedFormats.remove(ExportFormat.html);
        }
      }
    });
  }

  String _formatLabel(ExportFormat format) => switch (format) {
        ExportFormat.html => 'HTML',
        ExportFormat.pdf => 'PDF',
        ExportFormat.markdown => 'Markdown',
        ExportFormat.anki => 'Anki',
        ExportFormat.csv => 'CSV',
        ExportFormat.json => 'JSON',
      };

  IconData _formatIcon(ExportFormat format) => switch (format) {
        ExportFormat.html => CupertinoIcons.doc_text,
        ExportFormat.pdf => CupertinoIcons.doc_richtext,
        ExportFormat.markdown => CupertinoIcons.text_badge_plus,
        ExportFormat.anki => CupertinoIcons.rectangle_stack,
        ExportFormat.csv => CupertinoIcons.table,
        ExportFormat.json => CupertinoIcons.square_stack_3d_up,
      };

  // ─────────────────────────────────────────────────────────────────────
  // 筛选与内容选项区
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildFilterSection(
    BuildContext context,
    List<QuestionRecord> questions,
  ) {
    final options = _exportOptions;
    return _Section(
      title: '筛选与内容选项',
      description: '点击下方按钮配置学科、掌握度、时间范围与导出字段',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('快速预设', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                _presetChip('快速复习', () => _applyExportPreset(
                      questions,
                      ExportContentOptions(),
                    )),
                _presetChip('完整档案', () => _applyExportPreset(
                      questions,
                      ExportContentOptions.all,
                    )),
                _presetChip('打印练习', () => _applyExportPreset(
                      questions,
                      ExportContentOptions.none.copyWith(
                        includeImage: true,
                        includeDates: true,
                      ),
                    )),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: questions.isEmpty
                  ? null
                  : () => _openOptionsDialog(context, questions),
              icon: const Icon(CupertinoIcons.slider_horizontal_3),
              label: const Text('筛选与内容选项'),
            ),
            const SizedBox(height: 12),
            if (options == null)
              _SummaryBox(
                icon: CupertinoIcons.info,
                text: '尚未配置：将默认导出全部题目（${questions.length} 题）'
                    '${questions.isEmpty ? '，题库为空时无法导出' : ''}',
              )
            else ...<Widget>[
              _SummaryBox(
                icon: CupertinoIcons.line_horizontal_3_decrease,
                title: '当前筛选',
                text: _buildFilterSummary(options, questions.length),
              ),
              const SizedBox(height: 8),
              _SummaryBox(
                icon: CupertinoIcons.list_bullet,
                title: '内容选项',
                text: _buildContentSummary(options.contentOptions),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _presetChip(String label, VoidCallback onPressed) {
    return ActionChip(
      label: Text(label),
      avatar: const Icon(CupertinoIcons.sparkles, size: 14),
      onPressed: onPressed,
    );
  }

  void _applyExportPreset(
    List<QuestionRecord> questions,
    ExportContentOptions contentOptions,
  ) {
    setState(() {
      _exportOptions = ExportOptions(
        mode: WorksheetExportMode.answer,
        filtered: questions,
        templateType: _selectedTemplate,
        contentOptions: contentOptions,
      );
    });
  }

  Future<void> _openOptionsDialog(
    BuildContext context,
    List<QuestionRecord> questions,
  ) async {
    final result = await showExportOptionsDialog(context, questions);
    if (result == null || !mounted) return;
    setState(() => _exportOptions = result);
  }

  String _buildFilterSummary(ExportOptions options, int totalCount) {
    final parts = <String>[];
    parts.add(options.mode.label);
    parts.add('${options.filtered.length} / $totalCount 题');
    if (options.onlyFavorite) parts.add('仅收藏');
    if (options.selectedKnowledgePoints.isNotEmpty) {
      parts.add('${options.selectedKnowledgePoints.length} 个知识点');
    }
    if (options.selectedMistakeCategories.isNotEmpty) {
      parts.add('${options.selectedMistakeCategories.length} 类错因');
    }
    if (options.selectedDifficulties.isNotEmpty) {
      parts.add('${options.selectedDifficulties.length} 种难度');
    }
    if (options.selectedLearningStages.isNotEmpty) {
      parts.add('${options.selectedLearningStages.length} 个学习阶段');
    }
    if (options.selectedSources.isNotEmpty) {
      parts.add('${options.selectedSources.length} 个来源');
    }
    if (options.dateRange != null) {
      parts.add(
          '${_formatDate(options.dateRange!.start)}~${_formatDate(options.dateRange!.end)}');
    }
    return parts.join(' · ');
  }

  String _buildContentSummary(ExportContentOptions o) {
    final parts = <String>[];
    if (o.includeImage) parts.add('含题图');
    if (o.includeCorrectAnswer) parts.add('含答案');
    if (o.includeSolutionSteps) parts.add('含解析');
    if (o.includeKnowledgePoints) parts.add('含知识点');
    if (o.includeMistakeReason) parts.add('含错因');
    if (o.includeStudyAdvice) parts.add('含学习建议');
    if (o.includeReviewCount) parts.add('含复习次数');
    if (o.includeFavoriteMark) parts.add('含收藏标记');
    if (o.includeDates) parts.add('含日期');
    if (o.includeExercises) parts.add('含 AI 练习题');
    // Phase 11-4：扩展字段摘要。
    if (o.includeOcrText) parts.add('含OCR原文');
    if (o.includeAiAnalysis) parts.add('含完整AI分析');
    if (o.includeReviewHistory) parts.add('含复习历史');
    if (o.includeKnowledgeTree) parts.add('含知识点树路径');
    if (parts.isEmpty) parts.add('无内容字段');
    return parts.join(' / ');
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ─────────────────────────────────────────────────────────────────────
  // 排版选项区（仅 PDF）
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildLayoutSection(BuildContext context) {
    final o = _layoutOptions;
    return _Section(
      title: 'PDF 排版选项',
      description: '仅作用于 PDF 导出；其它格式忽略此处的设置',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildDropdownRow<PdfPageSize>(
              label: '纸张大小',
              value: o.pageSize,
              values: PdfPageSize.values,
              onChanged: (v) => setState(
                  () => _layoutOptions = _layoutOptions.copyWith(pageSize: v)),
            ),
            _buildDropdownRow<PdfOrientation>(
              label: '方向',
              value: o.orientation,
              values: PdfOrientation.values,
              onChanged: (v) => setState(() =>
                  _layoutOptions = _layoutOptions.copyWith(orientation: v)),
            ),
            _buildDropdownRow<PdfMargin>(
              label: '边距',
              value: o.margin,
              values: PdfMargin.values,
              onChanged: (v) => setState(
                  () => _layoutOptions = _layoutOptions.copyWith(margin: v)),
            ),
            _buildDropdownRow<PdfFontSize>(
              label: '字号',
              value: o.fontSize,
              values: PdfFontSize.values,
              onChanged: (v) => setState(() =>
                  _layoutOptions = _layoutOptions.copyWith(fontSize: v)),
            ),
            const Divider(height: 24),
            _buildSwitchRow(
              label: '含封面',
              value: o.includeCover,
              onChanged: (v) => setState(() =>
                  _layoutOptions = _layoutOptions.copyWith(includeCover: v)),
            ),
            _buildSwitchRow(
              label: '含目录',
              value: o.includeToc,
              onChanged: (v) => setState(
                  () => _layoutOptions = _layoutOptions.copyWith(includeToc: v)),
            ),
            _buildSwitchRow(
              label: '含页眉',
              value: o.includeHeader,
              onChanged: (v) => setState(() =>
                  _layoutOptions = _layoutOptions.copyWith(includeHeader: v)),
            ),
            _buildSwitchRow(
              label: '含页脚（含页码）',
              value: o.includeFooter,
              onChanged: (v) => setState(() =>
                  _layoutOptions = _layoutOptions.copyWith(includeFooter: v)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownRow<T>({
    required String label,
    required T value,
    required List<T> values,
    required ValueChanged<T> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              items: <DropdownMenuItem<T>>[
                for (final v in values)
                  DropdownMenuItem<T>(
                    value: v,
                    child: Text(_enumLabel(v)),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  String _enumLabel<T>(T value) {
    if (value is PdfPageSize) return value.label;
    if (value is PdfOrientation) return value.label;
    if (value is PdfMargin) return value.label;
    if (value is PdfFontSize) return value.label;
    return value.toString();
  }

  Widget _buildSwitchRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      value: value,
      onChanged: onChanged,
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 预览区
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildPreviewSection(BuildContext context, bool showPreview) {
    final pdfSelected = _selectedFormats.contains(ExportFormat.pdf);
    return _Section(
      title: '预览与检查',
      description: showPreview ? 'HTML 可直接预览；PDF 可生成后预览或分享' : '选择 HTML 或 PDF 后使用预览',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          FilledButton.tonalIcon(
            onPressed: showPreview && _exportOptions != null ? () => _previewHtml(context) : null,
            icon: const Icon(CupertinoIcons.eye),
            label: const Text('预览 HTML'),
          ),
          OutlinedButton.icon(
            onPressed: pdfSelected && _exportOptions != null ? () => _previewPdf(context) : null,
            icon: const Icon(CupertinoIcons.doc_richtext),
            label: const Text('预览 PDF'),
          ),
        ]),
      ),
    );
  }

  Future<void> _previewPdf(BuildContext context) async {
    final options = _exportOptions;
    if (options == null) return;
    try {
      final file = await PdfExportService.generatePdf(
        options.filtered,
        title: '错题本整理报告',
        mode: options.mode,
        studentInfo: options.studentInfo,
        watermark: options.studentInfo?.watermark,
        layoutOptions: _layoutOptions,
        contentOptions: options.contentOptions,
      );
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('PDF 预览')),
            body: PdfPreview(
              build: (_) => file.readAsBytes(),
              canChangePageFormat: false,
              canChangeOrientation: false,
              allowPrinting: true,
              allowSharing: true,
            ),
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF 预览失败：$e')));
      }
    }
  }

  Future<void> _previewHtml(BuildContext context) async {
    final options = _exportOptions;
    if (options == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HtmlPreviewScreen(
          questions: options.filtered,
          mode: options.mode,
          studentInfo: options.studentInfo,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 导出按钮区（底部 sticky）
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildExportBar(BuildContext context) {
    final canExport =
        _selectedFormats.isNotEmpty && !_isExporting && _exportOptions != null;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 1,
            ),
          ),
        ),
        child: FilledButton.icon(
          onPressed: canExport ? () => _startExport(context) : null,
          icon: _isExporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(CupertinoIcons.arrow_up_doc),
          label: Text(_isExporting
              ? '正在导出 ${(_exportProgress * 100).round()}%'
              : '导出（${_selectedFormats.length} 种格式）'),
        ),
      ),
    );
  }

  Future<void> _startExport(BuildContext context) async {
    final options = _exportOptions;
    if (options == null) return;
    if (_selectedFormats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一种导出格式')),
      );
      return;
    }
    final questions = options.filtered;
    final missingAnalysis = questions.where((q) => q.analysisResult == null).length;
    if (missingAnalysis > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$missingAnalysis 道题还没有 AI 分析，将按当前已有内容导出'),
          duration: const Duration(seconds: 4),
        ),
      );
    }

    setState(() {
      _isExporting = true;
      _exportProgress = 0;
    });

    final messenger = ScaffoldMessenger.of(context);
    final formats = _selectedFormats.toList();
    final succeeded = <ExportFormat>[];
    final failed = <MapEntry<ExportFormat, Object>>[];
    final exportedPaths = <String, String>{};

    try {
      for (var i = 0; i < formats.length; i++) {
        final format = formats[i];
        if (mounted) {
          setState(() {
            _exportProgress = (i + 1) / formats.length;
          });
        }
        try {
          final filePath = await _exportFormat(format, options);
          exportedPaths[_formatLabel(format)] = filePath;
          succeeded.add(format);
          await ExportHistoryService.add(ExportHistoryEntry(
            timestamp: DateTime.now().millisecondsSinceEpoch,
            format: _formatLabel(format),
            template: options.templateType.label,
            questionCount: questions.length,
            title: '错题本整理报告',
            fileName: File(filePath).uri.pathSegments.last,
          ));
          invalidateExportHistory(ref);
        } catch (e) {
          failed.add(MapEntry(format, e));
        }
      }

      if (!mounted) return;
      if (failed.isEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('已导出 ${succeeded.length} 种格式，并保存到导出历史'),
          ),
        );
      } else if (succeeded.isNotEmpty) {
        final failedLabels = failed.map((e) => _formatLabel(e.key)).join('、');
        messenger.showSnackBar(
          SnackBar(
            content: Text('部分导出成功，失败：$failedLabels。成功文件已保存到导出历史'),
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        final failedLabels =
            failed.map((e) => '${_formatLabel(e.key)}: ${e.value}').join('\n');
        messenger.showSnackBar(
          SnackBar(
            content: Text('导出失败：\n$failedLabels'),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
    if (mounted && succeeded.isNotEmpty) {
      final failedLabels = failed.map((e) => _formatLabel(e.key)).toList();
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => _ExportCompletePage(
            formats: succeeded.map(_formatLabel).toList(growable: false),
            filePaths: exportedPaths,
            questionCount: questions.length,
            completedAt: DateTime.now(),
            failedFormats: failedLabels,
          ),
        ),
      );
    }
  }

  Future<String> _exportFormat(
    ExportFormat format,
    ExportOptions options,
  ) async {
    final questions = options.filtered;
    final mode = options.mode;
    final studentInfo = options.studentInfo;
    final watermark = studentInfo?.watermark;
    final contentOptions = options.contentOptions;

    // Phase 11-4：按需预查扩展数据，避免在不需要时付出查询代价。
    // - reviewLogs：当 includeReviewHistory 打开时，从仓库取全量复习日志。
    // - knowledgeTreePaths：当 includeKnowledgeTree 打开时，逐题查询关联
    //   知识点并拼接面包屑路径。两项数据预查一次后供下游 6 个服务复用。
    final List<ReviewLog> reviewLogs;
    final Map<String, List<String>> knowledgeTreePaths;
    if (contentOptions.includeReviewHistory ||
        contentOptions.includeKnowledgeTree) {
      final reviewLogRepo = ref.read(reviewLogRepositoryProvider);
      final linkRepo = ref.read(questionKnowledgeLinkRepositoryProvider);
      final kpRepo = ref.read(knowledgePointRepositoryProvider);
      if (contentOptions.includeReviewHistory) {
        reviewLogs = await reviewLogRepo.listAll();
      } else {
        reviewLogs = const <ReviewLog>[];
      }
      if (contentOptions.includeKnowledgeTree) {
        knowledgeTreePaths =
            await _buildKnowledgeTreePaths(questions, linkRepo, kpRepo);
      } else {
        knowledgeTreePaths = const <String, List<String>>{};
      }
    } else {
      reviewLogs = const <ReviewLog>[];
      knowledgeTreePaths = const <String, List<String>>{};
    }

    // 工作台已在外层显示进度对话框，这里直接调用底层生成接口，
    // 不再走 shareHtml / sharePdf —— 它们各自会再弹一个进度对话框，
    // 与工作台外层对话框叠加，且 Share.shareXFiles await 期间内层对话框
    // 不会关闭，在某些平台会导致整个流程卡死。
    switch (format) {
      case ExportFormat.html:
        final result = await HtmlExportService.generateHtml(
          questions,
          mode: mode,
          studentInfo: studentInfo,
          contentOptions: contentOptions,
          watermark: watermark,
          layoutOptions: options.layoutOptions,
          templateType: options.templateType,
          reviewLogs: reviewLogs,

        );
        return result.filePath;
      case ExportFormat.pdf:
        final file = await PdfExportService.generatePdf(
          questions,
          mode: mode,
          studentInfo: studentInfo,
          watermark: watermark,
          layoutOptions: options.layoutOptions,
          contentOptions: contentOptions,
        );
        return file.path;
      case ExportFormat.markdown:
        final content = await MarkdownExportService().generateMarkdown(
          questions: questions,
          mode: mode,
          contentOptions: contentOptions,
          studentName: studentInfo?.name,
          className: studentInfo?.className,
          reviewLogs: reviewLogs,
          knowledgeTreePaths: knowledgeTreePaths,
        );
        return _saveTextExport(
          content,
          _buildFileName('md', options: options),
        );
      case ExportFormat.anki:
        final content = await AnkiExportService().generateAnkiImportText(
          questions: questions,
          contentOptions: contentOptions,
          knowledgeTreePaths: knowledgeTreePaths,
        );
        return _saveTextExport(
          content,
          _buildFileName('txt', options: options),
        );
      case ExportFormat.csv:
        final content = await CsvExportService().generateCsv(
          questions: questions,
          contentOptions: contentOptions,
        );
        return _saveTextExport(
          '\uFEFF$content',
          _buildFileName('csv', options: options),
        );
      case ExportFormat.json:
        final content = await JsonExportService().generateJson(
          questions: questions,
          contentOptions: contentOptions,
          reviewLogs: reviewLogs,
          knowledgeTreePaths: knowledgeTreePaths,
        );
        return _saveTextExport(
          content,
          _buildFileName('json', options: options),
        );
    }
  }

  Future<String> _saveTextExport(String content, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/exports');
    await exportDir.create(recursive: true);
    final file = await ExportFileWriter.uniqueTarget(exportDir, fileName);
    await ExportFileWriter.writeTextAtomic(file, content);
    return file.path;
  }

  /// Phase 11-4：为每道题目拼接知识点树面包屑路径。
  ///
  /// 流程：`linksForQuestion(q.id)` 拿到该题关联的全部 KnowledgePoint ID
  /// → 对每个 ID 调 `ancestorPath(id)` 拿到"自身→根"列表 → 反转为
  /// "根→叶"顺序 → 用 ` > ` 拼接节点名。
  ///
  /// 返回 `Map<questionId, List<path>>`，path 形如
  /// `数学 > 代数 > 二次方程`。一题可关联多个知识点，故 value 是 List。
  Future<Map<String, List<String>>> _buildKnowledgeTreePaths(
    List<QuestionRecord> questions,
    QuestionKnowledgeLinkRepository linkRepo,
    KnowledgePointRepository kpRepo,
  ) async {
    final result = <String, List<String>>{};
    for (final q in questions) {
      final links = await linkRepo.linksForQuestion(q.id);
      if (links.isEmpty) continue;
      final paths = <String>[];
      for (final link in links) {
        final ancestors = await kpRepo.ancestorPath(link.knowledgePointId);
        if (ancestors.isEmpty) continue;
        // ancestorPath 返回"自身→根"顺序，反转得到"根→叶"。
        final breadcrumb = ancestors
            .reversed
            .map((kp) => kp.name)
            .where((name) => name.isNotEmpty)
            .join(' > ');
        if (breadcrumb.isNotEmpty) paths.add(breadcrumb);
      }
      if (paths.isNotEmpty) {
        result[q.id] = paths;
      }
    }
    return result;
  }


  String _buildFileName(String extension, {required ExportOptions options}) {
    final templatePart = _sanitizeFileNamePart(options.templateType.label);
    final subjectPart = _sanitizeFileNamePart(_subjectScopeLabel(options.filtered));
    final now = DateTime.now();
    final datePart =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}_${now.millisecond.toString().padLeft(3, '0')}';
    return '${templatePart}_${subjectPart}_$datePart.$extension';
  }

  /// 学科范围标签：单学科返回学科名，多学科返回"多学科"，空题库返回"空"。
  /// 复用 HtmlExportService 同名逻辑，但本页不依赖服务层私有方法。
  static String _subjectScopeLabel(List<QuestionRecord> questions) {
    if (questions.isEmpty) return '空';
    final subjects = <String>{};
    for (final q in questions) {
      subjects.add(q.subject.label);
    }
    if (subjects.length == 1) return subjects.first;
    return '多学科';
  }

  /// 替换文件名中的非法字符为下划线（与 HtmlExportService 保持一致）。
  static String _sanitizeFileNamePart(String part) {
    return part.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 私有 UI 组件
// ─────────────────────────────────────────────────────────────────────────

class _ExportCompletePage extends StatelessWidget {
  const _ExportCompletePage({
    required this.formats,
    required this.filePaths,
    required this.questionCount,
    required this.completedAt,
    required this.failedFormats,
  });

  final List<String> formats;
  final Map<String, String> filePaths;
  final int questionCount;
  final DateTime completedAt;
  final List<String> failedFormats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = '${completedAt.hour.toString().padLeft(2, '0')}:${completedAt.minute.toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(title: const Text('导出完成')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.xl),
          children: <Widget>[
            Icon(CupertinoIcons.checkmark_seal_fill,
                size: 56, color: scheme.primary),
            const SizedBox(height: AppSpace.md),
            const Text(
              '文件已保存',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              '导出时间 $time · 共 $questionCount 题',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpace.xl),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('已生成格式',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.xs,
                    runSpacing: AppSpace.xs,
                    children: formats
                        .map((format) => Chip(label: Text(format)))
                        .toList(growable: false),
                  ),
                  if (failedFormats.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpace.md),
                    Text(
                      '失败格式：${failedFormats.join('、')}',
                      style: TextStyle(color: scheme.error),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
            const Text('本次导出文件',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpace.xs),
            for (final entry in filePaths.entries)
              Card(
                margin: const EdgeInsets.only(bottom: AppSpace.xs),
                child: ListTile(
                  dense: true,
                  leading: const Icon(CupertinoIcons.doc_text),
                  title: Text(entry.key),
                  subtitle: Text(
                    File(entry.value).uri.pathSegments.last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: <Widget>[
                      FilledButton.tonalIcon(
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => ExportFilePreviewScreen(
                              file: File(entry.value),
                            ),
                          ),
                        ),
                        icon: const Icon(CupertinoIcons.eye, size: 16),
                        label: const Text('预览'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => AppShareService.shareFile(
                          context,
                          entry.value,
                        ),
                        icon: const Icon(CupertinoIcons.share, size: 16),
                        label: const Text('分享'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppSpace.md),
            Text(
              '文件已经进入导出历史。返回后可在对应记录中分享或删除。',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpace.xl),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回导出工作台'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(description,
                style: TextStyle(
                    fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _FormatGroupLabel extends StatelessWidget {
  const _FormatGroupLabel({required this.label, required this.hint});

  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Container(
          width: 3,
          height: 12,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: theme.textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        Text(hint,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            )),
      ],
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final ExportTemplateType template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderColor =
        selected ? colorScheme.primary : colorScheme.outlineVariant;
    return Material(
      color: selected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 168,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: selected ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(template.icon,
                      size: 22,
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant),
                  const Spacer(),
                  if (selected)
                    Icon(CupertinoIcons.checkmark_circle_fill,
                        size: 18, color: colorScheme.primary),
                ],
              ),
              const SizedBox(height: 10),
              Text(template.label,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                template.description,
                style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.3),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              // Phase 11-2：适用场景标签
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer
                      .withValues(alpha: selected ? 0.7 : 0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '适用：${template.useCase}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSecondaryContainer,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  const _SummaryBox({
    required this.icon,
    required this.text,
    this.title,
  });

  final IconData icon;
  final String text;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (title != null) ...<Widget>[
                  Text(title!,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                ],
                Text(text,
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}



class _ExportHistoryItem {
  const _ExportHistoryItem({required this.entry, required this.file});

  final ExportHistoryEntry entry;
  final File? file;

  String get displayName => entry.fileName ?? '${entry.format} · ${entry.title}';
}

class _ExportHistoryListTile extends StatelessWidget {
  const _ExportHistoryListTile({
    required this.item,
    required this.onDelete,
    required this.onPreview,
    required this.onShare,
  });

  final _ExportHistoryItem item;
  final VoidCallback onDelete;
  final VoidCallback onPreview;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final entry = item.entry;
    final file = item.file;
    final name = item.displayName;
    final extension = entry.format.isNotEmpty
        ? entry.format
        : _extension(name);
    final colorScheme = Theme.of(context).colorScheme;
    final fileInfo = _fileInfo(item);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(_formatIcon(extension), color: colorScheme.primary),
      title: Row(
        children: <Widget>[
          _FormatBadge(label: extension.toUpperCase()),
          const SizedBox(width: 8),
          Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
      subtitle: Text(fileInfo),
      trailing: Wrap(
        spacing: 0,
        children: <Widget>[
          IconButton(
            onPressed: file == null ? null : onPreview,
            icon: const Icon(CupertinoIcons.eye),
            tooltip: '预览',
          ),
          IconButton(
            onPressed: file == null ? null : onShare,
            icon: const Icon(CupertinoIcons.share),
            tooltip: '分享',
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(CupertinoIcons.delete, color: AppColors.danger),
            tooltip: '删除',
          ),
        ],
      ),
    );
  }

  static String _fileInfo(_ExportHistoryItem item) {
    final timestamp = _formatDateTime(
      DateTime.fromMillisecondsSinceEpoch(item.entry.timestamp),
    );
    final file = item.file;
    if (file == null) return '文件不可用 · $timestamp';
    try {
      return '$timestamp · ${_formatBytes(file.lengthSync())}';
    } catch (_) {
      return '文件不可用 · $timestamp';
    }
  }

  static String _extension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'FILE';
    return name.substring(dot + 1);
  }

  static IconData _formatIcon(String extension) => switch (extension.toLowerCase()) {
        'pdf' => CupertinoIcons.doc_richtext,
        'csv' => CupertinoIcons.table,
        'json' => CupertinoIcons.square_stack_3d_up,
        'md' || 'markdown' => CupertinoIcons.text_badge_plus,
        'txt' || 'anki' => CupertinoIcons.rectangle_stack,
        _ => CupertinoIcons.doc_text,
      };

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _FormatBadge extends StatelessWidget {
  const _FormatBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

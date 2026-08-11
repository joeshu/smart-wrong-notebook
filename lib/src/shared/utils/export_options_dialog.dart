import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_content_options.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_template.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_preview_screen.dart';
import 'package:smart_wrong_notebook/src/shared/utils/worksheet_export_mode.dart';

/// 导出选项：模板 + 模式 + 筛选条件 + 内容选项 + 排版选项 + 筛选后的题目 + 学生信息。
class ExportOptions {
  const ExportOptions({
    required this.mode,
    required this.filtered,
    this.templateType = ExportTemplateType.mistakeReport,
    this.studentInfo,
    this.selectedKnowledgePoints = const <String>{},
    this.onlyFavorite = false,
    this.selectedMistakeCategories = const <MistakeCategory>{},
    this.selectedDifficulties = const <String>{},
    this.selectedLearningStages = const <String>{},
    this.selectedSources = const <String>{},
    this.dateRange,
    this.contentOptions = const ExportContentOptions(),
    this.layoutOptions,
  });

  final WorksheetExportMode mode;
  final List<QuestionRecord> filtered;
  final ExportStudentInfo? studentInfo;

  /// 导出模板类型，默认 [ExportTemplateType.mistakeReport] 保持向后兼容。
  final ExportTemplateType templateType;

  /// 选中的知识点（来自 aiTags / aiKnowledgePoints），空集合表示不过滤。
  final Set<String> selectedKnowledgePoints;

  /// 是否仅导出收藏题目。
  final bool onlyFavorite;

  /// 选中的错因类别，空集合表示不过滤。
  final Set<MistakeCategory> selectedMistakeCategories;

  /// 选中的难度（QuestionDifficulty.name），空集合表示不过滤。
  final Set<String> selectedDifficulties;

  /// 选中的学习阶段，空集合表示不过滤。
  final Set<String> selectedLearningStages;

  /// 选中的来源，空集合表示不过滤。
  final Set<String> selectedSources;

  /// 自定义时间区间，仅当用户在时间范围里选了「自定义日期」时非空。
  final DateTimeRange? dateRange;

  /// 导出内容字段开关。
  final ExportContentOptions contentOptions;

  /// PDF 排版选项：纸张 / 方向 / 边距 / 字号 / 内容区块开关。
  /// 为 null 表示使用默认值（A4 纵向 / 标准字号 / 正常边距）。
  final PdfLayoutOptions? layoutOptions;
}

enum _TimeRange { all, days7, days30, days90, custom }

const Map<_TimeRange, String> _timeRangeLabels = {
  _TimeRange.all: '全部时间',
  _TimeRange.days7: '近 7 天',
  _TimeRange.days30: '近 30 天',
  _TimeRange.days90: '近 90 天',
  _TimeRange.custom: '自定义日期',
};

const String _prefMode = 'export_options.mode';
const String _prefSubjects = 'export_options.subjects';
const String _prefLevels = 'export_options.levels';
const String _prefKnowledgePoints = 'export_options.knowledge_points';
const String _prefOnlyFavorite = 'export_options.only_favorite';
const String _prefMistakeCategories = 'export_options.mistake_categories';
const String _prefDifficulties = 'export_options.difficulties';
const String _prefLearningStages = 'export_options.learning_stages';
const String _prefSources = 'export_options.sources';
const String _prefTimeRange = 'export_options.time_range';
const String _prefDateRangeStart = 'export_options.date_range_start';
const String _prefDateRangeEnd = 'export_options.date_range_end';
const String _prefContentOptions = 'export_options.content_options';
const String _prefTemplateType = 'export_options.template_type';
const String _prefLayoutOptions = 'export_options.layout_options';

/// 弹出导出选项对话框：选择模式、筛选题目、填写学生信息。
///
/// - [allowFilter] 为 false 时隐藏筛选区（例如组卷工作台已手动选题）。
/// - [allowPreview] 为 true 时显示「预览」按钮（桌面端无 WebView，强制关闭）。
/// - [initialMode] 为非 null 时，用作模式选择的初始值（覆盖持久化值），
///   供组卷工作台等已有模式快切入口的页面传入，避免与持久化值冲突。
/// 返回 null 表示用户取消或已通过预览页完成导出。
Future<ExportOptions?> showExportOptionsDialog(
  BuildContext context,
  List<QuestionRecord> questions, {
  bool allowFilter = true,
  bool allowPreview = true,
  WorksheetExportMode? initialMode,
}) {
  return showDialog<ExportOptions?>(
    context: context,
    builder: (_) => _ExportOptionsDialog(
      questions: questions,
      allowFilter: allowFilter,
      allowPreview: allowPreview && !HtmlExportService.isDesktopPlatform,
      initialMode: initialMode,
    ),
  );
}

class _ExportOptionsDialog extends StatefulWidget {
  const _ExportOptionsDialog({
    required this.questions,
    required this.allowFilter,
    required this.allowPreview,
    this.initialMode,
  });

  final List<QuestionRecord> questions;
  final bool allowFilter;
  final bool allowPreview;
  final WorksheetExportMode? initialMode;

  @override
  State<_ExportOptionsDialog> createState() => _ExportOptionsDialogState();
}

class _ExportOptionsDialogState extends State<_ExportOptionsDialog> {
  WorksheetExportMode _mode = WorksheetExportMode.answer;
  ExportTemplateType _templateType = ExportTemplateType.mistakeReport;
  final Set<Subject> _subjects = {};
  final Set<MasteryLevel> _levels = {};
  final Set<String> _knowledgePoints = {};
  bool _onlyFavorite = false;
  final Set<MistakeCategory> _mistakeCategories = {};
  final Set<String> _difficulties = {};
  final Set<String> _learningStages = {};
  final Set<String> _sources = {};
  _TimeRange _timeRange = _TimeRange.all;
  DateTimeRange? _customDateRange;
  ExportContentOptions _contentOptions = const ExportContentOptions();
  PdfLayoutOptions _layoutOptions = const PdfLayoutOptions();
  final _nameController = TextEditingController();
  final _classController = TextEditingController();
  final _footerTextController = TextEditingController();

  // 题目数据动态收集的可选值（一次性计算，对话框生命周期内不变）。
  late final Set<String> _availableKnowledgePoints = {
    for (final q in widget.questions) ...[...q.aiTags, ...q.aiKnowledgePoints],
  };
  late final Set<String> _availableLearningStages = {
    for (final q in widget.questions)
      if (q.learningStage != null) q.learningStage!,
  };
  late final Set<String> _availableSources = {
    for (final q in widget.questions) if (q.source != null) q.source!,
  };

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _classController.dispose();
    _footerTextController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        // 工作台等入口传入的 initialMode 优先于持久化值
        if (widget.initialMode != null) {
          _mode = widget.initialMode!;
        } else {
          final modeName = prefs.getString(_prefMode);
          if (modeName != null) {
            for (final m in WorksheetExportMode.values) {
              if (m.name == modeName) {
                _mode = m;
                break;
              }
            }
          }
        }
        final templateName = prefs.getString(_prefTemplateType);
        if (templateName != null) {
          for (final t in ExportTemplateType.values) {
            if (t.name == templateName) {
              _templateType = t;
              break;
            }
          }
        }
        _subjects
          ..clear()
          ..addAll(_readSubjectList(prefs.getStringList(_prefSubjects)));
        _levels
          ..clear()
          ..addAll(_readLevelList(prefs.getStringList(_prefLevels)));
        _knowledgePoints
          ..clear()
          ..addAll(prefs.getStringList(_prefKnowledgePoints) ?? const []);
        _onlyFavorite = prefs.getBool(_prefOnlyFavorite) ?? false;
        _mistakeCategories
          ..clear()
          ..addAll(_readMistakeCategoryList(
              prefs.getStringList(_prefMistakeCategories)));
        _difficulties
          ..clear()
          ..addAll(prefs.getStringList(_prefDifficulties) ?? const []);
        _learningStages
          ..clear()
          ..addAll(prefs.getStringList(_prefLearningStages) ?? const []);
        _sources
          ..clear()
          ..addAll(prefs.getStringList(_prefSources) ?? const []);
        final timeRangeName = prefs.getString(_prefTimeRange);
        if (timeRangeName != null) {
          for (final r in _TimeRange.values) {
            if (r.name == timeRangeName) {
              _timeRange = r;
              break;
            }
          }
        }
        final startMs = prefs.getInt(_prefDateRangeStart);
        final endMs = prefs.getInt(_prefDateRangeEnd);
        if (startMs != null && endMs != null && endMs >= startMs) {
          _customDateRange = DateTimeRange(
            start: DateTime.fromMillisecondsSinceEpoch(startMs),
            end: DateTime.fromMillisecondsSinceEpoch(endMs),
          );
        }
        final contentJson = prefs.getString(_prefContentOptions);
        if (contentJson != null && contentJson.isNotEmpty) {
          _contentOptions = _decodeContentOptions(contentJson);
        }
        final layoutJson = prefs.getString(_prefLayoutOptions);
        if (layoutJson != null && layoutJson.isNotEmpty) {
          _layoutOptions = _decodeLayoutOptions(layoutJson);
          _footerTextController.text = _layoutOptions.footerText ?? '';
        }
      });
    } catch (_) {
      // SharedPreferences 不可用（例如测试环境），沿用默认值。
    }
  }

  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefMode, _mode.name);
      await prefs.setString(_prefTemplateType, _templateType.name);
      await prefs.setStringList(
          _prefSubjects, _subjects.map((s) => s.name).toList());
      await prefs.setStringList(
          _prefLevels, _levels.map((l) => l.name).toList());
      await prefs.setStringList(_prefKnowledgePoints, _knowledgePoints.toList());
      await prefs.setBool(_prefOnlyFavorite, _onlyFavorite);
      await prefs.setStringList(_prefMistakeCategories,
          _mistakeCategories.map((c) => c.name).toList());
      await prefs.setStringList(_prefDifficulties, _difficulties.toList());
      await prefs.setStringList(_prefLearningStages, _learningStages.toList());
      await prefs.setStringList(_prefSources, _sources.toList());
      await prefs.setString(_prefTimeRange, _timeRange.name);
      if (_customDateRange != null) {
        await prefs.setInt(_prefDateRangeStart,
            _customDateRange!.start.millisecondsSinceEpoch);
        await prefs.setInt(_prefDateRangeEnd,
            _customDateRange!.end.millisecondsSinceEpoch);
      } else {
        await prefs.remove(_prefDateRangeStart);
        await prefs.remove(_prefDateRangeEnd);
      }
      await prefs.setString(_prefContentOptions,
          jsonEncode(_encodeContentOptions(_contentOptions)));
      // _layoutOptions.footerText 与输入框同步：用户可能清空输入框。
      final footerText = _footerTextController.text.trim();
      final toSave = footerText.isEmpty
          ? _layoutOptions.copyWith(footerText: null)
          : _layoutOptions.copyWith(footerText: footerText);
      await prefs.setString(
          _prefLayoutOptions, jsonEncode(_encodeLayoutOptions(toSave)));
    } catch (_) {
      // 持久化失败不影响导出流程。
    }
  }

  List<QuestionRecord> get _filtered {
    if (!widget.allowFilter) return widget.questions;
    final now = DateTime.now();
    return widget.questions.where((q) {
      if (_subjects.isNotEmpty && !_subjects.contains(q.subject)) return false;
      if (_levels.isNotEmpty && !_levels.contains(q.masteryLevel)) return false;
      if (_knowledgePoints.isNotEmpty) {
        final qKps = <String>{...q.aiTags, ...q.aiKnowledgePoints};
        if (_knowledgePoints.intersection(qKps).isEmpty) return false;
      }
      if (_onlyFavorite && !q.isFavorite) return false;
      if (_mistakeCategories.isNotEmpty) {
        final cat = q.mistakeCategory;
        if (cat == null || !_mistakeCategories.contains(cat)) return false;
      }
      if (_difficulties.isNotEmpty) {
        final d = q.difficulty;
        if (d == null || !_difficulties.contains(d.name)) return false;
      }
      if (_learningStages.isNotEmpty) {
        final ls = q.learningStage;
        if (ls == null || !_learningStages.contains(ls)) return false;
      }
      if (_sources.isNotEmpty) {
        final src = q.source;
        if (src == null || !_sources.contains(src)) return false;
      }
      switch (_timeRange) {
        case _TimeRange.days7:
          if (now.difference(q.createdAt).inDays > 7) return false;
        case _TimeRange.days30:
          if (now.difference(q.createdAt).inDays > 30) return false;
        case _TimeRange.days90:
          if (now.difference(q.createdAt).inDays > 90) return false;
        case _TimeRange.custom:
          final range = _customDateRange;
          if (range != null) {
            // 区间为闭区间，end 当天 23:59:59 之后才算越界。
            final endInclusive =
                range.end.add(const Duration(days: 1)).subtract(
                      const Duration(milliseconds: 1),
                    );
            if (q.createdAt.isBefore(range.start) ||
                q.createdAt.isAfter(endInclusive)) {
              return false;
            }
          }
        case _TimeRange.all:
          break;
      }
      return true;
    }).toList();
  }

  ExportStudentInfo? get _studentInfo {
    if (_nameController.text.isEmpty && _classController.text.isEmpty) return null;
    return ExportStudentInfo(
      name: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
      className:
          _classController.text.trim().isEmpty ? null : _classController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return AlertDialog(
      title: const Text('导出选项'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('导出模板', style: _sectionStyle),
              RadioGroup<ExportTemplateType>(
                groupValue: _templateType,
                onChanged: (v) {
                  if (v != null) setState(() => _templateType = v);
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final item in ExportTemplateType.values)
                      RadioListTile<ExportTemplateType>(
                        dense: true,
                        value: item,
                        title: Text(item.label),
                        subtitle: Text(item.description),
                      ),
                  ],
                ),
              ),
              const Divider(),
              const Text('试卷类型', style: _sectionStyle),
              RadioGroup<WorksheetExportMode>(
                groupValue: _mode,
                onChanged: (v) {
                  if (v != null) setState(() => _mode = v);
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final item in WorksheetExportMode.values)
                      RadioListTile<WorksheetExportMode>(
                        dense: true,
                        value: item,
                        title: Text(item.label),
                      ),
                  ],
                ),
              ),
              if (widget.allowFilter) ...<Widget>[
                const Divider(),
                const Text('按学科筛选（不选=全部）', style: _sectionStyle),
                _chipGroup<Subject>(
                  values: Subject.values,
                  selected: _subjects,
                  label: (s) => s.label,
                  onToggle: (s) => setState(() {
                    if (!_subjects.add(s)) _subjects.remove(s);
                  }),
                ),
                const SizedBox(height: 8),
                const Text('按掌握程度筛选（不选=全部）', style: _sectionStyle),
                _chipGroup<MasteryLevel>(
                  values: MasteryLevel.values,
                  selected: _levels,
                  label: _masteryLabel,
                  onToggle: (l) => setState(() {
                    if (!_levels.add(l)) _levels.remove(l);
                  }),
                ),
                if (_availableKnowledgePoints.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  _buildCompactMultiSelect(
                    label: '按知识点筛选',
                    hint: '不选=全部',
                    values: _availableKnowledgePoints.toList()..sort(),
                    selected: _knowledgePoints,
                  ),
                ],
                if (_availableLearningStages.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  _buildCompactMultiSelect(
                    label: '按学习阶段筛选',
                    hint: '不选=全部',
                    values: _availableLearningStages.toList()..sort(),
                    selected: _learningStages,
                  ),
                ],
                if (_availableSources.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  _buildCompactMultiSelect(
                    label: '按来源筛选',
                    hint: '不选=全部',
                    values: _availableSources.toList()..sort(),
                    selected: _sources,
                  ),
                ],
                const SizedBox(height: 8),
                const Text('按错因类别筛选（不选=全部）', style: _sectionStyle),
                _chipGroup<MistakeCategory>(
                  values: MistakeCategory.values,
                  selected: _mistakeCategories,
                  label: (c) => c.label,
                  onToggle: (c) => setState(() {
                    if (!_mistakeCategories.add(c)) _mistakeCategories.remove(c);
                  }),
                ),
                const SizedBox(height: 8),
                const Text('按难度筛选（不选=全部）', style: _sectionStyle),
                _chipGroup<String>(
                  values: QuestionDifficulty.values.map((d) => d.name).toList(),
                  selected: _difficulties,
                  label: (name) => _difficultyLabel(_difficultyFromName(name)),
                  onToggle: (name) => setState(() {
                    if (!_difficulties.add(name)) _difficulties.remove(name);
                  }),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('仅看收藏', style: _sectionStyle),
                  value: _onlyFavorite,
                  onChanged: (v) => setState(() => _onlyFavorite = v),
                ),
                Row(children: <Widget>[
                  const Text('时间范围：', style: _sectionStyle),
                  DropdownButton<_TimeRange>(
                    value: _timeRange,
                    items: [
                      for (final r in _TimeRange.values)
                        DropdownMenuItem(
                            value: r, child: Text(_timeRangeLabels[r]!)),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _timeRange = v);
                    },
                  ),
                  if (_timeRange == _TimeRange.custom) ...<Widget>[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: const Icon(CupertinoIcons.calendar, size: 16),
                      label: Text(_customDateRange == null
                          ? '选择日期'
                          : '${_formatDate(_customDateRange!.start)} ~ '
                              '${_formatDate(_customDateRange!.end)}'),
                      onPressed: _pickDateRange,
                    ),
                  ],
                ]),
              ],
              const Divider(),
              const Text('内容选项（勾选导出内容）', style: _sectionStyle),
              _contentOptionTile('含题图', _contentOptions.includeImage,
                  (v) => setState(() => _contentOptions =
                      _contentOptions.copyWith(includeImage: v))),
              _contentOptionTile('含知识点', _contentOptions.includeKnowledgePoints,
                  (v) => setState(() => _contentOptions =
                      _contentOptions.copyWith(includeKnowledgePoints: v))),
              _contentOptionTile('含错因', _contentOptions.includeMistakeReason,
                  (v) => setState(() => _contentOptions =
                      _contentOptions.copyWith(includeMistakeReason: v))),
              _contentOptionTile('含正确答案', _contentOptions.includeCorrectAnswer,
                  (v) => setState(() => _contentOptions =
                      _contentOptions.copyWith(includeCorrectAnswer: v))),
              _contentOptionTile('含解题步骤', _contentOptions.includeSolutionSteps,
                  (v) => setState(() => _contentOptions =
                      _contentOptions.copyWith(includeSolutionSteps: v))),
              _contentOptionTile('含学习建议', _contentOptions.includeStudyAdvice,
                  (v) => setState(() => _contentOptions =
                      _contentOptions.copyWith(includeStudyAdvice: v))),
              _contentOptionTile('含复习次数', _contentOptions.includeReviewCount,
                  (v) => setState(() => _contentOptions =
                      _contentOptions.copyWith(includeReviewCount: v))),
              _contentOptionTile('含收藏标记', _contentOptions.includeFavoriteMark,
                  (v) => setState(() => _contentOptions =
                      _contentOptions.copyWith(includeFavoriteMark: v))),
              _contentOptionTile('含日期', _contentOptions.includeDates,
                  (v) => setState(() => _contentOptions =
                      _contentOptions.copyWith(includeDates: v))),
              _contentOptionTile('含 AI 练习题', _contentOptions.includeExercises,
                  (v) => setState(() => _contentOptions =
                      _contentOptions.copyWith(includeExercises: v))),
              // Phase 11-4：扩展内容字段（默认关闭，避免冗长）。
              _contentOptionTile('含 OCR 识别原文',
                  _contentOptions.includeOcrText,
                  (v) => setState(() => _contentOptions =
                      _contentOptions.copyWith(includeOcrText: v))),
              _contentOptionTile('含完整 AI 分析',
                  _contentOptions.includeAiAnalysis,
                  (v) => setState(() => _contentOptions =
                      _contentOptions.copyWith(includeAiAnalysis: v))),
              _contentOptionTile('含复习历史',
                  _contentOptions.includeReviewHistory,
                  (v) => setState(() => _contentOptions =
                      _contentOptions.copyWith(includeReviewHistory: v))),
              _contentOptionTile('含知识点树路径',
                  _contentOptions.includeKnowledgeTree,
                  (v) => setState(() => _contentOptions =
                      _contentOptions.copyWith(includeKnowledgeTree: v))),
              const Divider(),
              const Text('排版选项', style: _sectionStyle),
              const Text('纸张大小', style: _subSectionStyle),
              RadioGroup<PdfPageSize>(
                groupValue: _layoutOptions.pageSize,
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _layoutOptions =
                        _layoutOptions.copyWith(pageSize: v));
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final item in PdfPageSize.values)
                      RadioListTile<PdfPageSize>(
                        dense: true,
                        value: item,
                        title: Text(item.label),
                      ),
                  ],
                ),
              ),
              const Text('方向', style: _subSectionStyle),
              RadioGroup<PdfOrientation>(
                groupValue: _layoutOptions.orientation,
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _layoutOptions =
                        _layoutOptions.copyWith(orientation: v));
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final item in PdfOrientation.values)
                      RadioListTile<PdfOrientation>(
                        dense: true,
                        value: item,
                        title: Text(item.label),
                      ),
                  ],
                ),
              ),
              const Text('边距', style: _subSectionStyle),
              RadioGroup<PdfMargin>(
                groupValue: _layoutOptions.margin,
                onChanged: (v) {
                  if (v != null) {
                    setState(() =>
                        _layoutOptions = _layoutOptions.copyWith(margin: v));
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final item in PdfMargin.values)
                      RadioListTile<PdfMargin>(
                        dense: true,
                        value: item,
                        title: Text(item.label),
                      ),
                  ],
                ),
              ),
              const Text('字号', style: _subSectionStyle),
              RadioGroup<PdfFontSize>(
                groupValue: _layoutOptions.fontSize,
                onChanged: (v) {
                  if (v != null) {
                    setState(() =>
                        _layoutOptions = _layoutOptions.copyWith(fontSize: v));
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final item in PdfFontSize.values)
                      RadioListTile<PdfFontSize>(
                        dense: true,
                        value: item,
                        title: Text(item.label),
                      ),
                  ],
                ),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _layoutOptions.includeCover,
                title: const Text('含封面'),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _layoutOptions =
                        _layoutOptions.copyWith(includeCover: v));
                  }
                },
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _layoutOptions.includeToc,
                title: const Text('含目录'),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _layoutOptions =
                        _layoutOptions.copyWith(includeToc: v));
                  }
                },
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _layoutOptions.includeHeader,
                title: const Text('含页眉'),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _layoutOptions =
                        _layoutOptions.copyWith(includeHeader: v));
                  }
                },
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _layoutOptions.includeFooter,
                title: const Text('含页脚'),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _layoutOptions =
                        _layoutOptions.copyWith(includeFooter: v));
                  }
                },
              ),
              TextField(
                controller: _footerTextController,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '页脚内容（可选）',
                  hintText: '支持占位符 {page} {date} {studentName}',
                ),
                onChanged: (v) {
                  // 仅暂存到输入框；持久化与导出时再写回 _layoutOptions。
                },
              ),
              const Divider(),
              const Text('学生信息（可选，填在封面）', style: _sectionStyle),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '姓名',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _classController,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '班级',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '将导出 ${filtered.length} 题（共 ${widget.questions.length} 题）',
                style: TextStyle(
                  color: filtered.isEmpty ? Colors.red : Colors.green[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        if (widget.allowPreview)
          TextButton(
            onPressed: filtered.isEmpty ? null : _preview,
            child: const Text('预览'),
          ),
        TextButton(
          onPressed: _cancel,
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: filtered.isEmpty ? null : () => _export(filtered),
          child: const Text('导出'),
        ),
      ],
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initial = _customDateRange ??
        DateTimeRange(
          start: now.subtract(const Duration(days: 30)),
          end: now,
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: initial,
      helpText: '选择日期范围',
      saveText: '确定',
    );
    if (picked != null && mounted) {
      setState(() => _customDateRange = picked);
    }
  }

  Future<void> _cancel() async {
    await _savePreferences();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _preview() async {
    await _savePreferences();
    final filtered = _filtered;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HtmlPreviewScreen(
          questions: filtered,
          mode: _mode,
          studentInfo: _studentInfo,
        ),
      ),
    );
    if (!mounted) return;
    // 预览页已提供分享/导出 PDF 入口，返回后直接关闭对话框。
    Navigator.of(context).pop(null);
  }

  Future<void> _export(List<QuestionRecord> filtered) async {
    await _savePreferences();
    if (!mounted) return;
    // 同步页脚输入框到 _layoutOptions：空串视为 null（用默认计数器）。
    final footerText = _footerTextController.text.trim();
    final layout = footerText.isEmpty
        ? _layoutOptions.copyWith(footerText: null)
        : _layoutOptions.copyWith(footerText: footerText);
    Navigator.of(context).pop(ExportOptions(
      mode: _mode,
      filtered: filtered,
      templateType: _templateType,
      studentInfo: _studentInfo,
      selectedKnowledgePoints: Set<String>.of(_knowledgePoints),
      onlyFavorite: _onlyFavorite,
      selectedMistakeCategories: Set<MistakeCategory>.of(_mistakeCategories),
      selectedDifficulties: Set<String>.of(_difficulties),
      selectedLearningStages: Set<String>.of(_learningStages),
      selectedSources: Set<String>.of(_sources),
      dateRange: _timeRange == _TimeRange.custom ? _customDateRange : null,
      contentOptions: _contentOptions,
      layoutOptions: layout,
    ));
  }

  Widget _chipGroup<T>({
    required List<T> values,
    required Set<T> selected,
    required String Function(T) label,
    required ValueChanged<T> onToggle,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 0,
      children: [
        for (final v in values)
          FilterChip(
            label: Text(label(v)),
            selected: selected.contains(v),
            onSelected: (_) => onToggle(v),
          ),
      ],
    );
  }

  /// 大列表多选字段（知识点 / 学习阶段 / 来源）：紧凑行 + 弹出式多选对话框。
  ///
  /// 候选值数量可能很大（几十到上百），用 FilterChip 平铺会让对话框变得超长。
  /// 改为单行紧凑展示「已选 N / 共 M」+ 一个「选择」按钮，点击后弹出
  /// 可滚动的多选对话框，对话框内还提供搜索框（候选 >12 时显示）与
  /// 「全选 / 清空 / 反选」快捷操作。
  Widget _buildCompactMultiSelect({
    required String label,
    required String hint,
    required List<String> values,
    required Set<String> selected,
  }) {
    final selectedInValues = selected.intersection(values.toSet());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => _openMultiSelectDialog(
          label: label,
          values: values,
          selected: selected,
        ),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(label,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      selectedInValues.isEmpty
                          ? hint
                          : '已选 ${selectedInValues.length} / 共 ${values.length} 个'
                              '${_previewSelected(selectedInValues)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: selectedInValues.isEmpty
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(CupertinoIcons.chevron_down,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  /// 拼接前 3 个已选项作为预览，超出显示「等 N 项」。
  String _previewSelected(Set<String> selectedInValues) {
    if (selectedInValues.isEmpty) return '';
    final sorted = selectedInValues.toList()..sort();
    const max = 3;
    final head = sorted.take(max).join('、');
    if (sorted.length <= max) return '：$head';
    return '：$head 等 ${sorted.length} 项';
  }

  Future<void> _openMultiSelectDialog({
    required String label,
    required List<String> values,
    required Set<String> selected,
  }) async {
    final result = await showDialog<Set<String>?>(
      context: context,
      builder: (dialogContext) => _MultiSelectDialog(
        title: label,
        values: values,
        initial: selected,
      ),
    );
    if (result == null) return;
    setState(() {
      selected
        ..clear()
        ..addAll(result);
    });
  }

  Widget _contentOptionTile(
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: value,
      title: Text(title),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

const TextStyle _sectionStyle = TextStyle(
  fontWeight: FontWeight.w600,
  fontSize: 13,
);

const TextStyle _subSectionStyle = TextStyle(
  fontWeight: FontWeight.w500,
  fontSize: 12,
  color: Color(0xFF666666),
);

String _masteryLabel(MasteryLevel level) => switch (level) {
      MasteryLevel.newQuestion => '待学习',
      MasteryLevel.reviewing => '复习中',
      MasteryLevel.mastered => '已掌握',
    };

String _difficultyLabel(QuestionDifficulty? difficulty) {
  if (difficulty == null) return '';
  return switch (difficulty) {
    QuestionDifficulty.foundation => '基础',
    QuestionDifficulty.advanced => '提高',
    QuestionDifficulty.challenge => '压轴 / 挑战',
    QuestionDifficulty.custom => '自定义',
  };
}

QuestionDifficulty? _difficultyFromName(String name) {
  for (final d in QuestionDifficulty.values) {
    if (d.name == name) return d;
  }
  return null;
}

String _formatDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

List<Subject> _readSubjectList(List<String>? raw) {
  if (raw == null) return const <Subject>[];
  final result = <Subject>[];
  for (final name in raw) {
    for (final s in Subject.values) {
      if (s.name == name) {
        result.add(s);
        break;
      }
    }
  }
  return result;
}

List<MasteryLevel> _readLevelList(List<String>? raw) {
  if (raw == null) return const <MasteryLevel>[];
  final result = <MasteryLevel>[];
  for (final name in raw) {
    for (final l in MasteryLevel.values) {
      if (l.name == name) {
        result.add(l);
        break;
      }
    }
  }
  return result;
}

List<MistakeCategory> _readMistakeCategoryList(List<String>? raw) {
  if (raw == null) return const <MistakeCategory>[];
  final result = <MistakeCategory>[];
  for (final name in raw) {
    for (final c in MistakeCategory.values) {
      if (c.name == name) {
        result.add(c);
        break;
      }
    }
  }
  return result;
}

Map<String, dynamic> _encodeContentOptions(ExportContentOptions o) =>
    <String, dynamic>{
      'includeImage': o.includeImage,
      'includeKnowledgePoints': o.includeKnowledgePoints,
      'includeMistakeReason': o.includeMistakeReason,
      'includeCorrectAnswer': o.includeCorrectAnswer,
      'includeSolutionSteps': o.includeSolutionSteps,
      'includeStudyAdvice': o.includeStudyAdvice,
      'includeReviewCount': o.includeReviewCount,
      'includeFavoriteMark': o.includeFavoriteMark,
      'includeDates': o.includeDates,
      'includeExercises': o.includeExercises,
      // Phase 11-4：扩展字段，旧版本存储没有这些键，反序列化时回退到 false。
      'includeOcrText': o.includeOcrText,
      'includeAiAnalysis': o.includeAiAnalysis,
      'includeReviewHistory': o.includeReviewHistory,
      'includeKnowledgeTree': o.includeKnowledgeTree,
    };

ExportContentOptions _decodeContentOptions(String json) {
  try {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return ExportContentOptions(
      includeImage: map['includeImage'] as bool? ?? true,
      includeKnowledgePoints: map['includeKnowledgePoints'] as bool? ?? true,
      includeMistakeReason: map['includeMistakeReason'] as bool? ?? true,
      includeCorrectAnswer: map['includeCorrectAnswer'] as bool? ?? true,
      includeSolutionSteps: map['includeSolutionSteps'] as bool? ?? true,
      includeStudyAdvice: map['includeStudyAdvice'] as bool? ?? true,
      includeReviewCount: map['includeReviewCount'] as bool? ?? true,
      includeFavoriteMark: map['includeFavoriteMark'] as bool? ?? true,
      includeDates: map['includeDates'] as bool? ?? true,
      includeExercises: map['includeExercises'] as bool? ?? true,
      // 扩展字段默认 false（与构造函数默认值一致），旧版本存储自然回退。
      includeOcrText: map['includeOcrText'] as bool? ?? false,
      includeAiAnalysis: map['includeAiAnalysis'] as bool? ?? false,
      includeReviewHistory: map['includeReviewHistory'] as bool? ?? false,
      includeKnowledgeTree: map['includeKnowledgeTree'] as bool? ?? false,
    );
  } catch (_) {
    return const ExportContentOptions();
  }
}

Map<String, dynamic> _encodeLayoutOptions(PdfLayoutOptions o) =>
    <String, dynamic>{
      'pageSize': o.pageSize.name,
      'orientation': o.orientation.name,
      'margin': o.margin.name,
      'fontSize': o.fontSize.name,
      'includeCover': o.includeCover,
      'includeToc': o.includeToc,
      'includeHeader': o.includeHeader,
      'includeFooter': o.includeFooter,
      if (o.footerText != null) 'footerText': o.footerText,
    };

PdfLayoutOptions _decodeLayoutOptions(String json) {
  try {
    final map = jsonDecode(json) as Map<String, dynamic>;
    PdfPageSize? pageSize;
    PdfOrientation? orientation;
    PdfMargin? margin;
    PdfFontSize? fontSize;
    final pageSizeName = map['pageSize'] as String?;
    if (pageSizeName != null) {
      for (final v in PdfPageSize.values) {
        if (v.name == pageSizeName) {
          pageSize = v;
          break;
        }
      }
    }
    final orientationName = map['orientation'] as String?;
    if (orientationName != null) {
      for (final v in PdfOrientation.values) {
        if (v.name == orientationName) {
          orientation = v;
          break;
        }
      }
    }
    final marginName = map['margin'] as String?;
    if (marginName != null) {
      for (final v in PdfMargin.values) {
        if (v.name == marginName) {
          margin = v;
          break;
        }
      }
    }
    final fontSizeName = map['fontSize'] as String?;
    if (fontSizeName != null) {
      for (final v in PdfFontSize.values) {
        if (v.name == fontSizeName) {
          fontSize = v;
          break;
        }
      }
    }
    final footerText = map['footerText'] as String?;
    return PdfLayoutOptions(
      pageSize: pageSize ?? PdfPageSize.a4,
      orientation: orientation ?? PdfOrientation.portrait,
      margin: margin ?? PdfMargin.normal,
      fontSize: fontSize ?? PdfFontSize.medium,
      includeCover: map['includeCover'] as bool? ?? true,
      includeToc: map['includeToc'] as bool? ?? false,
      includeHeader: map['includeHeader'] as bool? ?? true,
      includeFooter: map['includeFooter'] as bool? ?? true,
      footerText: (footerText != null && footerText.isEmpty) ? null : footerText,
    );
  } catch (_) {
    return const PdfLayoutOptions();
  }
}

/// 大列表多选对话框：带搜索框（候选 >12 时显示）与「全选 / 清空」快捷按钮。
///
/// 用于知识点 / 学习阶段 / 来源等可能存在几十上百个候选值的字段。
/// 点击「确定」返回新选择集合；点击「取消」返回 null（调用方保持原状）。
class _MultiSelectDialog extends StatefulWidget {
  const _MultiSelectDialog({
    required this.title,
    required this.values,
    required this.initial,
  });

  final String title;
  final List<String> values;
  final Set<String> initial;

  @override
  State<_MultiSelectDialog> createState() => _MultiSelectDialogState();
}

class _MultiSelectDialogState extends State<_MultiSelectDialog> {
  late Set<String> _selected;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.of(widget.initial);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _filtered {
    if (_query.isEmpty) return widget.values;
    final q = _query.toLowerCase();
    return widget.values.where((v) => v.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final showSearch = widget.values.length > 12;
    final filtered = _filtered;
    return AlertDialog(
      title: Row(
        children: <Widget>[
          Expanded(child: Text(widget.title)),
          TextButton(
            onPressed: () => setState(_selected.clear),
            child: const Text('清空'),
          ),
          TextButton(
            onPressed: () => setState(() {
              _selected
                ..clear()
                ..addAll(widget.values);
            }),
            child: const Text('全选'),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showSearch) ...<Widget>[
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '搜索',
                  prefixIcon: Icon(CupertinoIcons.search, size: 18),
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
              const SizedBox(height: 8),
            ],
            Text('已选 ${_selected.length} / 共 ${widget.values.length} 项',
                style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (_, index) {
                  final v = filtered[index];
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _selected.contains(v),
                    title: Text(v, style: const TextStyle(fontSize: 13)),
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          _selected.add(v);
                        } else {
                          _selected.remove(v);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

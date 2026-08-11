import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/services/recognition_confirmation_policy.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_layout.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/cached_question_image.dart';

class RecognitionConfirmationScreen extends ConsumerStatefulWidget {
  const RecognitionConfirmationScreen({super.key});

  @override
  ConsumerState<RecognitionConfirmationScreen> createState() =>
      _RecognitionConfirmationScreenState();
}

class _RecognitionConfirmationScreenState
    extends ConsumerState<RecognitionConfirmationScreen> {
  static const _autoConfirmKey = 'recognition_high_confidence_auto_confirm';
  final _stemController = TextEditingController();
  final _optionsController = TextEditingController();
  final _answerController = TextEditingController();
  final Set<String> _confirmed = <String>{};
  bool _initialized = false;
  bool _busy = false;
  bool _autoConfirm = false;
  bool _showImageOnCompact = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final value = (await SharedPreferences.getInstance()).getBool(_autoConfirmKey) ?? false;
    if (mounted) setState(() => _autoConfirm = value);
  }

  @override
  void dispose() {
    _stemController.dispose();
    _optionsController.dispose();
    _answerController.dispose();
    super.dispose();
  }

  void _initialize(QuestionRecord record) {
    if (_initialized) return;
    final source = record.normalizedQuestionText.trim().isNotEmpty
        ? record.normalizedQuestionText
        : record.extractedQuestionText;
    final options = _parseOptions(source);
    _stemController.text = source
        .split('\n')
        .where((line) => !RegExp(r'^\s*[A-H][.．、]\s*\S').hasMatch(line))
        .join('\n')
        .trim();
    _optionsController.text = options.join('\n');
    _answerController.text = record.studentAnswer ?? '';
    _initialized = true;
  }

  List<String> _parseOptions(String text) => text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => RegExp(r'^[A-H][.．、]\s*\S').hasMatch(line))
      .toList(growable: false);

  RecognitionConfirmationEvaluation _evaluation(QuestionRecord record) {
    return const RecognitionConfirmationPolicy().evaluateQuestion(
      confidence: record.ocrConfidence,
      stem: _stemController.text,
      options: _optionsController.text,
      studentAnswer: _answerController.text,
      imageAvailable: File(record.imagePath).existsSync(),
      risks: _questionRisks,
    );
  }

  List<String> get _questionRisks {
    final text = '${_stemController.text}\n${_optionsController.text}';
    return _looksFormulaDamaged(text)
        ? const <String>['公式可能损坏']
        : const <String>[];
  }

  List<String> _riskExplanations(QuestionRecord record, Set<String> required) {
    final explanations = <String>[];
    if (required.contains(RecognitionReviewField.stem)) {
      explanations.add('题干置信度较低或内容为空，请逐字核对。');
    }
    if (required.contains(RecognitionReviewField.options)) {
      explanations.add('选项可能有遗漏或格式变化，请按原图逐项核对。');
    }
    if (required.contains(RecognitionReviewField.studentAnswer)) {
      explanations.add('学生答案需要单独确认，避免把识别结果当作真实作答。');
    }
    if (required.contains(RecognitionReviewField.formulas)) {
      explanations.add('检测到公式结构风险，请确认括号、分式和上下标。');
    }
    if (!File(record.imagePath).existsSync()) {
      explanations.add('原图附件不可用，无法自动核对；请手动录入或重新拍摄。');
    }
    return explanations;
  }

  bool _looksFormulaDamaged(String text) {
    final dollars = RegExp(r'\$').allMatches(text).length;
    final inlineDelimiters = RegExp(r'\\\(|\\\)').allMatches(text).length;
    final displayDelimiters = RegExp(r'\\\[|\\\]').allMatches(text).length;
    return dollars.isOdd ||
        inlineDelimiters.isOdd ||
        displayDelimiters.isOdd ||
        text.contains(r'\frac{') && !text.contains('}');
  }

  @override
  Widget build(BuildContext context) {
    final record = ref.watch(currentQuestionProvider);
    if (record == null) {
      return const Scaffold(body: Center(child: Text('未找到待确认题目')));
    }
    _initialize(record);
    final evaluation = _evaluation(record);
    final required = evaluation.requiredFields;
    final imageAvailable = File(record.imagePath).existsSync();
    final canProceed = (_autoConfirm &&
            evaluation.decision == RecognitionConfirmationDecision.autoPass) ||
        const RecognitionConfirmationPolicy().canProceedQuestion(
          confidence: record.ocrConfidence,
          stem: _stemController.text,
          options: _optionsController.text,
          studentAnswer: _answerController.text,
          confirmedFields: _confirmed,
          imageAvailable: imageAvailable,
          risks: _questionRisks,
        );
    return Scaffold(
      appBar: AppBar(
        title: const Text('识别确认工作台'),
        leading: IconButton(
          onPressed: _busy ? null : () => context.go('/capture/correction'),
          icon: const Icon(CupertinoIcons.chevron_left),
        ),
      ),
      body: AppPage(
        maxWidth: AppContentWidth.wide,
        padding: EdgeInsets.zero,
        child: Column(
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(AppSpace.lg),
              child: AppTaskFlow(
                steps: <String>['拍摄质量', '题目切分', '文字确认', '开始分析'],
                currentStep: 2,
              ),
            ),
            Expanded(
              child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= AppBreakpoints.expanded;
          final image = _imagePane(record);
          final review = _reviewPane(record, required);
          if (wide) {
            return Row(children: <Widget>[
              Expanded(child: image),
              const VerticalDivider(width: 1),
              Expanded(child: review),
            ]);
          }
          return Column(children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: SegmentedButton<bool>(
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment(value: true, icon: Icon(CupertinoIcons.photo), label: Text('原图')),
                  ButtonSegment(value: false, icon: Icon(CupertinoIcons.text_cursor), label: Text('识别文字')),
                ],
                selected: <bool>{_showImageOnCompact},
                onSelectionChanged: (value) => setState(() => _showImageOnCompact = value.first),
              ),
            ),
            Expanded(child: _showImageOnCompact ? image : review),
          ]);
              }),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppContentWidth.standard,
            ),
            child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.md,
            AppSpace.sm,
            AppSpace.md,
            AppSpace.sm,
          ),
          child: Row(children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _saveDraft(record),
                icon: const Icon(CupertinoIcons.doc),
                label: const Text('保留草稿'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: !_busy && canProceed ? () => _confirm(record) : null,
                icon: _busy
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(CupertinoIcons.checkmark_shield),
                label: Text(canProceed ? '确认文字并开始分析' : '请先确认低置信度字段'),
              ),
            ),
          ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _reviewOverview(QuestionRecord record, Set<String> required) {
    final scheme = Theme.of(context).colorScheme;
    final confidence = record.ocrConfidence;
    final confirmedCount = required.where(_confirmed.contains).length;
    final remaining = required.length - confirmedCount;
    final safe = _evaluation(record).decision ==
        RecognitionConfirmationDecision.autoPass;
    final tone = safe
        ? AppTagTone.success
        : remaining > 0
            ? AppTagTone.warning
            : AppTagTone.primary;

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Icon(
              safe
                  ? CupertinoIcons.checkmark_shield_fill
                  : CupertinoIcons.text_badge_checkmark,
              color: scheme.onPrimaryContainer,
              size: 21,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  safe
                      ? '识别结果清晰，可快速确认'
                      : remaining > 0
                          ? '还有 $remaining 项需要你确认'
                          : '字段已确认，可以继续',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  confidence == null
                      ? '识别置信度未标注'
                      : '整体置信度 ${(confidence * 100).round()}% · '
                          '${required.isEmpty ? '无强制风险' : '已确认 $confirmedCount/${required.length}'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          AppTag(
            label: safe
                ? '高置信'
                : remaining > 0
                    ? '待处理'
                    : '已核对',
            useThemeTone: true,
            themeTone: tone,
          ),
        ],
      ),
    );
  }

  Widget _imagePane(QuestionRecord record) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        padding: const EdgeInsets.all(12),
        child: File(record.imagePath).existsSync()
            ? InteractiveViewer(
                minScale: .8,
                maxScale: 5,
                child: Center(child: CachedQuestionImage(record.imagePath, fit: BoxFit.contain)),
              )
            : const Center(child: Text('原图附件缺失，请手动录入或放弃此草稿')),
      );

  Widget _reviewPane(QuestionRecord record, Set<String> required) => ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _reviewOverview(record, required),
          if (_riskExplanations(record, required).isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpace.md),
            AppInfoSection(
              icon: CupertinoIcons.exclamationmark_triangle,
              title: '为什么需要确认',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _riskExplanations(record, required)
                    .map((text) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('• $text'),
                        ))
                    .toList(growable: false),
              ),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          AppInfoSection(
            icon: CupertinoIcons.layers,
            title: '识别来源对照',
            collapsible: true,
            initiallyExpanded: false,
            child: Column(
              children: <Widget>[
                _layerCard(
                  'OCR 原文',
                  record.extractedQuestionText,
                  AppColors.slate,
                ),
                const SizedBox(height: 8),
                _layerCard(
                  'AI 规范化文本',
                  record.normalizedQuestionText,
                  AppColors.accentPurple,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            required.isEmpty ? '确认最终文字' : '优先处理低置信字段',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            required.isEmpty
                ? '内容风险较低，快速核对后即可进入分析。'
                : '只需处理高亮字段，其余内容已自动收纳。',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _stemController,
            minLines: 4,
            maxLines: 10,
            onChanged: (_) => setState(() => _confirmed.remove(RecognitionReviewField.stem)),
            decoration: _fieldDecoration('用户修正题干', RecognitionReviewField.stem, required),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _optionsController,
            minLines: 2,
            maxLines: 8,
            onChanged: (_) => setState(() => _confirmed.remove(RecognitionReviewField.options)),
            decoration: _fieldDecoration('选项（每行一个）', RecognitionReviewField.options, required),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _answerController,
            minLines: 2,
            maxLines: 6,
            onChanged: (_) => setState(() => _confirmed.remove(RecognitionReviewField.studentAnswer)),
            decoration: _fieldDecoration('学生答案', RecognitionReviewField.studentAnswer, required),
          ),
          if (required.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: required.map((field) => FilterChip(
                selected: _confirmed.contains(field),
                label: Text('确认${_fieldLabel(field)}'),
                avatar: Icon(_confirmed.contains(field)
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.exclamationmark_triangle, size: 15),
                onSelected: (value) => setState(() {
                  value ? _confirmed.add(field) : _confirmed.remove(field);
                }),
              )).toList(growable: false),
            ),
          ],
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _autoConfirm,
            onChanged: (value) async {
              setState(() => _autoConfirm = value);
              await (await SharedPreferences.getInstance()).setBool(_autoConfirmKey, value);
            },
            title: const Text('以后高置信度且无结构风险时自动确认'),
            subtitle: const Text('低置信、空题、公式损坏或原图缺失仍会强制进入本页。'),
          ),
          Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _retryRecognition(record),
              icon: const Icon(CupertinoIcons.arrow_clockwise),
              label: const Text('重新识别整题'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _retryRecognition(record, field: RecognitionReviewField.stem),
              icon: const Icon(CupertinoIcons.text_badge_checkmark),
              label: const Text('只重识别题干'),
            ),
          ]),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      );

  InputDecoration _fieldDecoration(String label, String field, Set<String> required) {
    final risky = required.contains(field) && !_confirmed.contains(field);
    return InputDecoration(
      labelText: label,
      filled: risky,
      fillColor: risky ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: .35) : null,
      border: const OutlineInputBorder(),
      helperText: risky ? '低置信度：请修正后点击下方逐项确认' : null,
    );
  }

  Widget _layerCard(String title, String value, Color accent) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: accent.withValues(alpha: .35)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accent)),
          const SizedBox(height: 4),
          SelectableText(value.trim().isEmpty ? '暂无内容' : value, style: const TextStyle(fontSize: 12)),
        ]),
      );

  String _fieldLabel(String field) => switch (field) {
        RecognitionReviewField.stem => '题干',
        RecognitionReviewField.options => '选项',
        RecognitionReviewField.studentAnswer => '学生答案',
        RecognitionReviewField.formulas => '公式',
        _ => field,
      };

  Future<void> _retryRecognition(QuestionRecord record, {String? field}) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final extraction = await ref.read(aiAnalysisServiceProvider).extractQuestionStructure(
        subjectName: record.subject.name,
        imagePath: record.imagePath,
        textHint: record.extractedQuestionText,
        mode: ref.read(captureModeProvider),
      );
      final normalized = extraction.normalizedQuestionText.isNotEmpty
          ? extraction.normalizedQuestionText
          : extraction.extractedQuestionText;
      if (field == null || field == RecognitionReviewField.stem) {
        final options = _parseOptions(normalized);
        _stemController.text = normalized.split('\n')
            .where((line) => !RegExp(r'^\s*[A-H][.．、]\s*\S').hasMatch(line))
            .join('\n').trim();
        if (field == null) _optionsController.text = options.join('\n');
      }
      if (field == null) _answerController.text = extraction.studentAnswer ?? '';
      final wholeQuestion = field == null;
      final updated = record.withOcrConfidence(
        wholeQuestion ? extraction.ocrConfidence : record.ocrConfidence,
        extractedQuestionText: wholeQuestion
            ? extraction.extractedQuestionText
            : record.extractedQuestionText,
        normalizedQuestionText: <String>[
          _stemController.text.trim(),
          _optionsController.text.trim(),
        ].where((value) => value.isNotEmpty).join('\n'),
        studentAnswer: wholeQuestion
            ? extraction.studentAnswer
            : record.studentAnswer,
      );
      await ref.read(questionRepositoryProvider).saveDraft(updated);
      if (mounted) {
        setState(() {
          if (wholeQuestion) {
            _confirmed.clear();
          } else {
            _confirmed.remove(RecognitionReviewField.stem);
            _confirmed.remove(RecognitionReviewField.formulas);
          }
          ref.read(currentQuestionProvider.notifier).state = updated;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '重新识别失败：$error。可继续手动录入并保留草稿。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm(QuestionRecord record) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final normalized = <String>[
        _stemController.text.trim(),
        _optionsController.text.trim(),
      ].where((value) => value.isNotEmpty).join('\n');
      final updated = record.copyWith(
        normalizedQuestionText: normalized,
        studentAnswer: _answerController.text.trim(),
        contentStatus: ContentStatus.analyzing,
        tags: record.tags
            .where((tag) => tag != RecognitionConfirmationPolicy.requiredTag)
            .toList(growable: false),
      );
      await ref.read(questionRepositoryProvider).saveDraft(updated);
      if (!mounted) return;
      ref.read(currentQuestionProvider.notifier).state = updated;
      context.go('/analysis/loading');
    } catch (error) {
      if (mounted) setState(() => _error = '确认并开始分析失败：$error。请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveDraft(QuestionRecord record) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final updated = record.copyWith(
        normalizedQuestionText: <String>[
          _stemController.text.trim(),
          _optionsController.text.trim(),
        ].where((value) => value.isNotEmpty).join('\n'),
        studentAnswer: _answerController.text.trim(),
        contentStatus: ContentStatus.needsConfirmation,
      );
      await ref.read(questionRepositoryProvider).saveDraft(updated);
      if (!mounted) return;
      ref.read(currentQuestionProvider.notifier).state = updated;
      context.go('/notebook');
    } catch (error) {
      if (mounted) setState(() => _error = '保留草稿失败：$error。请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

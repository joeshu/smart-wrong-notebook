import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/files/image_fingerprint.dart';
import 'package:smart_wrong_notebook/src/data/services/custom_http_document_layout_service.dart';
import 'package:smart_wrong_notebook/src/data/services/auto_document_layout_service.dart';
import 'package:smart_wrong_notebook/src/data/services/mineru_document_layout_service.dart';
import 'package:smart_wrong_notebook/src/data/services/paddle_cloud_document_layout_service.dart';
import 'package:smart_wrong_notebook/src/data/repositories/worksheet_review_draft_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_review_summary.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';
import 'package:smart_wrong_notebook/src/domain/services/question_region_map_editor.dart';
import 'package:smart_wrong_notebook/src/domain/services/question_assembly_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/recognition_confirmation_policy.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/cached_question_image.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/post_recognition_ai_dialog.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/single_text_field_dialog.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/stage_indicator.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/status_pill.dart';
import 'package:uuid/uuid.dart';

/// Manual multi-region editor. A tap places a question-sized candidate box;
/// confirmed boxes are cropped into independent question drafts.
class WorksheetRegionEditorScreen extends ConsumerStatefulWidget {
  const WorksheetRegionEditorScreen({super.key});

  @override
  ConsumerState<WorksheetRegionEditorScreen> createState() =>
      _WorksheetRegionEditorScreenState();
}

class _WorksheetRegionEditorScreenState
    extends ConsumerState<WorksheetRegionEditorScreen> {
  final List<QuestionRegion> _regions = <QuestionRegion>[];
  bool _isCropping = false;
  String? _retryingRegionId;
  bool _isDetecting = false;
  String? _detectionMessage;
  String? _detectionProvider;
  String? _detectionWarning;
  Duration? _detectionDuration;
  // Phase 10-2：分阶段进度条状态。识别中由 service 的 onStage 回调填充；
  // 识别完成/失败时清空，回退到 _detectionMessage 文本展示。
  List<String>? _detectionStages;
  int _detectionStageCurrent = 0;
  String? _detectionStageDetail;
  final WorksheetReviewDraftRepository _draftRepository = WorksheetReviewDraftRepository();
  Timer? _draftSaveTimer;
  bool _didCheckDraft = false;
  String? _draftStatus;
  String? _selectedRegionId;
  // 手动拖动框选：起点 + 实时预览矩形（归一化坐标）。
  Offset? _dragStart;
  Rect? _dragPreview;
  // 题目校对工作台折叠状态：默认收起，把空间留给图片框选区。
  bool _workbenchExpanded = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() => restoreLayoutProviderConfig(ref));
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    super.dispose();
  }

  void _scheduleDraftSave(String pageId) {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 600), () async {
      if (_regions.isEmpty) return;
      await _draftRepository.save(pageId, _regions);
      if (mounted) setState(() => _draftStatus = '已自动保存');
    });
  }

  /// 原图不可用时让用户重新选图，写回工作台 session 与 currentQuestionProvider。
  ///
  /// 选图后同时把当前页 imagePath 更新到工作台 session，并刷新 currentQuestionProvider，
  /// 这样 build() 立即从空状态切回正常态，无需 push/pop。
  Future<void> _reselectPageImage(QuestionRecord page) async {
    final messenger = ScaffoldMessenger.of(context);
    final XFile? picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2560,
      maxHeight: 2560,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    try {
      final storage = ref.read(imageStorageServiceProvider);
      final newPath = await storage.saveImage(File(picked.path));
      final oldPath = page.imagePath;
      final updated = page.copyWith(imagePath: newPath);
      // 同步到工作台 session，避免回到工作台后看到的仍是失效路径。
      final worksheet = ref.read(currentWorksheetImportProvider);
      if (worksheet != null) {
        final nextPages = worksheet.pages.map((item) => item.id == page.id
            ? updated : item).toList();
        await persistWorksheetImport(ref, worksheet.copyWith(pages: nextPages));
      }
      ref.read(currentQuestionProvider.notifier).state = updated;
      if (oldPath.isNotEmpty && oldPath != newPath) {
        await storage.deleteImage(oldPath);
      }
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text('已重新选图，可继续框选切题'),
        duration: Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('重新选图失败: $e')));
    }
  }

  Future<void> _restoreDraftIfNeeded(QuestionRecord page) async {
    if (_didCheckDraft) return;
    _didCheckDraft = true;
    final saved = await _draftRepository.load(page.id);
    if (saved == null || saved.isEmpty || !mounted) return;
    final resume = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('恢复未完成逐题校对？'),
        content: Text('检测到 ${saved.length} 道题目的本地草稿，包括题框、文字校对和采用状态。'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('放弃草稿并重新识别')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('继续校对')),
        ],
      ),
    );
    if (!mounted) return;
    if (resume == true) {
      setState(() {
        _regions..clear()..addAll(saved);
        _selectedRegionId = saved.first.id;
        _draftStatus = '已恢复本地草稿';
      });
    } else {
      await _draftRepository.clear(page.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(currentQuestionProvider);
    if (page == null || !File(page.imagePath).existsSync()) {
      return Scaffold(
        appBar: AppBar(title: const Text('整页框选切题')),
        body: AppEmptyState(
          icon: CupertinoIcons.photo,
          title: page == null ? '未找到可框选的试卷页面' : '原图不可用',
          description: page == null
              ? '请返回工作台重新选择试卷页面。'
              : '原始试卷图片已丢失，可重新选择图片后继续框选切题。',
          action: page == null
              ? null
              : FilledButton.icon(
                  onPressed: () => _reselectPageImage(page),
                  icon: const Icon(CupertinoIcons.photo_on_rectangle),
                  label: const Text('重新选图'),
                ),
        ),
      );
    }
    Future<void>.microtask(() => _restoreDraftIfNeeded(page));
    final scheme = Theme.of(context).colorScheme;
    final layoutConfig = ref.watch(layoutProviderConfigProvider);
    final oneShotType = ref.watch(oneShotLayoutProviderTypeProvider);
    return PopScope(
      canPop: !_isDetecting && !_isCropping,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmExitWhileBusy();
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('整页框选切题'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: _isCropping ? null : () => _confirmExitWhileBusy(),
        ),
      ),
      body: SafeArea(
        child: Column(children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: AppTaskFlow(
              steps: <String>['拍摄质量', '题目切分', '文字确认', '开始分析'],
              currentStep: 1,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: _DetectionActionCard(
              isDetecting: _isDetecting,
              selectedType: _selectedStrategyLabel(
                oneShotType == null
                    ? layoutConfig
                    : LayoutProviderConfig(type: oneShotType),
              ),
              onAuto: _isCropping || _isDetecting ? null : () => _detectRegions(page, override: oneShotType),
              onPaddle: _isCropping || _isDetecting || !_hasPaddleToken(layoutConfig) ? null : () => _detectRegions(page, override: LayoutProviderType.paddleCloud),
              onMineru: _isCropping || _isDetecting || !_hasMineruToken(layoutConfig) ? null : () => _detectRegions(page, override: LayoutProviderType.mineruCloud),
              onOpenSettings: () => context.push('/settings/layout'),
              onManual: _isCropping || _isDetecting ? null : _clearForManual,
              paddleReady: _hasPaddleToken(layoutConfig),
              mineruReady: _hasMineruToken(layoutConfig),
            ),
          ),
          if (_detectionProvider != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: _DetectionResultCard(
                provider: _detectionProvider!,
                regions: _regions,
                duration: _detectionDuration,
                warning: _detectionWarning,
                compact: true,
              ),
            )
          else if (_isDetecting && _detectionStages != null && _detectionStages!.isNotEmpty)
            // Phase 10-2：识别中且 service 已上报阶段 → 渲染分阶段进度条。
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: _DetectionStageCard(
                stages: _detectionStages!,
                current: _detectionStageCurrent,
                detail: _detectionStageDetail,
                message: _detectionMessage,
              ),
            )
          else if (_detectionMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              child: Text(_detectionMessage!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Text(
              '在图上拖动框选题目区域，松开生成题框；轻点放默认题框。拖动彩色框调整，点框后可合并或拆分。',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          if (_selectedRegionIndex >= 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
              child: _RegionMapActionBar(
                regionNumber: _selectedRegionIndex + 1,
                canMerge: _regions.length > 1,
                onMerge: () => _mergeSelectedRegion(page.id),
                onSplit: () => _splitSelectedRegion(page.id),
                onReview: () => setState(() => _workbenchExpanded = true),
              ),
            ),
          if (_regions.isNotEmpty)
            Flexible(
              flex: _workbenchExpanded ? 1 : 0,
              fit: _workbenchExpanded ? FlexFit.tight : FlexFit.loose,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.32,
                ),
                child: Column(
                  mainAxisSize: _workbenchExpanded ? MainAxisSize.max : MainAxisSize.min,
                  children: <Widget>[
                    InkWell(
                      onTap: () => setState(() => _workbenchExpanded = !_workbenchExpanded),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                        child: Row(children: <Widget>[
                          Icon(
                            _workbenchExpanded
                                ? CupertinoIcons.chevron_down
                                : CupertinoIcons.chevron_right,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '已识别 ${_regions.length} 道题 · '
                              '${_regions.where((r) => r.reviewStatus == QuestionRegionReviewStatus.accepted).length} 题采用 · '
                              '点击${_workbenchExpanded ? '收起' : '展开校对文字'}',
                              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ]),
                      ),
                    ),
                    if (_workbenchExpanded)
                      Expanded(
                        child: _RecognizedQuestionWorkbench(
                          regions: _regions,
                          defaultSubject: page.subject,
                          onUpdate: (index, next) => setState(() {
                            final previous = _regions[index];
                            _regions[index] = next.copyWith(
                              originalRecognizedText: previous.originalRecognizedText ?? previous.recognizedText,
                            );
                            _scheduleDraftSave(page.id);
                          }),
                          onIgnore: (index) => setState(() {
                            final region = _regions[index];
                            _regions[index] = region.copyWith(
                              reviewStatus: region.reviewStatus == QuestionRegionReviewStatus.ignored
                                  ? QuestionRegionReviewStatus.accepted
                                  : QuestionRegionReviewStatus.ignored,
                            );
                            _scheduleDraftSave(page.id);
                          }),
                          selectedRegionId: _selectedRegionId,
                          sourceImagePath: page.imagePath,
                          retryingRegionId: _retryingRegionId,
                          onRetryRecognition: (index, field) =>
                              _retryRegionRecognition(page, index, field: field),
                          onSelect: (region) => setState(() => _selectedRegionId = region.id),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            flex: 2,
            child: LayoutBuilder(builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return GestureDetector(
                // 手动拖动框选：按下拖动画矩形，松开生成题框；
                // 轻点（拖动距离很小）则放一个默认大小题框居中于落点。
                onPanStart: _isCropping ? null : (details) {
                  _dragStart = details.localPosition;
                  setState(() {
                    _dragPreview = Rect.fromLTWH(
                      (_dragStart!.dx / size.width).clamp(0.0, 1.0),
                      (_dragStart!.dy / size.height).clamp(0.0, 1.0),
                      0.0,
                      0.0,
                    );
                  });
                },
                onPanUpdate: _isCropping ? null : (details) {
                  if (_dragStart == null) return;
                  final startN = Offset(
                    (_dragStart!.dx / size.width).clamp(0.0, 1.0),
                    (_dragStart!.dy / size.height).clamp(0.0, 1.0),
                  );
                  final curN = Offset(
                    (details.localPosition.dx / size.width).clamp(0.0, 1.0),
                    (details.localPosition.dy / size.height).clamp(0.0, 1.0),
                  );
                  setState(() {
                    _dragPreview = Rect.fromLTRB(
                      math.min(startN.dx, curN.dx),
                      math.min(startN.dy, curN.dy),
                      math.max(startN.dx, curN.dx),
                      math.max(startN.dy, curN.dy),
                    );
                  });
                },
                onPanEnd: _isCropping ? null : (details) {
                  if (_dragStart == null || _dragPreview == null) {
                    _dragStart = null;
                    _dragPreview = null;
                    return;
                  }
                  final r = _dragPreview!;
                  const defaultWidth = 0.80;
                  const defaultHeight = 0.20;
                  setState(() {
                    if (r.width > 0.05 && r.height > 0.03) {
                      // 拖动画框：直接用拖动范围作为题框。
                      final region = QuestionRegion(
                        id: const Uuid().v4(),
                        normalizedRect: r,
                      );
                      _regions.add(region);
                      _selectedRegionId = region.id;
                    } else {
                      // 轻点：放默认大小题框，落点水平居中。
                      final region = QuestionRegion(
                        id: const Uuid().v4(),
                        normalizedRect: Rect.fromLTWH(
                          (_dragStart!.dx / size.width - defaultWidth / 2)
                              .clamp(0.0, 1 - defaultWidth)
                              .toDouble(),
                          (_dragStart!.dy / size.height - defaultHeight / 2)
                              .clamp(0.0, 1 - defaultHeight)
                              .toDouble(),
                          defaultWidth,
                          defaultHeight,
                        ),
                      );
                      _regions.add(region);
                      _selectedRegionId = region.id;
                    }
                    _dragStart = null;
                    _dragPreview = null;
                  });
                },
                child: Stack(fit: StackFit.expand, children: <Widget>[
                  CachedQuestionImage(page.imagePath, fit: BoxFit.fill),
                  ..._regions.asMap().entries.map((entry) {
                    final quality = _RegionQuality.evaluate(_regions, entry.key);
                    return _RegionOverlay(
                      region: entry.value.copyWith(confidence: quality),
                      number: entry.key + 1,
                      canvasSize: size,
                      onDelete: () => setState(() => _regions.removeAt(entry.key)),
                      selected: entry.value.id == _selectedRegionId,
                      onSelect: () => setState(() => _selectedRegionId = entry.value.id),
                      onChanged: (rect) => setState(() {
                        _regions[entry.key] = entry.value.copyWith(
                          normalizedRect: rect,
                          confidence: entry.value.source == QuestionRegionSource.manual ? 1 : .90,
                        );
                        _scheduleDraftSave(page.id);
                      }),
                    );
                  }),
                  // 拖动框选实时预览。
                  if (_dragPreview != null)
                    Positioned(
                      left: _dragPreview!.left * size.width,
                      top: _dragPreview!.top * size.height,
                      width: _dragPreview!.width * size.width,
                      height: _dragPreview!.height * size.height,
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: const Color(0xFF7C3AED), width: 2),
                            color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                          ),
                        ),
                      ),
                    ),
                ]),
              );
            }),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: FilledButton.icon(
              onPressed: _isCropping || _regions.where((region) => region.reviewStatus == QuestionRegionReviewStatus.accepted).isEmpty ? null : () => _confirmAndCrop(page),
              icon: _isCropping ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(CupertinoIcons.crop),
              label: Text(_isCropping ? '正在生成独立题图...' : '确认并生成 ${_regions.where((region) => region.reviewStatus == QuestionRegionReviewStatus.accepted).length} 道题'),
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
            ),
          ),
        ]),
      ),
    ),
    );
  }

  /// 识别中或裁切中退出时弹确认框，避免任务被误中断。
  Future<void> _confirmExitWhileBusy() async {
    final messenger = ScaffoldMessenger.of(context);
    final busy = _isDetecting || _isCropping;
    if (!busy) {
      context.go('/worksheet/import');
      return;
    }
    final reason = _isDetecting ? '识别任务正在进行' : '正在生成独立题图';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确定退出？'),
        content: Text('$reason，退出后当前进度不会自动保存到草稿之外的位置。\n是否仍要退出？'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('继续等待')),
          FilledButton.tonal(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出')),
        ],
      ),
    );
    if (confirmed == true) {
      context.go('/worksheet/import');
    } else {
      // 用户取消时给出反馈
      messenger.showSnackBar(const SnackBar(content: Text('已继续当前任务'), duration: Duration(seconds: 1)));
    }
  }

  bool _hasPaddleToken(LayoutProviderConfig config) =>
      config.type == LayoutProviderType.autoCloud ? config.apiKey.isNotEmpty :
      config.type == LayoutProviderType.paddleCloud && config.apiKey.isNotEmpty;

  bool _hasMineruToken(LayoutProviderConfig config) =>
      config.type == LayoutProviderType.autoCloud ? config.secondaryApiKey.isNotEmpty :
      config.type == LayoutProviderType.mineruCloud && config.apiKey.isNotEmpty;

  String _selectedStrategyLabel(LayoutProviderConfig? config) {
    switch (config?.type) {
      case LayoutProviderType.autoCloud:
        return '自动智能识别 · PaddleOCR → MinerU 兜底';
      case LayoutProviderType.paddleCloud:
        return 'PaddleOCR AI Studio · 快速识别';
      case LayoutProviderType.mineruCloud:
        return 'MinerU VLM · 深度解析';
      case LayoutProviderType.currentVision:
        return '当前 AI 视觉模型';
      case LayoutProviderType.customHttp:
        return '自定义 HTTP 版面服务';
      case LayoutProviderType.manualOnly:
        return '仅手动框选';
      case null:
        return '正在读取识别设置…';
    }
  }

  void _clearForManual() {
    setState(() {
      _regions.clear();
      _selectedRegionId = null;
      _detectionProvider = null;
      _detectionWarning = null;
      _detectionDuration = null;
      _detectionMessage = '已切换为手动框选：点击试卷空白处可新增题框。';
    });
  }

  int get _selectedRegionIndex =>
      _regions.indexWhere((region) => region.id == _selectedRegionId);

  void _mergeSelectedRegion(String pageId) {
    final selectedIndex = _selectedRegionIndex;
    if (selectedIndex < 0 || _regions.length < 2) return;
    final selected = _regions[selectedIndex];
    var nearestIndex = -1;
    var nearestDistance = double.infinity;
    for (var index = 0; index < _regions.length; index++) {
      if (index == selectedIndex) continue;
      final candidate = _regions[index];
      final dx = selected.normalizedRect.center.dx -
          candidate.normalizedRect.center.dx;
      final dy = selected.normalizedRect.center.dy -
          candidate.normalizedRect.center.dy;
      final distance = dx * dx + dy * dy;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
      }
    }
    if (nearestIndex < 0) return;
    final other = _regions[nearestIndex];
    final merged = const QuestionRegionMapEditor().merge(selected, other);
    setState(() {
      _regions[selectedIndex] = merged;
      _regions.removeAt(nearestIndex);
      _selectedRegionId = merged.id;
      _detectionWarning = '已合并相邻题框，请核对题干、选项和图形是否属于同一道题。';
    });
    _scheduleDraftSave(pageId);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已合并相邻题框；字段确认已重置，请重新核对')),
    );
  }

  void _splitSelectedRegion(String pageId) {
    final index = _selectedRegionIndex;
    if (index < 0) return;
    final selected = _regions[index];
    try {
      final split = const QuestionRegionMapEditor().splitVertically(
        selected,
        secondId: const Uuid().v4(),
      );
      setState(() {
        _regions[index] = split.first;
        _regions.insert(index + 1, split.second);
        _selectedRegionId = split.second.id;
        _detectionWarning = '已从中线拆分题框；请拖动边界并分别重新识别上下区域。';
      });
      _scheduleDraftSave(pageId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已上下拆分；请拖动边界并重新识别两个题框')),
      );
    } on FormatException catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${error.message}')),
      );
    }
  }

  Future<void> _detectRegions(QuestionRecord page, {LayoutProviderType? override}) async {
    final startedAt = DateTime.now();
    // 记录本次识别使用的服务名，失败时仍保留在 _detectionProvider 中，
    // 让用户清楚是哪个引擎失败，便于切换或重新配置 Token。
    String? pendingProviderLabel;
    setState(() {
      _isDetecting = true;
      _detectionMessage = override == LayoutProviderType.paddleCloud
          ? '正在使用 PaddleOCR 快速识别…'
          : override == LayoutProviderType.mineruCloud
              ? '正在使用 MinerU VLM 深度解析…'
              : '正在准备识别试卷版面…';
      _detectionProvider = null;
      _detectionWarning = null;
      _detectionDuration = null;
      // Phase 10-2：清空上一次的阶段进度状态，避免残留圆点。
      _detectionStages = null;
      _detectionStageCurrent = 0;
      _detectionStageDetail = null;
    });
    // Phase 10-2：统一的 onStage 回调——把 service 上报的阶段写入 state，
    // 触发 StageIndicator 重渲染。mounted 检查与 service 调用方一致。
    void onStage({required int current, required int total, required String label, String? detail}) {
      if (!mounted) return;
      setState(() {
        // total 可能在多态调用时变化（Auto 调 Paddle 时 Paddle 发的是 4 阶段，
        // 但 Auto 自己只关心 3 阶段）。这里以最近一次上报的 total 为准，
        // 用 List.filled 占位让 StageIndicator 知道圆点数。
        _detectionStages = List<String>.filled(total, '', growable: false);
        if (current >= 0 && current < total) {
          _detectionStages![current] = label;
        }
        _detectionStageCurrent = current;
        _detectionStageDetail = detail;
        _detectionMessage = label;
      });
    }
    try {
      final config = override == null
          ? await restoreLayoutProviderConfig(ref)
          : await ref.read(layoutProviderRepositoryProvider).loadForType(override);
      final type = override ?? config.type;
      final effectiveConfig = config;
      if (type == LayoutProviderType.manualOnly) {
        if (mounted) setState(() => _detectionMessage = '当前设置为仅手动框选；可直接点击页面新增题框。');
        return;
      }
      // 提前标注当前服务的可读名称，确保 catch 块能拿到。
      pendingProviderLabel = switch (type) {
        LayoutProviderType.currentVision => '当前视觉模型',
        LayoutProviderType.paddleCloud => 'PaddleOCR PP-StructureV3',
        LayoutProviderType.mineruCloud => 'MinerU VLM',
        LayoutProviderType.autoCloud => 'Auto（自动选择）',
        LayoutProviderType.customHttp => '自定义 HTTP 版面识别',
        LayoutProviderType.manualOnly => '仅手动框选',
      };
      final result = type == LayoutProviderType.customHttp
          ? await CustomHttpDocumentLayoutService(effectiveConfig)
              .detectQuestionRegions(imagePath: page.imagePath, onStage: onStage)
          : type == LayoutProviderType.paddleCloud
              ? await PaddleCloudDocumentLayoutService(effectiveConfig)
                  .detectQuestionRegions(imagePath: page.imagePath, onStage: onStage)
              : type == LayoutProviderType.mineruCloud
                  ? await MineruDocumentLayoutService(effectiveConfig)
                      .detectQuestionRegions(imagePath: page.imagePath, onStage: onStage)
                  : type == LayoutProviderType.autoCloud
                      ? await AutoDocumentLayoutService(
                          effectiveConfig,
                          onStage: onStage,
                        ).detectQuestionRegions(imagePath: page.imagePath)
                  : await ref
                      .read(visionDocumentLayoutServiceProvider)
                      .detectQuestionRegions(imagePath: page.imagePath, onStage: onStage);
      if (!mounted) return;
      final assembly = const QuestionAssemblyService().assemble(result.regions);
      setState(() {
        _regions
          ..clear()
          ..addAll(assembly.regions);
        _selectedRegionId = _regions.isEmpty ? null : _regions.first.id;
        _detectionProvider = result.providerLabel;
        _detectionWarning = result.warning;
        _detectionDuration = DateTime.now().difference(startedAt);
        _detectionMessage = '已生成候选框，请逐一检查后确认裁切。';
        // 识别完成：清空阶段条，避免残留。
        _detectionStages = null;
        _detectionStageCurrent = 0;
        _detectionStageDetail = null;
      });
      if (override == LayoutProviderType.paddleCloud ||
          override == LayoutProviderType.mineruCloud) {
        await _askWhetherToUseAiAfterRecognition();
      }
    } catch (e) {
      if (!mounted) return;
      // 失败时保留服务标签 + 错误原因，让用户知道是哪个引擎失败。
      setState(() {
        _detectionProvider = pendingProviderLabel;
        _detectionMessage = '识别失败（$pendingProviderLabel）：$e\n'
            '你仍可手动点击页面新增题框，或切换其他识别引擎重试。';
        // 失败：清空阶段条，回退到错误文案展示。
        _detectionStages = null;
        _detectionStageCurrent = 0;
        _detectionStageDetail = null;
      });
    } finally {
      if (mounted) setState(() => _isDetecting = false);
    }
  }

  Future<void> _askWhetherToUseAiAfterRecognition() async {
    if (!mounted || _regions.isEmpty) return;
    final choice = await PostRecognitionAiDialog.show(
      context,
      regionCount: _regions.length,
      providerLabel: _detectionProvider ?? 'OCR/文档',
    );
    if (!mounted || choice == null) return;
    if (choice == PostRecognitionAiChoice.perQuestion) return;
    setState(() {
      for (var index = 0; index < _regions.length; index++) {
        _regions[index] = _regions[index].copyWith(
          analyzeWithAi: choice == PostRecognitionAiChoice.all,
        );
      }
    });
  }

  Future<void> _retryRegionRecognition(
    QuestionRecord source,
    int index, {
    String? field,
  }) async {
    final region = _regions[index];
    setState(() => _retryingRegionId = region.id);
    String? temporaryPath;
    try {
      final croppedPath = await ref.read(questionRegionCropServiceProvider).cropToStoredImage(
        sourcePath: source.imagePath,
        region: region,
      );
      temporaryPath = croppedPath;
      final extraction = await ref.read(aiAnalysisServiceProvider).extractQuestionStructure(
        subjectName: (region.subject ?? source.subject).label,
        imagePath: croppedPath,
        textHint: region.recognizedText ?? '',
      );
      final normalized = extraction.normalizedQuestionText.isNotEmpty
          ? extraction.normalizedQuestionText
          : extraction.extractedQuestionText;
      final options = parseOptionLines(normalized);
      final stem = normalized.split('\n')
          .where((line) => !RegExp(r'^\s*[A-H][.．、]\s*\S').hasMatch(line))
          .join('\n').trim();
      final formulas = RegExp(r'\$[^$]+\$').allMatches(normalized)
          .map((match) => match.group(0)!)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        var next = region;
        if (field == null) {
          next = region.copyWith(
            originalRecognizedText: extraction.extractedQuestionText,
            recognizedText: normalized,
            aiNormalizedText: normalized,
            questionStem: stem,
            options: options,
            formulas: formulas,
            studentAnswer: extraction.studentAnswer ?? '',
            confirmedFields: const <String>{},
          );
        } else if (field == RecognitionReviewField.stem) {
          next = region.copyWith(questionStem: stem, aiNormalizedText: normalized);
        } else if (field == RecognitionReviewField.options) {
          next = region.copyWith(options: options, aiNormalizedText: normalized);
        } else if (field == RecognitionReviewField.studentAnswer) {
          next = region.copyWith(studentAnswer: extraction.studentAnswer ?? '');
        } else if (field == RecognitionReviewField.formulas) {
          next = region.copyWith(formulas: formulas, aiNormalizedText: normalized);
        }
        _regions[index] = next;
        _scheduleDraftSave(source.id);
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重新识别失败：$error。当前修正内容和草稿已保留。')),
        );
      }
    } finally {
      if (temporaryPath != null) {
        final temporary = File(temporaryPath);
        if (await temporary.exists()) await temporary.delete();
      }
      if (mounted) setState(() => _retryingRegionId = null);
    }
  }

  Future<void> _editRecognizedText(int index) async {
    final region = _regions[index];
    final saved = await showSingleTextFieldDialog(
      context: context,
      title: '编辑第 ${region.detectedNumber ?? index + 1} 题文字',
      initialText: region.recognizedText ?? '',
      minLines: 5,
      maxLines: 10,
      hintText: '可校对文字、公式 LaTex 与表格 Markdown',
      confirmText: '采用文字',
    );
    if (saved == null || !mounted) return;
    setState(() {
      _regions[index] = region.copyWith(
        recognizedText: saved,
        contentFormatHint: saved.contains(r'$') || saved.contains(r'\\')
            ? 'latexMixed'
            : 'plain',
      );
    });
  }

  Future<void> _confirmAndCrop(QuestionRecord source) async {
    const policy = RecognitionConfirmationPolicy();
    final accepted = _regions.where((item) => item.reviewStatus == QuestionRegionReviewStatus.accepted).toList();
    final blocked = <QuestionRegion>[];
    for (var index = 0; index < _regions.length; index++) {
      final region = _regions[index];
      if (region.reviewStatus == QuestionRegionReviewStatus.accepted &&
          !policy.canProceed(
            region,
            detectQuestionRegionRisks(region, _regions, index: index),
          )) {
        blocked.add(region);
      }
    }
    if (blocked.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('仍有题目需要确认'),
          content: Text('${blocked.length} 道题存在低置信度字段或结构风险。请逐字段确认；贴边、重叠等空间风险必须先调整题框。'),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('返回待处理队列'),
            ),
          ],
        ),
      );
      return;
    }
    final aiCount = accepted.where((item) => item.analyzeWithAi).length;
    final ocrCount = accepted.length - aiCount;
    final ignoredCount = _regions.length - accepted.length;
    final risky = accepted.where((item) {
      final edge = item.normalizedRect.left < .01 || item.normalizedRect.top < .01 ||
          item.normalizedRect.right > .99 || item.normalizedRect.bottom > .99;
      return (item.recognizedText ?? '').trim().isEmpty ||
          (item.source == QuestionRegionSource.layoutModel && item.confidence < .60) || edge;
    }).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认本页处理方式'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('本页共 ${_regions.length} 道候选题：'),
          const SizedBox(height: 8),
          Text('✓ $aiCount 题：裁切后交给普通 AI 深度分析'),
          Text('✓ $ocrCount 题：仅保存 OCR / 文档结果'),
          if (ignoredCount > 0) Text('⊘ $ignoredCount 题：忽略，不裁切也不保存'),
          if (risky > 0) Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('⚠ $risky 题存在空题干、低可信度或贴边题框；建议返回继续校对。', style: const TextStyle(fontSize: 12, color: Color(0xFF9A3412))),
          ),
        ]),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('返回继续校对')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('确认生成')),
        ],
      ),
    );
    if (confirmed == true && mounted) await _cropAndQueue(source);
  }

  Future<void> _cropAndQueue(QuestionRecord source) async {
    setState(() {
      _isCropping = true;
      _detectionMessage = '正在裁切题图…';
    });
    try {
      final cropper = ref.read(questionRegionCropServiceProvider);
      final ai = ref.read(aiAnalysisServiceProvider);
      final candidates = <QuestionRecord>[];
      final acceptedRegions = _regions
          .where((item) => item.reviewStatus == QuestionRegionReviewStatus.accepted)
          .toList();
      final recordIdsByRegion = <String, String>{
        for (final region in acceptedRegions) region.id: const Uuid().v4(),
      };
      for (var i = 0; i < acceptedRegions.length; i++) {
        final region = acceptedRegions[i];
        if (mounted) {
          setState(() => _detectionMessage =
              '正在识别第 ${i + 1}/${acceptedRegions.length} 题文字与公式…');
        }

        final path = await cropper.cropToStoredImage(
            sourcePath: source.imagePath, region: region);
        final fingerprint = await ImageFingerprintCodec.fromFile(File(path));
        final perceptual =
            await ImageFingerprintCodec.perceptualFromFile(File(path));

        // 对手动框选区域（无识别文字），调用 AI 识别文字+公式，
        // 并尝试切分多题（一个框选区域可能含多道题）。
        String recognizedText = region.recognizedText ?? '';
        String contentFormatHint = region.contentFormatHint ?? 'plain';
        List<String> splitTexts = const <String>[];

        if (recognizedText.isEmpty) {
          try {
            final extraction = await ai.extractQuestionStructure(
              subjectName: (region.subject ?? source.subject).label,
              imagePath: path,
            );
            recognizedText = extraction.normalizedQuestionText;
            if (recognizedText.contains(r'$') ||
                recognizedText.contains(r'\\')) {
              contentFormatHint = 'latexMixed';
            }
            // AI 切出多题时，用切分结果生成多道题。
            final split = extraction.splitResult;
            if (split != null && split.candidates.length > 1) {
              splitTexts =
                  split.candidates.map((c) => c.text).toList();
            }
          } catch (e) {
            // AI 未配置或调用失败：降级为空文本，后续走 /analysis/loading。
            debugPrint('[WorksheetRegionEditor] AI 识别文字失败: $e');
          }
        }

        final baseTags = (ImageFingerprintCodec.writePerceptual(
          ImageFingerprintCodec.write(source.tags, fingerprint),
          perceptual,
        )
          ..removeWhere((tag) =>
              tag.startsWith('layout_provider:') ||
              tag.startsWith('question_type:') ||
              tag.startsWith('document_blocks:'))
          ..add('layout_provider:${_detectionProvider ?? '手动框选'}')
          ..addAll(region.questionType == null || region.questionType!.isEmpty
              ? const <String>[]
              : <String>['question_type:${region.questionType}'])
          ..addAll(region.recognizedBlockTypes.isEmpty
              ? const <String>[]
              : <String>['document_blocks:${region.recognizedBlockTypes.join('+')}']));
        baseTags
          ..add('reading_order:${region.readingOrder ?? i}')
          ..add('page_column:${region.columnIndex}')
          ..addAll(region.parentRegionId == null
              ? const <String>[]
              : <String>['parent_region:${region.parentRegionId}']);

        final assembledParentId = region.parentRegionId == null
            ? source.id
            : recordIdsByRegion[region.parentRegionId] ?? source.id;

        if (splitTexts.length > 1) {
          // 一个框选区域含多道题：为每题生成独立 QuestionRecord（共用小图）。
          for (var splitIndex = 0; splitIndex < splitTexts.length; splitIndex++) {
            final text = splitTexts[splitIndex];
            final fmt = text.contains(r'$') || text.contains(r'\\')
                ? QuestionContentFormat.latexMixed
                : QuestionContentFormat.plain;
            candidates.add(QuestionRecord.draft(
              id: splitIndex == 0
                  ? recordIdsByRegion[region.id]!
                  : const Uuid().v4(),
              imagePath: path,
              subject: region.subject ?? source.subject,
              recognizedText: text,
              contentFormat: fmt,
            ).copyWith(
              contentStatus: ContentStatus.processing,
              tags: List<String>.from(baseTags),
              parentQuestionId: assembledParentId,
              rootQuestionId: source.rootQuestionId ?? source.id,
              ocrConfidence: region.confidence,
              studentAnswer: region.studentAnswer,
            ));
          }
        } else {
          candidates.add(QuestionRecord.draft(
            id: recordIdsByRegion[region.id]!,
            imagePath: path,
            subject: region.subject ?? source.subject,
            recognizedText: recognizedText,
            contentFormat: contentFormatHint == 'latexMixed'
                ? QuestionContentFormat.latexMixed
                : QuestionContentFormat.plain,
          ).copyWith(
            contentStatus: region.analyzeWithAi
                ? ContentStatus.processing
                : ContentStatus.ready,
            tags: baseTags,
            parentQuestionId: assembledParentId,
            rootQuestionId: source.rootQuestionId ?? source.id,
            ocrConfidence: region.confidence,
            studentAnswer: region.studentAnswer,
          ));
        }
      }
      final worksheet = ref.read(currentWorksheetImportProvider);
      if (worksheet != null) {
        final next = worksheet.pages.where((item) => item.id != source.id).toList()
          ..addAll(candidates);
        await persistWorksheetImport(ref, worksheet.copyWith(pages: next));
      }
      await _draftRepository.clear(source.id);
      _draftSaveTimer?.cancel();
      final nextForAnalysis = candidates.firstWhere(
        (candidate) => candidate.contentStatus == ContentStatus.processing,
        orElse: () => candidates.first,
      );
      ref.read(currentQuestionProvider.notifier).state = nextForAnalysis;
      final aiCount = candidates.where((item) => item.contentStatus == ContentStatus.processing).length;
      final ocrCount = candidates.length - aiCount;
      final ignoredCount = _regions.where((item) => item.reviewStatus == QuestionRegionReviewStatus.ignored).length;
      ref.read(currentWorksheetReviewSummaryProvider.notifier).state = WorksheetReviewSummary(
        sourcePageId: source.id, aiCount: aiCount, ocrCount: ocrCount, ignoredCount: ignoredCount,
      );
      if (!mounted) return;
      context.go('/worksheet/review-summary');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成题图失败: $e')));
    } finally {
      if (mounted) setState(() => _isCropping = false);
    }
  }
}

class _RegionMapActionBar extends StatelessWidget {
  const _RegionMapActionBar({
    required this.regionNumber,
    required this.canMerge,
    required this.onMerge,
    required this.onSplit,
    required this.onReview,
  });

  final int regionNumber;
  final bool canMerge;
  final VoidCallback onMerge;
  final VoidCallback onSplit;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('worksheet-region-map-action-bar'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '题框 $regionNumber',
              style: TextStyle(
                color: scheme.onPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  TextButton.icon(
                    key: const Key('merge-selected-region-button'),
                    onPressed: canMerge ? onMerge : null,
                    icon: const Icon(CupertinoIcons.rectangle_on_rectangle,
                        size: 16),
                    label: const Text('合并相邻'),
                  ),
                  TextButton.icon(
                    key: const Key('split-selected-region-button'),
                    onPressed: onSplit,
                    icon: const Icon(CupertinoIcons.scissors, size: 16),
                    label: const Text('上下拆分'),
                  ),
                  TextButton.icon(
                    onPressed: onReview,
                    icon: const Icon(CupertinoIcons.text_badge_checkmark,
                        size: 16),
                    label: const Text('校对内容'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegionOverlay extends StatelessWidget {
  const _RegionOverlay({
    required this.region,
    required this.number,
    required this.canvasSize,
    required this.onDelete,
    required this.selected,
    required this.onSelect,
    required this.onChanged,
  });
  final QuestionRegion region;
  final int number;
  final Size canvasSize;
  final VoidCallback onDelete;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<Rect> onChanged;

  @override
  Widget build(BuildContext context) {
    final r = region.normalizedRect;
    return Positioned(
      left: r.left * canvasSize.width,
      top: r.top * canvasSize.height,
      width: r.width * canvasSize.width,
      height: r.height * canvasSize.height,
      child: _ResizableRegion(
        region: r,
        canvasSize: canvasSize,
        number: number,
        source: region.source,
        confidence: region.confidence,
        detectedNumber: region.detectedNumber,
        selected: selected,
        onSelect: onSelect,
        onDelete: onDelete,
        onChanged: onChanged,
      ),
    );
  }
}


class _ResizableRegion extends StatefulWidget {
  const _ResizableRegion({
    required this.region,
    required this.canvasSize,
    required this.number,
    required this.source,
    required this.confidence,
    required this.detectedNumber,
    required this.selected,
    required this.onSelect,
    required this.onDelete,
    required this.onChanged,
  });

  final Rect region;
  final Size canvasSize;
  final int number;
  final QuestionRegionSource source;
  final double confidence;
  final String? detectedNumber;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onDelete;
  final ValueChanged<Rect> onChanged;

  @override
  State<_ResizableRegion> createState() => _ResizableRegionState();
}

class _ResizableRegionState extends State<_ResizableRegion> {
  late Rect _region;

  @override
  void initState() {
    super.initState();
    _region = widget.region;
  }

  @override
  void didUpdateWidget(covariant _ResizableRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.region != widget.region) _region = widget.region;
  }

  void _move(Offset delta) {
    final dx = delta.dx / widget.canvasSize.width;
    final dy = delta.dy / widget.canvasSize.height;
    _update(Rect.fromLTWH(
      (_region.left + dx).clamp(0.0, 1 - _region.width).toDouble(),
      (_region.top + dy).clamp(0.0, 1 - _region.height).toDouble(),
      _region.width,
      _region.height,
    ));
  }

  void _resize(Offset delta) {
    final width = (_region.width + delta.dx / widget.canvasSize.width)
        .clamp(.10, 1 - _region.left)
        .toDouble();
    final height = (_region.height + delta.dy / widget.canvasSize.height)
        .clamp(.06, 1 - _region.top)
        .toDouble();
    _update(Rect.fromLTWH(_region.left, _region.top, width, height));
  }

  void _update(Rect next) {
    setState(() => _region = next);
    widget.onChanged(next);
  }

  Color _qualityColor() {
    if (widget.source == QuestionRegionSource.manual) return const Color(0xFF64748B);
    if (widget.confidence >= .80) return const Color(0xFF16A34A);
    if (widget.confidence >= .60) return const Color(0xFF2563EB);
    return const Color(0xFFEA580C);
  }

  String _qualityLabel() {
    if (widget.source == QuestionRegionSource.manual) return '手动';
    if (widget.confidence >= .80) return '较可靠';
    if (widget.confidence >= .60) return '建议检查';
    return '建议调整';
  }

  @override
  Widget build(BuildContext context) {
    final qualityColor = _qualityColor();
    final borderColor = widget.selected ? const Color(0xFF7C3AED) : qualityColor;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: widget.selected ? 4 : 2),
        color: borderColor.withValues(alpha: widget.selected ? .18 : .08),
      ),
      child: Stack(children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onSelect,
            onPanUpdate: (details) => _move(details.delta),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Container(
              color: qualityColor,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(widget.source == QuestionRegionSource.manual
                  ? '手动 · 题 ${widget.number}'
                  : '${widget.detectedNumber ?? widget.number}题 · ${_qualityLabel()} ${(widget.confidence * 100).round()}%',
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
            Material(
              color: const Color(0xFFDC2626),
              child: InkWell(
                onTap: widget.onDelete,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Icon(CupertinoIcons.xmark,
                      color: Colors.white, size: 14),
                ),
              ),
            ),
          ]),
        ),
        Positioned(
          right: -8,
          bottom: -8,
          child: GestureDetector(
            onPanUpdate: (details) => _resize(details.delta),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: qualityColor, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(CupertinoIcons.arrow_down_right,
                  size: 14, color: qualityColor),
            ),
          ),
        ),
      ]),
    );
  }
}


class _DetectionActionCard extends StatelessWidget {
  const _DetectionActionCard({
    required this.isDetecting,
    required this.selectedType,
    required this.onAuto,
    required this.onPaddle,
    required this.onMineru,
    required this.onManual,
    required this.paddleReady,
    required this.mineruReady,
    required this.onOpenSettings,
  });
  final bool isDetecting;
  final String selectedType;
  final VoidCallback? onAuto;
  final VoidCallback? onPaddle;
  final VoidCallback? onMineru;
  final VoidCallback? onManual;
  final bool paddleReady;
  final bool mineruReady;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    color: const Color(0xFFF0F9FF),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
        Row(children: <Widget>[
          const Icon(CupertinoIcons.viewfinder_circle, size: 16, color: Color(0xFF0369A1)),
          const SizedBox(width: 6),
          Expanded(child: Text(isDetecting ? selectedType : '识别策略：$selectedType', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
          if (isDetecting) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: <Widget>[
            FilledButton.tonalIcon(
              onPressed: onAuto,
              icon: const Icon(CupertinoIcons.sparkles, size: 14),
              label: const Text('按策略识别'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 6),
            OutlinedButton(
              onPressed: onPaddle,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(paddleReady ? 'PaddleOCR' : 'PaddleOCR·未配置'),
            ),
            const SizedBox(width: 6),
            OutlinedButton(
              onPressed: onMineru,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(mineruReady ? 'MinerU' : 'MinerU·未配置'),
            ),
            const SizedBox(width: 6),
            TextButton(
              onPressed: onManual,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('手动框选'),
            ),
          ]),
        ),
        if (!paddleReady || !mineruReady) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: <Widget>[
            const Expanded(
              child: Text(
                '未配置的服务不可用，请先填写版面识别 Token。',
                style: TextStyle(fontSize: 12, color: Color(0xFF9A3412)),
              ),
            ),
            TextButton(
              onPressed: onOpenSettings,
              child: const Text('去设置'),
            ),
          ]),
        ),
      ]),
    ),
  );
}

/// Phase 10-2：识别中分阶段进度卡片。
///
/// 渲染 [StageIndicator] + 当前阶段名 + 可选子进度文案。service 失败或
/// 完成时本卡片不会显示（state 已清空 _detectionStages）。
class _DetectionStageCard extends StatelessWidget {
  const _DetectionStageCard({
    required this.stages,
    required this.current,
    required this.detail,
    required this.message,
  });

  final List<String> stages;
  final int current;
  final String? detail;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 用阶段名列表生成渲染用的 steps；service 上报的 label 已写入
    // stages[current]，其他位置为空字符串（StageIndicator 不读取非当前
    // 阶段的 label，只画圆点）。这里补一个 fallback：若 stages 全空
    //（理论上不会发生），用占位 "…" 让圆点至少有尺寸。
    final steps = stages.map((s) => s.isEmpty ? '·' : s).toList(growable: false);
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.primaryContainer.withValues(alpha: 0.18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            StageIndicator(
              steps: steps,
              current: current,
              accent: scheme.primary,
              dimColor: scheme.outlineVariant,
              detail: detail,
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                message!,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetectionResultCard extends StatelessWidget {
  const _DetectionResultCard({required this.provider, required this.regions, required this.duration, required this.warning, this.compact = false});
  final String provider;
  final List<QuestionRegion> regions;
  final Duration? duration;
  final String? warning;
  final bool compact;

  FieldStatus _fieldStatus(String label, bool available, {bool warning = false}) {
    if (available) return FieldStatus.recognized;
    return warning ? FieldStatus.needsReview : FieldStatus.missing;
  }

  bool _hasBlock(String type) => regions.any((region) =>
      region.recognizedBlockTypes.any((item) => item.toLowerCase().contains(type.toLowerCase())));

  bool _hasOptionText() => regions.any((region) {
    final text = region.recognizedText ?? '';
    return RegExp(r'(?:^|\s)[A-H][.．、]\s*\S', multiLine: true).hasMatch(text);
  });
  String _structureSummary(List<QuestionRegion> regions) {
    final counts = <String, int>{};
    for (final region in regions) {
      for (final type in region.recognizedBlockTypes.where((type) => type != '文字')) {
        counts[type] = (counts[type] ?? 0) + 1;
      }
    }
    return counts.entries.map((entry) => '${entry.key} ${entry.value}').join(' · ');
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    color: const Color(0xFFF0FDF4),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        const Row(children: <Widget>[Icon(CupertinoIcons.check_mark_circled_solid, color: Color(0xFF16A34A)), SizedBox(width: 8), Text('候选题框已生成', style: TextStyle(fontWeight: FontWeight.w700))]),
        const SizedBox(height: 7),
        Text('最终服务：$provider · ${regions.length} 道候选题${duration == null ? '' : ' · ${duration!.inSeconds}s'}', style: const TextStyle(fontSize: 12)),
        if (!compact && regions.any((region) => (region.recognizedText ?? '').trim().isNotEmpty)) ...<Widget>[
          const SizedBox(height: 6),
          Text('已同时提取题目文字/公式：${regions.where((region) => (region.recognizedText ?? '').trim().isNotEmpty).length} 道。确认题框后会带入下一步校对，不会丢弃。', style: const TextStyle(fontSize: 12, color: Color(0xFF166534))),
          if (_structureSummary(regions).isNotEmpty)
            Text('结构识别：${_structureSummary(regions)}', style: const TextStyle(fontSize: 12, color: Color(0xFF166534))),
        ],
        if (warning != null && warning!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text('提示：$warning', style: const TextStyle(fontSize: 12, color: Color(0xFF9A3412))),
          ),
        if (regions.isNotEmpty && !compact) ...<Widget>[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              StatusPill(label: '题干', status: _fieldStatus('题干', regions.any((r) => (r.recognizedText ?? '').trim().isNotEmpty))),
              StatusPill(label: '公式', status: _fieldStatus('公式', _hasBlock('公式') || regions.any((r) => r.formulas.isNotEmpty), warning: true)),
              StatusPill(label: '选项', status: _fieldStatus('选项', _hasOptionText(), warning: true)),
              StatusPill(label: '图形', status: _fieldStatus('图形', _hasBlock('图') || _hasBlock('diagram'), warning: true)),
            ],
          ),
        ],

        const Padding(padding: EdgeInsets.only(top: 4), child: Text('可拖动、缩放或删除题框；确认后进入逐题校对。', style: TextStyle(fontSize: 12, color: Color(0xFF475569)))),
      ]),
    ),
  );
}

/// 计算单题字段在对照工作台的展示状态（五态统一判定）。
///
/// 集中字段判定逻辑，避免 `_DetectionResultCard`（汇总卡）与
/// `RecognitionEvidencePreview`（单题对照区）出现文案/配色不一致。
/// 选项字段在非选择题时返回 [FieldStatus.notApplicable]；题型未指定时
/// 按是否识别到选项行判定，避免误判。
///
/// [edited] 为 true 且字段非空/适用时返回 [FieldStatus.edited]，表示
/// 用户已手动校对过该字段（与原始识别结果不同）。
FieldStatus recognitionFieldStatus(
  String field,
  QuestionRegion region, {
  String? stemOverride,
  List<String>? formulasOverride,
  List<String>? tablesOverride,
  bool edited = false,
}) {
  switch (field) {
    case '题干':
      final stem = stemOverride ?? region.questionStem ?? region.recognizedText ?? '';
      if (stem.trim().isEmpty) return FieldStatus.needsReview;
      return edited ? FieldStatus.edited : FieldStatus.recognized;
    case '公式':
      final formulas = formulasOverride ?? region.formulas;
      final has = formulas.isNotEmpty ||
          region.recognizedBlockTypes.any((t) => t == '公式');
      if (!has) return FieldStatus.missing;
      return edited ? FieldStatus.edited : FieldStatus.recognized;
    case '表格':
      final tables = tablesOverride ?? region.tables;
      final has = tables.isNotEmpty ||
          region.recognizedBlockTypes.any((t) => t == '表格');
      if (!has) return FieldStatus.missing;
      return edited ? FieldStatus.edited : FieldStatus.recognized;
    case '选项':
      final type = region.questionType;
      if (type != null &&
          type.isNotEmpty &&
          type != '未指定' &&
          type != '选择题') {
        return FieldStatus.notApplicable;
      }
      // 用户已显式编辑过 options（list 非空）→ 已校对。
      // 与"自动从 recognizedText 解析到选项行"区分开，让用户清楚自己改过。
      if (region.options.isNotEmpty) {
        return FieldStatus.edited;
      }
      return hasOptionLine(region.recognizedText)
          ? (edited ? FieldStatus.edited : FieldStatus.recognized)
          : FieldStatus.needsReview;
    case '图形':
      final has = region.recognizedBlockTypes.any((t) =>
          t == '图形' || t == 'diagram' || t.toLowerCase().contains('diagram'));
      // 已填写图形备注 → 视为人工核对完成，标记"已校对"。
      if ((region.diagramNote ?? '').trim().isNotEmpty) {
        return FieldStatus.edited;
      }
      return has ? FieldStatus.recognized : FieldStatus.needsReview;
    default:
      return FieldStatus.missing;
  }
}

bool hasOptionLine(String? text) {
  if (text == null) return false;
  return RegExp(r'(?:^|\s)[A-H][.．、]\s*\S', multiLine: true).hasMatch(text);
}

/// 从 recognizedText 中按行解析 A./B./C./D. 选项行。
/// 仅匹配行首（允许前导空白）；每行返回 "X. 内容" 形式，已 trim。
List<String> parseOptionLines(String? text) {
  if (text == null) return const <String>[];
  final pattern = RegExp(r'^\s*([A-H])[.．、]\s*(.+?)\s*$');
  final result = <String>[];
  for (final line in text.split('\n')) {
    final match = pattern.firstMatch(line);
    if (match != null) {
      result.add('${match.group(1)}. ${match.group(2)!.trim()}');
    }
  }
  return result;
}

/// 把对话框收集的多行文本规范化为 "A. xxx\nB. yyy" 列表。
/// 已带 A./B./C./D. 前缀的保留原字母；缺前缀的按行序补 A./B./C./D.。
List<String> normalizeOptions(String raw) {
  final lines = raw
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final pattern = RegExp(r'^([A-H])[.．、]\s*(.+)$');
  return List<String>.generate(lines.length, (i) {
    final match = pattern.firstMatch(lines[i]);
    if (match != null) {
      return '${match.group(1)}. ${match.group(2)!.trim()}';
    }
    return '${String.fromCharCode(65 + i)}. ${lines[i]}';
  });
}

class RecognitionEvidencePreview extends StatefulWidget {
  const RecognitionEvidencePreview({
    required this.sourceImagePath,
    required this.region,
    required this.stem,
    required this.formulas,
    required this.tables,
    this.risks = const <String>[],
  });

  final String sourceImagePath;
  final QuestionRegion region;
  final String stem;
  final List<String> formulas;
  final List<String> tables;

  /// 当前题框的全部风险提示。其中与空间布局相关的风险
  /// （贴边/宽高比/面积/重叠）会被单独抽取到对照区原图与字段状态
  /// 附近展示，让用户在对照原图时直接看到题框异常。
  final List<String> risks;

  @override
  State<RecognitionEvidencePreview> createState() =>
      _RecognitionEvidencePreviewState();
}

class _RecognitionEvidencePreviewState
    extends State<RecognitionEvidencePreview> {
  bool _expanded = false;

  List<String> get _spatialRisks => widget.risks.where((item) =>
      item.contains('边缘') ||
      item.contains('宽高比') ||
      item.contains('面积') ||
      item.contains('重叠')).toList();

  @override
  Widget build(BuildContext context) {
    final sourceImage = File(widget.sourceImagePath);
    final imageExists = sourceImage.existsSync();
    final rect = widget.region.normalizedRect;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 520;
        final image = _buildImage(context, imageExists, rect, wide);
        final content = _buildContent(context);
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Expanded(child: image),
                  const SizedBox(width: 10),
                  Expanded(child: content),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  image,
                  const SizedBox(height: 8),
                  content,
                ]),
        );
      },
    );
  }

  Widget _buildImage(BuildContext context, bool exists, Rect rect, bool wide) {
    if (!exists) {
      return Container(
        height: wide ? 150 : 120,
        alignment: Alignment.center,
        color: Theme.of(context).colorScheme.surface,
        child: const Text('原图附件缺失', style: TextStyle(fontSize: 12)),
      );
    }
    final spatialRisks = _spatialRisks;
    return GestureDetector(
      onTap: () => _showFullScreenImage(context),
      child: Stack(
        children: <Widget>[
          SizedBox(
            height: wide ? 150 : 120,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LayoutBuilder(builder: (context, constraints) {
                final scale = constraints.maxWidth / rect.width;
                return Stack(children: <Widget>[
                  Positioned(
                    left: -rect.left * scale,
                    top: -rect.top * scale,
                    width: scale,
                    child: CachedQuestionImage(widget.sourceImagePath, fit: BoxFit.fitWidth),
                  ),
                  Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _PreviewBorderPainter()))),
                ]);
              }),
            ),
          ),
          if (spatialRisks.isNotEmpty)
            Positioned(
              left: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(CupertinoIcons.exclamationmark_triangle, size: 11, color: Colors.white),
                    const SizedBox(width: 2),
                    Text('题框风险 ${spatialRisks.length}',
                        style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(CupertinoIcons.zoom_in, size: 12, color: Colors.white),
                  SizedBox(width: 2),
                  Text('点击放大', style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 全屏查看原图，支持双指缩放与拖动。
  void _showFullScreenImage(BuildContext context) {
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        pageBuilder: (_, __, ___) => _FullScreenImageViewer(imagePath: widget.sourceImagePath),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final spatialRisks = _spatialRisks;
    final stem = widget.stem;
    final formulas = widget.formulas;
    final tables = widget.tables;
    final expanded = _expanded;
    // 是否被用户手动编辑过：originalRecognizedText 存在且与当前 recognizedText
    // 不一致。三个可编辑字段（题干/公式/表格）共享这一标记，编辑任一字段都会
    // 触发整体 modified=true，让相应字段徽章显示"已校对"。
    final modified = widget.region.originalRecognizedText != null &&
        widget.region.recognizedText != widget.region.originalRecognizedText;
    // 当题干/公式/表格较长时显示"展开/收起"按钮；空内容时不显示。
    final hasLongContent = stem.length > 60 ||
        formulas.any((f) => f.length > 30) ||
        tables.any((t) => t.split('\n').where((l) => l.trim().isNotEmpty).length > 3);
    final stemMaxLines = expanded ? null : 5;
    final formulaMaxLines = expanded ? null : 2;
    final tableLineTake = expanded ? 9999 : 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('文字分层对照', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 4),
        _RecognitionTextLayer(
          label: 'OCR 原文',
          text: widget.region.originalRecognizedText ?? widget.region.recognizedText ?? '',
          color: const Color(0xFF64748B),
        ),
        _RecognitionTextLayer(
          label: '用户修正',
          text: widget.region.recognizedText ?? '',
          color: const Color(0xFF2563EB),
        ),
        _RecognitionTextLayer(
          label: 'AI 规范化',
          text: widget.region.aiNormalizedText ?? '尚未重新规范化',
          color: const Color(0xFF7C3AED),
        ),
        const SizedBox(height: 6),
        const Text('结构化识别内容', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 5),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            StatusPill(label: '题干', status: recognitionFieldStatus('题干', widget.region, stemOverride: stem, edited: modified)),
            StatusPill(label: '公式', status: recognitionFieldStatus('公式', widget.region, formulasOverride: formulas, edited: modified)),
            StatusPill(label: '表格', status: recognitionFieldStatus('表格', widget.region, tablesOverride: tables, edited: modified)),
            StatusPill(label: '选项', status: recognitionFieldStatus('选项', widget.region)),
            StatusPill(label: '图形', status: recognitionFieldStatus('图形', widget.region)),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          stem.isEmpty ? '暂无题干文字' : stem,
          maxLines: stemMaxLines,
          overflow: stemMaxLines == null ? TextOverflow.visible : TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, height: 1.35),
        ),
        if (formulas.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          ...formulas.map((item) => Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'ƒ $item',
              maxLines: formulaMaxLines,
              overflow: formulaMaxLines == null ? TextOverflow.visible : TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF475569), fontFamily: 'monospace'),
            ),
          )),
        ],
        if (tables.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          ...tables.expand((table) => table
              .split('\n')
              .where((line) => line.trim().isNotEmpty)
              .take(tableLineTake)
              .map((line) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      line,
                      maxLines: expanded ? null : 1,
                      overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF475569), fontFamily: 'monospace'),
                    ),
                  ))),
        ],
        if (hasLongContent)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                expanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
                size: 14,
              ),
              label: Text(expanded ? '收起' : '展开完整内容'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 24),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: const Color(0xFF2563EB),
                textStyle: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        if (spatialRisks.isNotEmpty) ...<Widget>[
          const SizedBox(height: 5),
          ...spatialRisks.map((risk) => Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('⚠ ', style: TextStyle(fontSize: 12, color: Color(0xFFDC2626))),
                Expanded(child: Text(risk, style: const TextStyle(fontSize: 12, color: Color(0xFF9A3412)))),
              ],
            ),
          )),
        ],
      ],
    );
  }
}

class _RecognitionTextLayer extends StatelessWidget {
  const _RecognitionTextLayer({
    required this.label,
    required this.text,
    required this.color,
  });

  final String label;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 68,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text.trim().isEmpty ? '暂无内容' : text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    ),
  );
}

class _PreviewBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF2563EB)..style = PaintingStyle.stroke..strokeWidth = 2;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 全屏原图查看器：双指缩放 + 拖动 + 双击放大，点击空白处关闭。
class _FullScreenImageViewer extends StatefulWidget {
  const _FullScreenImageViewer({required this.imagePath});

  final String imagePath;

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  final TransformationController _controller = TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).maybePop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Stack(
            children: <Widget>[
              GestureDetector(
                onDoubleTapDown: (details) => _doubleTapDetails = details,
                onDoubleTap: _handleDoubleTap,
                child: InteractiveViewer(
                  transformationController: _controller,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  minScale: 0.5,
                  maxScale: 5.0,
                  child: Center(
                    child: CachedQuestionImage(
                      widget.imagePath,
                      fit: BoxFit.contain,
                      errorMessage: '原图加载失败',
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 12,
                child: SafeArea(
                  child: IconButton.filledTonal(
                    icon: const Icon(CupertinoIcons.xmark),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleDoubleTap() {
    final position = _doubleTapDetails?.localPosition ?? Offset.zero;
    if (_controller.value != 1.0) {
      _controller.value = Matrix4.identity();
    } else {
      _controller.value = Matrix4.identity()
        ..translate(-position.dx * 2, -position.dy * 2)
        ..scale(3.0);
    }
  }
}

class _RegionQuality {
  static double evaluate(List<QuestionRegion> regions, int index) {
    final region = regions[index];
    if (region.source == QuestionRegionSource.manual) return 1;
    var score = region.confidence.clamp(0.0, 1.0).toDouble();
    for (var i = 0; i < regions.length; i++) {
      if (i == index) continue;
      if (_iou(region.normalizedRect, regions[i].normalizedRect) > .35) {
        score = (score * .65).clamp(0.0, 1.0).toDouble();
      }
    }
    if (region.normalizedRect.left < .01 || region.normalizedRect.top < .01 ||
        region.normalizedRect.right > .99 || region.normalizedRect.bottom > .99) {
      score = (score * .8).clamp(0.0, 1.0).toDouble();
    }
    return score;
  }

  static double _iou(Rect a, Rect b) {
    final overlap = a.intersect(b);
    if (overlap.isEmpty) return 0;
    final intersection = overlap.width * overlap.height;
    final union = a.width * a.height + b.width * b.height - intersection;
    return union <= 0 ? 0 : intersection / union;
  }
}



enum _QuestionListFilter { all, risk, edited, ignored }

class _RecognizedQuestionWorkbench extends StatefulWidget {
  const _RecognizedQuestionWorkbench({
    required this.regions,
    required this.defaultSubject,
    required this.onUpdate,
    required this.onIgnore,
    required this.selectedRegionId,
    required this.sourceImagePath,
    required this.retryingRegionId,
    required this.onRetryRecognition,
    required this.onSelect,
  });
  final List<QuestionRegion> regions;
  final Subject defaultSubject;
  final void Function(int index, QuestionRegion region) onUpdate;
  final ValueChanged<int> onIgnore;
  final String? selectedRegionId;
  final String sourceImagePath;
  final String? retryingRegionId;
  final void Function(int index, String? field) onRetryRecognition;
  final ValueChanged<QuestionRegion> onSelect;

  @override
  State<_RecognizedQuestionWorkbench> createState() =>
      _RecognizedQuestionWorkbenchState();
}

class _RecognizedQuestionWorkbenchState
    extends State<_RecognizedQuestionWorkbench> {
  static const _questionTypes = <String>[
    '未指定', '选择题', '填空题', '计算题', '证明题', '应用题',
  ];
  int _selectedIndex = 0;
  _QuestionListFilter _filter = _QuestionListFilter.all;
  bool _showAdvanced = false;
  final Set<String> _batchSelectedIds = <String>{};
  Map<int, QuestionRegion>? _lastBatchBefore;

  @override
  void didUpdateWidget(covariant _RecognizedQuestionWorkbench oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedIndex >= widget.regions.length) {
      _selectedIndex = widget.regions.isEmpty ? 0 : widget.regions.length - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.regions.isEmpty) return const SizedBox.shrink();
    final selectedById = widget.selectedRegionId == null
        ? -1
        : widget.regions.indexWhere((item) => item.id == widget.selectedRegionId);
    final index = (selectedById >= 0 ? selectedById : _selectedIndex)
        .clamp(0, widget.regions.length - 1);
    final region = widget.regions[index];
    final subject = region.subject ?? widget.defaultSubject;
    final type = region.questionType ?? '未指定';
    final risks = _riskMessages(index);
    final acceptedCount = widget.regions.where((item) => item.reviewStatus == QuestionRegionReviewStatus.accepted).length;
    final ignoredCount = widget.regions.length - acceptedCount;
    final riskCount = List<int>.generate(widget.regions.length, (item) => item).where((item) => _riskMessages(item).isNotEmpty).length;
    final editedCount = widget.regions.where((item) => item.originalRecognizedText != null && item.recognizedText != item.originalRecognizedText).length;
    const confirmationPolicy = RecognitionConfirmationPolicy();
    final autoConfirmable = List<int>.generate(widget.regions.length, (item) => item)
        .where((item) =>
            confirmationPolicy
                .evaluateRegion(widget.regions[item], _riskMessages(item))
                .decision ==
            RecognitionConfirmationDecision.autoPass)
        .toList(growable: false);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(children: <Widget>[
        ListTile(
          dense: true,
          leading: const Icon(CupertinoIcons.doc_text_search),
          title: Text('逐题确认工作台 · 第 ${index + 1}/${widget.regions.length} 题'),
          subtitle: Text('已采用 $acceptedCount 题${ignoredCount > 0 ? ' · 已忽略 $ignoredCount 题' : ''}；可切换题目完整校对', style: const TextStyle(fontSize: 11)),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Row(children: <Widget>[
            _filterChip('全部 ${widget.regions.length}', _QuestionListFilter.all),
            _filterChip('风险 $riskCount', _QuestionListFilter.risk, warning: riskCount > 0),
            _filterChip('已修改 $editedCount', _QuestionListFilter.edited),
            _filterChip('已忽略 $ignoredCount', _QuestionListFilter.ignored),
            const SizedBox(width: 4),
            FilledButton.tonalIcon(
              onPressed: autoConfirmable.isEmpty
                  ? null
                  : () => _autoConfirmHighConfidence(autoConfirmable),
              icon: const Icon(CupertinoIcons.checkmark_seal, size: 15),
              label: Text('确认高置信度 ${autoConfirmable.length} 题'),
            ),
          ]),
        ),
        if (_batchSelectedIds.isNotEmpty || _lastBatchBefore != null) _batchActionBar(),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            final compact = constraints.maxWidth < 600;
            final list = _buildQuestionList(context, index, horizontal: compact);
            final detail = _buildDetail(context, index, region, subject, type, risks, widget.sourceImagePath);
            if (compact) {
              return Column(children: <Widget>[
                SizedBox(height: 78, child: list),
                const Divider(height: 1),
                Expanded(child: detail),
              ]);
            }
            return Row(children: <Widget>[
              SizedBox(width: 132, child: list),
              const VerticalDivider(width: 1),
              Expanded(child: detail),
            ]);
          }),
        ),
      ]),
    );
  }

  List<String> _riskMessages(int index) =>
      detectQuestionRegionRisks(widget.regions[index], widget.regions, index: index);

  void _autoConfirmHighConfidence(List<int> indices) {
    setState(() {
      _lastBatchBefore = <int, QuestionRegion>{
        for (final index in indices) index: widget.regions[index],
      };
      for (final index in indices) {
        final region = widget.regions[index];
        widget.onUpdate(
          index,
          region.copyWith(
            reviewStatus: QuestionRegionReviewStatus.accepted,
            confirmedFields: RecognitionReviewField.all,
          ),
        );
      }
    });
  }

  void _toggleBatchSelection(String id) => setState(() {
    if (!_batchSelectedIds.add(id)) _batchSelectedIds.remove(id);
  });

  void _applyBatch(
    QuestionRegion Function(QuestionRegion region) transform, {
    bool eligibleOnly = false,
  }) {
    if (_batchSelectedIds.isEmpty) return;
    const policy = RecognitionConfirmationPolicy();
    final selectedIndices = <int>[
      for (var index = 0; index < widget.regions.length; index++)
        if (_batchSelectedIds.contains(widget.regions[index].id) &&
            (!eligibleOnly ||
                policy
                        .evaluateRegion(
                          widget.regions[index],
                          _riskMessages(index),
                        )
                        .decision ==
                    RecognitionConfirmationDecision.autoPass))
          index,
    ];
    if (selectedIndices.isEmpty) return;
    setState(() {
      _lastBatchBefore = <int, QuestionRegion>{
        for (final index in selectedIndices) index: widget.regions[index],
      };
      for (final entry in _lastBatchBefore!.entries) {
        widget.onUpdate(entry.key, transform(entry.value));
      }
      _batchSelectedIds.removeAll(
        selectedIndices.map((index) => widget.regions[index].id),
      );
    });
  }

  void _undoBatch() {
    final before = _lastBatchBefore;
    if (before == null) return;
    setState(() {
      for (final entry in before.entries) widget.onUpdate(entry.key, entry.value);
      _lastBatchBefore = null;
    });
  }

  Widget _batchActionBar() => Container(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 7),
      color: const Color(0xFFF0F9FF),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: <Widget>[
          Text('已选 ${_batchSelectedIds.length} 题', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: () => _applyBatch((item) => item.copyWith(analyzeWithAi: true, reviewStatus: QuestionRegionReviewStatus.accepted, confirmedFields: RecognitionReviewField.all), eligibleOnly: true), child: const Text('采用 + AI')),
          const SizedBox(width: 6),
          OutlinedButton(onPressed: () => _applyBatch((item) => item.copyWith(analyzeWithAi: false, reviewStatus: QuestionRegionReviewStatus.accepted, confirmedFields: RecognitionReviewField.all), eligibleOnly: true), child: const Text('仅 OCR')),
          const SizedBox(width: 6),
          OutlinedButton(onPressed: () => _applyBatch((item) => item.copyWith(reviewStatus: QuestionRegionReviewStatus.ignored)), child: const Text('批量忽略')),
          if (_lastBatchBefore != null) ...<Widget>[
            const SizedBox(width: 6),
            TextButton.icon(onPressed: _undoBatch, icon: const Icon(CupertinoIcons.arrow_uturn_left, size: 15), label: const Text('撤销本次')),
          ],
        ]),
      ),
    );

  Widget _filterChip(String label, _QuestionListFilter filter, {bool warning = false}) =>
      Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          selected: _filter == filter,
          selectedColor: warning ? const Color(0xFFFED7AA) : null,
          label: Text(label, style: const TextStyle(fontSize: 11)),
          onSelected: (_) => setState(() => _filter = filter),
        ),
      );

  bool _matchesFilter(int index) {
    final region = widget.regions[index];
    switch (_filter) {
      case _QuestionListFilter.all:
        return true;
      case _QuestionListFilter.risk:
        return _riskMessages(index).isNotEmpty;
      case _QuestionListFilter.edited:
        return region.originalRecognizedText != null &&
            region.recognizedText != region.originalRecognizedText;
      case _QuestionListFilter.ignored:
        return region.reviewStatus == QuestionRegionReviewStatus.ignored;
    }
  }

  Widget _buildQuestionList(BuildContext context, int selectedIndex,
      {required bool horizontal}) {
    final indices = List<int>.generate(widget.regions.length, (index) => index)
        .where(_matchesFilter).toList();
    return ListView.builder(
      scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
      padding: const EdgeInsets.all(6),
      itemCount: indices.length,
      itemBuilder: (context, visibleIndex) {
        final itemIndex = indices[visibleIndex];
        final item = widget.regions[itemIndex];
        final selected = itemIndex == selectedIndex;
        final ignored = item.reviewStatus == QuestionRegionReviewStatus.ignored;
        final risky = _riskMessages(itemIndex).isNotEmpty;
        final modified = item.originalRecognizedText != null && item.recognizedText != item.originalRecognizedText;
        return Padding(
          padding: horizontal
              ? const EdgeInsets.only(right: 6)
              : const EdgeInsets.only(bottom: 6),
          child: SizedBox(
            width: horizontal ? 112 : double.infinity,
            child: Material(
              color: ignored
                  ? Theme.of(context).colorScheme.surfaceContainerLow
                  : selected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  setState(() => _selectedIndex = itemIndex);
                  widget.onSelect(item);
                },
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(children: <Widget>[
                        GestureDetector(
                          onTap: () => _toggleBatchSelection(item.id),
                          child: Icon(_batchSelectedIds.contains(item.id)
                              ? CupertinoIcons.checkmark_square_fill
                              : CupertinoIcons.square,
                              size: 16,
                              color: _batchSelectedIds.contains(item.id)
                                  ? Theme.of(context).colorScheme.primary
                                  : const Color(0xFF64748B)),
                        ),
                        const SizedBox(width: 4),
                        Expanded(child: Text('第 ${item.detectedNumber ?? itemIndex + 1} 题', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                        Icon(ignored ? CupertinoIcons.minus_circle_fill : item.analyzeWithAi ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.doc_text, size: 14, color: ignored ? const Color(0xFF64748B) : item.analyzeWithAi ? const Color(0xFF16A34A) : const Color(0xFF2563EB)),
                      ]),
                      const SizedBox(height: 3),
                      Wrap(spacing: 2, runSpacing: 2, children: item.recognizedBlockTypes.where((block) => block != '文字').take(2).map(_MiniTypeTag.new).toList()),
                      const SizedBox(height: 3),
                      Text(ignored ? '⊘ 已忽略' : risky ? '⚠ 待处理风险' : modified ? '✎ 已修改' : item.analyzeWithAi ? '✓ 采用 + AI' : '✓ 采用 · 仅 OCR', style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  int? _nextRiskIndex(int current) {
    for (var step = 1; step <= widget.regions.length; step++) {
      final index = (current + step) % widget.regions.length;
      if (_riskMessages(index).isNotEmpty) return index;
    }
    return null;
  }

  Future<Size> _sourceImageSize(String imagePath) async {
    final image = await decodeImageFromList(await File(imagePath).readAsBytes());
    return Size(image.width.toDouble(), image.height.toDouble());
  }

  Future<void> _showCropPreview(BuildContext context, QuestionRegion region, String imagePath) async {
    final sourceSize = await _sourceImageSize(imagePath);
    if (!context.mounted) return;
    final cropAspect = sourceSize.width * region.normalizedRect.width /
        (sourceSize.height * region.normalizedRect.height);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('最终裁切预览'),
        content: AspectRatio(
          aspectRatio: cropAspect,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LayoutBuilder(builder: (context, constraints) {
              final scale = constraints.maxWidth / region.normalizedRect.width;
              return Stack(children: <Widget>[
                Positioned(
                  left: -region.normalizedRect.left * scale,
                  top: -region.normalizedRect.top * scale,
                  width: scale,
                  child: CachedQuestionImage(imagePath, fit: BoxFit.fitWidth),
                ),
              ]);
            }),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('返回调整题框')),
        ],
      ),
    );
  }

  String _stemFor(QuestionRegion region) {
    if (region.questionStem != null) return region.questionStem!;
    final formula = RegExp(r'\$[^$]+\$');
    // 题干不应包含公式行、表格行、选项行；选项行单独由 _optionsFor 维护。
    final optionLine = RegExp(r'^\s*[A-H][.．、]\s*\S');
    return (region.recognizedText ?? '').split('\n')
        .where((line) => !formula.hasMatch(line) &&
            !line.trimLeft().startsWith('|') &&
            !optionLine.hasMatch(line))
        .join('\n').trim();
  }

  List<String> _formulasFor(QuestionRegion region) {
    if (region.formulas.isNotEmpty) return region.formulas;
    return RegExp(r'\$[^$]+\$').allMatches(region.recognizedText ?? '')
        .map((match) => match.group(0)!).toList();
  }

  List<String> _tablesFor(QuestionRegion region) {
    if (region.tables.isNotEmpty) return region.tables;
    final lines = (region.recognizedText ?? '').split('\n')
        .where((line) => line.trimLeft().startsWith('|')).toList();
    return lines.isEmpty ? const <String>[] : <String>[lines.join('\n')];
  }

  /// 取选项列表：region.options 非空时直接返回（用户已编辑过）；
  /// 否则首次进入从 recognizedText 自动解析 A./B./C./D. 行。
  /// 用户主动清空（options 已被设为空 list 且 originalRecognizedText 标记
  /// 已编辑）时返回空，避免把原文里的选项行"复活"。
  List<String> _optionsFor(QuestionRegion region) {
    if (region.options.isNotEmpty) return region.options;
    if (region.originalRecognizedText != null) return const <String>[];
    return parseOptionLines(region.recognizedText);
  }

  void _applyBlocks(int index, QuestionRegion region, List<DocumentBlock> blocks) {
    final text = blocks.where((block) => block.type == DocumentBlockType.text)
        .map((block) => block.content).where((value) => value.trim().isNotEmpty).join('\n\n');
    final formulas = blocks.where((block) => block.type == DocumentBlockType.formula)
        .map((block) => block.content).where((value) => value.trim().isNotEmpty).toList();
    final tables = blocks.where((block) => block.type == DocumentBlockType.table)
        .map((block) => block.content).where((value) => value.trim().isNotEmpty).toList();
    final options = _optionsFor(region);
    final combined = <String>[
      ...blocks.where((block) => block.content.trim().isNotEmpty).map((block) => block.content),
      ...options,
    ].join('\n\n');
    widget.onUpdate(index, region.copyWith(
      questionStem: text,
      formulas: formulas,
      tables: tables,
      options: options,
      documentBlocks: blocks,
      recognizedText: combined,
      contentFormatHint: formulas.isEmpty ? 'plain' : 'latexMixed',
    ));
  }

  void _openBlockEditor(BuildContext context, int index, QuestionRegion region) {
    final blocks = region.documentBlocks.isEmpty
        ? _orderedBlocks(region, _stemFor(region), _formulasFor(region), _tablesFor(region))
        : region.documentBlocks;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (dialogContext) => FractionallySizedBox(
        heightFactor: .88,
        child: _DocumentBlockEditor(
          initialBlocks: blocks,
          onApply: (next) {
            _applyBlocks(index, region, next);
            Navigator.pop(dialogContext);
          },
        ),
      ),
    );
  }

  List<DocumentBlock> _orderedBlocks(QuestionRegion region, String stem,
      List<String> formulas, List<String> tables) {
    if (region.documentBlocks.isEmpty) return <DocumentBlock>[
      if (stem.trim().isNotEmpty) DocumentBlock(type: DocumentBlockType.text, content: stem),
      ...formulas.map((item) => DocumentBlock(type: DocumentBlockType.formula, content: item)),
      ...tables.map((item) => DocumentBlock(type: DocumentBlockType.table, content: item)),
    ];
    final remaining = <DocumentBlockType, List<String>>{
      DocumentBlockType.text: <String>[stem],
      DocumentBlockType.formula: List<String>.from(formulas),
      DocumentBlockType.table: List<String>.from(tables),
    };
    final next = <DocumentBlock>[];
    for (final block in region.documentBlocks) {
      final values = remaining[block.type];
      if (values == null) {
        next.add(block);
      } else if (values.isNotEmpty) {
        next.add(block.copyWith(content: values.removeAt(0)));
      }
    }
    for (final type in remaining.keys) {
      next.addAll(remaining[type]!.where((item) => item.trim().isNotEmpty)
          .map((item) => DocumentBlock(type: type, content: item)));
    }
    return next;
  }

  void _updateStructured(int index, QuestionRegion region, {
    String? stem, List<String>? formulas, List<String>? tables,
    List<String>? options,
  }) {
    final nextStem = stem ?? _stemFor(region);
    final nextFormulas = formulas ?? _formulasFor(region);
    final nextTables = tables ?? _tablesFor(region);
    final nextOptions = options ?? _optionsFor(region);
    final blocks = _orderedBlocks(region, nextStem, nextFormulas, nextTables);
    // combined 必须包含选项行，让 hasOptionLine 在重建后仍能识别，
    // 同时让"恢复识别原文"对照保持完整。
    final combined = <String>[
      ...blocks.where((block) => block.content.trim().isNotEmpty).map((block) => block.content),
      ...nextOptions,
    ].join('\n\n');
    widget.onUpdate(index, region.copyWith(
      questionStem: nextStem,
      formulas: nextFormulas,
      tables: nextTables,
      options: nextOptions,
      documentBlocks: blocks,
      recognizedText: combined,
      contentFormatHint: nextFormulas.isEmpty ? 'plain' : 'latexMixed',
    ));
  }

  /// 弹出选项编辑对话框。每行一个选项，自动补 A./B./C./D. 前缀；
  /// 用户保存空文本时清空 options（不再回退到自动解析）。
  Future<void> _openOptionEditor(
      BuildContext context, int index, QuestionRegion region) async {
    final initial = _optionsFor(region).join('\n');
    final result = await showSingleTextFieldDialog(
      context: context,
      title: '编辑选项（每行一个）',
      initialText: initial,
      labelText: '选项列表',
      hintText: 'A. 选项一\nB. 选项二\nC. 选项三\nD. 选项四',
      minLines: 4,
      maxLines: 10,
      confirmText: '保存',
    );
    if (result == null) return;
    final nextOptions = normalizeOptions(result);
    _updateStructured(index, region, options: nextOptions);
  }

  /// 弹出图形备注对话框。把人工核对结论存到 region.diagramNote；
  /// 空文本视为清空（存空串，避免 copyWith 把 null 当作"保留原值"）。
  Future<void> _openDiagramNoteEditor(
      BuildContext context, int index, QuestionRegion region) async {
    final result = await showSingleTextFieldDialog(
      context: context,
      title: '图形备注（人工核对）',
      initialText: region.diagramNote ?? '',
      labelText: '图形内容描述',
      hintText: '例如：直角三角形 ABC，∠C=90°，AB=5，AC=3',
      minLines: 2,
      maxLines: 6,
      confirmText: '保存',
    );
    if (result == null) return;
    widget.onUpdate(index, region.copyWith(diagramNote: result));
  }

  Widget _buildDetail(BuildContext context, int index, QuestionRegion region,
      Subject subject, String type, List<String> risks, String sourceImagePath) {
    final stem = _stemFor(region);
    final formulas = _formulasFor(region);
    final tables = _tablesFor(region);
    final original = region.originalRecognizedText ?? region.recognizedText ?? '';
    final modified = region.originalRecognizedText != null && region.recognizedText != original;
    const confirmationPolicy = RecognitionConfirmationPolicy();
    final requiredFields = confirmationPolicy
        .evaluateRegion(
          region,
          risks,
          imageAvailable: File(sourceImagePath).existsSync(),
        )
        .requiredFields;
    return ListView(
      key: ValueKey(region.id),
      padding: const EdgeInsets.all(10),
      children: <Widget>[
        RecognitionEvidencePreview(
          sourceImagePath: sourceImagePath,
          region: region,
          stem: stem,
          formulas: formulas,
          tables: tables,
          risks: risks,
        ),
        if (requiredFields.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('低置信度字段需逐项确认', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  children: requiredFields.map((field) {
                    final confirmed = region.confirmedFields.contains(field);
                    return FilterChip(
                      selected: confirmed,
                      avatar: Icon(confirmed ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.exclamationmark_triangle, size: 14),
                      label: Text(_recognitionFieldLabel(field)),
                      onSelected: (value) {
                        final next = Set<String>.from(region.confirmedFields);
                        value ? next.add(field) : next.remove(field);
                        widget.onUpdate(index, region.copyWith(confirmedFields: next));
                      },
                    );
                  }).toList(growable: false),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: widget.retryingRegionId == region.id
                          ? null
                          : () => widget.onRetryRecognition(index, null),
                      icon: const Icon(CupertinoIcons.arrow_clockwise, size: 14),
                      label: Text(widget.retryingRegionId == region.id ? '识别中…' : '重新识别整题'),
                    ),
                    ...requiredFields.where(_isRecognitionRetryField).map((field) => TextButton(
                      onPressed: widget.retryingRegionId == region.id
                          ? null
                          : () => widget.onRetryRecognition(index, field),
                      child: Text('重识别${_recognitionFieldLabel(field)}'),
                    )),
                  ],
                ),
              ],
            ),
          ),
        if (region.parentRegionId != null ||
            region.assemblyRiskCodes.contains(QuestionAssemblyRiskCode.parentQuestionUncertain))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DropdownButtonFormField<String>(
              value: region.parentRegionId ?? '__top__',
              decoration: const InputDecoration(
                isDense: true,
                labelText: '所属大题',
                helperText: '小题可归入前后大题；选择“顶层题目”可解除父子关系。',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String>>[
                const DropdownMenuItem(value: '__top__', child: Text('顶层题目')),
                ...widget.regions.where((candidate) => candidate.id != region.id &&
                    candidate.parentRegionId == null).map((candidate) => DropdownMenuItem(
                  value: candidate.id,
                  child: Text(candidate.detectedNumber == null
                      ? '题目 ${candidate.id}'
                      : '第 ${candidate.detectedNumber} 题'),
                )),
              ],
              onChanged: (value) {
                final risks = Set<QuestionAssemblyRiskCode>.from(region.assemblyRiskCodes)
                  ..remove(QuestionAssemblyRiskCode.parentQuestionUncertain);
                final confirmed = Set<String>.from(region.confirmedFields)
                  ..add(RecognitionReviewField.questionAssembly);
                widget.onUpdate(index, region.copyWith(
                  parentRegionId: value == '__top__' ? null : value,
                  assemblyRiskCodes: risks,
                  confirmedFields: confirmed,
                ));
              },
            ),
          ),
        Row(children: <Widget>[
          Expanded(child: Text('第 ${region.detectedNumber ?? index + 1} 题详情', style: const TextStyle(fontWeight: FontWeight.w700))),
          ...region.recognizedBlockTypes.where((block) => block != '文字').map(_MiniTypeTag.new),
          TextButton.icon(
            onPressed: () => widget.onIgnore(index),
            icon: Icon(region.reviewStatus == QuestionRegionReviewStatus.ignored
                ? CupertinoIcons.arrow_counterclockwise
                : CupertinoIcons.minus_circle, size: 16),
            label: Text(region.reviewStatus == QuestionRegionReviewStatus.ignored ? '恢复采用' : '忽略'),
          ),
        ]),
        Row(children: <Widget>[
          TextButton.icon(
            onPressed: index == 0 ? null : () {
              setState(() => _selectedIndex = index - 1);
              widget.onSelect(widget.regions[index - 1]);
            },
            icon: const Icon(CupertinoIcons.chevron_left, size: 15),
            label: const Text('上一题'),
          ),
          Text('${index + 1} / ${widget.regions.length}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          TextButton.icon(
            onPressed: index >= widget.regions.length - 1 ? null : () {
              setState(() => _selectedIndex = index + 1);
              widget.onSelect(widget.regions[index + 1]);
            },
            icon: const Icon(CupertinoIcons.chevron_right, size: 15),
            label: const Text('下一题'),
          ),
        ]),
        if (risks.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                final next = _nextRiskIndex(index);
                if (next == null || next == index) return;
                setState(() => _selectedIndex = next);
                widget.onSelect(widget.regions[next]);
              },
              icon: const Icon(CupertinoIcons.exclamationmark_triangle, size: 15),
              label: const Text('下一道风险题'),
            ),
          ),
        if (region.reviewStatus == QuestionRegionReviewStatus.ignored)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('⊘ 此题已忽略，不会被裁切、保存或交给 AI；可点击“恢复采用”撤销。', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          ),
        if (risks.isNotEmpty)
          _RiskActionCard(
            risks: risks,
            onEditText: () => setState(() => _showAdvanced = false),
            onPreviewCrop: () => _showCropPreview(context, region, sourceImagePath),
            onOpenAdvanced: () => setState(() => _showAdvanced = true),
            onEditOptions: () => _openOptionEditor(context, index, region),
          ),
        Text('题框区域：x ${region.normalizedRect.left.toStringAsFixed(2)} · y ${region.normalizedRect.top.toStringAsFixed(2)} · ${region.normalizedRect.width.toStringAsFixed(2)} × ${region.normalizedRect.height.toStringAsFixed(2)}。可在下方试卷图拖动蓝框调整。', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _showCropPreview(context, region, sourceImagePath),
            icon: const Icon(CupertinoIcons.crop, size: 15),
            label: const Text('查看最终裁切预览'),
          ),
        ),
        const SizedBox(height: 8),
        if (modified)
          Row(children: <Widget>[
            const Icon(CupertinoIcons.pencil_circle_fill, size: 15, color: Color(0xFF2563EB)),
            const SizedBox(width: 4),
            const Text('已修改识别结果', style: TextStyle(fontSize: 12, color: Color(0xFF2563EB))),
            const Spacer(),
            TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('识别原文对照'),
                  content: SingleChildScrollView(
                    child: SelectableText(original.isEmpty ? '没有可用的识别原文。' : original),
                  ),
                  actions: <Widget>[TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('关闭'))],
                ),
              ),
              child: const Text('查看原文'),
            ),
            TextButton(
              onPressed: () => widget.onUpdate(index, region.copyWith(
                questionStem: original,
                formulas: const <String>[],
                tables: const <String>[],
                recognizedText: original,
              )),
              child: const Text('恢复识别原文'),
            ),
          ]),
        TextFormField(
          key: ValueKey('${region.id}-quick-stem-$stem'),
          initialValue: stem,
          minLines: 2,
          maxLines: 4,
          onChanged: (value) => _updateStructured(index, region, stem: value),
          decoration: const InputDecoration(isDense: true, labelText: '题干', helperText: '先校对题干；公式、表格和内容块可在高级校对中编辑。', alignLabelWithHint: true, border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: ValueKey('${region.id}-student-answer-${region.studentAnswer ?? ''}'),
          initialValue: region.studentAnswer ?? '',
          minLines: 1,
          maxLines: 4,
          onChanged: (value) => widget.onUpdate(
            index,
            region.copyWith(studentAnswer: value),
          ),
          decoration: const InputDecoration(
            isDense: true,
            labelText: '学生答案',
            helperText: '与题干、选项独立保存；后续错因分析只使用这里确认的作答。',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 6),
        ExpansionTile(
          initiallyExpanded: _showAdvanced,
          onExpansionChanged: (value) => setState(() => _showAdvanced = value),
          tilePadding: EdgeInsets.zero,
          title: const Text('高级校对', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          subtitle: Text('公式、表格、原文对照与内容块顺序${region.documentBlocks.isEmpty ? '' : ' · ${region.documentBlocks.length} 个内容块'}', style: const TextStyle(fontSize: 11)),
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _openBlockEditor(context, index, region),
                icon: const Icon(CupertinoIcons.list_bullet_indent, size: 16),
                label: const Text('编辑内容块顺序'),
              ),
            ),
        const SizedBox(height: 6),
        TextFormField(
          key: ValueKey('${region.id}-advanced-stem-$stem'),
          initialValue: stem,
          minLines: 3,
          maxLines: 6,
          onChanged: (value) => _updateStructured(index, region, stem: value),
          decoration: const InputDecoration(
            isDense: true,
            labelText: '题干',
            helperText: '正文可独立校对；公式和表格在下方分别维护。',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        if (region.recognizedBlockTypes.contains('公式') || formulas.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey('${region.id}-formula-${formulas.join()}'),
            initialValue: formulas.join('\n\n'),
            minLines: 2,
            maxLines: 5,
            onChanged: (value) => _updateStructured(index, region,
              formulas: value.split('\n\n').where((item) => item.trim().isNotEmpty).toList()),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'LaTex 公式（每段公式以空行分隔）',
              helperText: r'请保留 $...$ 或 \(...\) 等 LaTex 标记。',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
        if (region.recognizedBlockTypes.contains('表格') || tables.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey('${region.id}-table-${tables.join()}'),
            initialValue: tables.join('\n\n'),
            minLines: 3,
            maxLines: 7,
            onChanged: (value) => _updateStructured(index, region,
              tables: value.trim().isEmpty ? const <String>[] : <String>[value]),
            decoration: const InputDecoration(
              isDense: true,
              labelText: '表格 Markdown',
              helperText: '可直接编辑 | 列 | 的 Markdown 表格内容。',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (tables.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            _MarkdownTablePreview(tables.first),
          ],
        ],
        // 选项独立编辑入口：选择题或识别到选项行时显示。点击弹出对话框，
        // 每行一个选项，自动补 A./B./C./D. 前缀；保存后写入 region.options
        // 并合并回 recognizedText，让 hasOptionLine 仍能识别。
        if (type == '选择题' ||
            region.recognizedBlockTypes.contains('选项') ||
            _optionsFor(region).isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openOptionEditor(context, index, region),
              icon: const Icon(CupertinoIcons.list_bullet_indent, size: 16),
              label: Text(_optionsFor(region).isEmpty
                  ? '编辑选项（暂无选项行）'
                  : '编辑选项（${_optionsFor(region).length} 项）'),
            ),
          ),
          if (_optionsFor(region).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Text(
                _optionsFor(region).join('\n'),
                style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
              ),
            ),
        ],
        // 图形备注入口：识别到图形块或已有备注时显示。备注存到
        // region.diagramNote，作为人工核对结论；空备注视为清空。
        if (region.recognizedBlockTypes.any((t) =>
                t == '图形' || t == 'diagram' || t.toLowerCase().contains('diagram')) ||
            (region.diagramNote ?? '').trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openDiagramNoteEditor(context, index, region),
              icon: const Icon(CupertinoIcons.pencil_circle, size: 16),
              label: Text((region.diagramNote ?? '').trim().isEmpty
                  ? '添加图形备注'
                  : '编辑图形备注'),
            ),
          ),
          if ((region.diagramNote ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Text(
                region.diagramNote!,
                style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
              ),
            ),
        ],
          ],
        ),
        const SizedBox(height: 8),
        Row(children: <Widget>[
          Expanded(child: DropdownButtonFormField<Subject>(
            value: subject,
            isDense: true,
            decoration: const InputDecoration(labelText: '学科', border: OutlineInputBorder()),
            items: Subject.values.map((item) => DropdownMenuItem(value: item, child: Text(item.label))).toList(),
            onChanged: (value) { if (value != null) widget.onUpdate(index, region.copyWith(subject: value)); },
          )),
          const SizedBox(width: 8),
          Expanded(child: DropdownButtonFormField<String>(
            value: _questionTypes.contains(type) ? type : '未指定',
            isDense: true,
            decoration: const InputDecoration(labelText: '题目类型', border: OutlineInputBorder()),
            items: _questionTypes.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
            onChanged: (value) => widget.onUpdate(index, region.copyWith(questionType: value == '未指定' ? '' : value)),
          )),
        ]),
        const SizedBox(height: 6),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: region.analyzeWithAi,
          onChanged: (value) => widget.onUpdate(index, region.copyWith(analyzeWithAi: value)),
          title: Text(region.analyzeWithAi ? '✓ 采用，并交给普通 AI 深度分析' : '✓ 采用，仅保存 OCR / 文档结果', style: const TextStyle(fontSize: 12)),
          subtitle: Text(region.analyzeWithAi ? '生成讲解、错因、知识点与练习' : '不调用普通 AI，可稍后在错题本中分析', style: const TextStyle(fontSize: 11)),
        ),
      ],
    );
  }
}

String _recognitionFieldLabel(String field) => switch (field) {
  RecognitionReviewField.stem => '题干',
  RecognitionReviewField.options => '选项',
  RecognitionReviewField.studentAnswer => '学生答案',
  RecognitionReviewField.formulas => '公式',
  RecognitionReviewField.tables => '表格',
  RecognitionReviewField.diagram => '图形',
  RecognitionReviewField.questionAssembly => '题目顺序与父子关系',
  RecognitionReviewField.authorRoles => '内容作者角色',
  RecognitionReviewField.specialistBlocks => '专用识别块',
  _ => field,
};

bool _isRecognitionRetryField(String field) => const <String>{
  RecognitionReviewField.stem,
  RecognitionReviewField.options,
  RecognitionReviewField.studentAnswer,
  RecognitionReviewField.formulas,
  RecognitionReviewField.tables,
  RecognitionReviewField.diagram,
}.contains(field);

class _RiskActionCard extends StatelessWidget {
  const _RiskActionCard({
    required this.risks,
    required this.onEditText,
    required this.onPreviewCrop,
    required this.onOpenAdvanced,
    required this.onEditOptions,
  });
  final List<String> risks;
  final VoidCallback onEditText;
  final VoidCallback onPreviewCrop;
  final VoidCallback onOpenAdvanced;
  final VoidCallback onEditOptions;
  @override
  Widget build(BuildContext context) {
    final needsText = risks.any((item) => item.contains('文字') || item.contains('可信度'));
    final needsCrop = risks.any((item) => item.contains('边缘') || item.contains('重叠'));
    final needsStructure = risks.any((item) => item.contains('公式') || item.contains('表格'));
    // 选项缺失风险走独立的选项编辑入口（Batch 4），不再回退到题干校对。
    final needsOption = risks.any((item) => item.contains('选项'));
    return Container(
      margin: const EdgeInsets.only(bottom: 7), padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('⚠ ${risks.join('；')}', style: const TextStyle(fontSize: 12, color: Color(0xFF9A3412))),
        const SizedBox(height: 5),
        Wrap(spacing: 6, runSpacing: 4, children: <Widget>[
          if (needsText) TextButton.icon(onPressed: onEditText, icon: const Icon(CupertinoIcons.pencil, size: 14), label: const Text('校对题干')),
          if (needsCrop) TextButton.icon(onPressed: onPreviewCrop, icon: const Icon(CupertinoIcons.crop, size: 14), label: const Text('查看裁切')),
          if (needsStructure) TextButton.icon(onPressed: onOpenAdvanced, icon: const Icon(CupertinoIcons.list_bullet, size: 14), label: const Text('校对格式')),
          if (needsOption) TextButton.icon(onPressed: onEditOptions, icon: const Icon(CupertinoIcons.list_bullet_indent, size: 14), label: const Text('补选项')),
        ]),
      ]),
    );
  }
}

class _DocumentBlockEditor extends StatefulWidget {
  const _DocumentBlockEditor({required this.initialBlocks, required this.onApply});
  final List<DocumentBlock> initialBlocks;
  final ValueChanged<List<DocumentBlock>> onApply;

  @override
  State<_DocumentBlockEditor> createState() => _DocumentBlockEditorState();
}

class _DocumentBlockEditorState extends State<_DocumentBlockEditor> {
  late List<DocumentBlock> _blocks;

  @override
  void initState() {
    super.initState();
    _blocks = List<DocumentBlock>.from(widget.initialBlocks);
  }

  String _label(DocumentBlockType type) => switch (type) {
    DocumentBlockType.text => '文字块',
    DocumentBlockType.formula => '公式块',
    DocumentBlockType.table => '表格块',
    DocumentBlockType.handwriting => '手写块',
    DocumentBlockType.diagram => '图形块',
    DocumentBlockType.image => '图片块',
    DocumentBlockType.answerMark => '批改标记',
    DocumentBlockType.unknown => '未分类块',
  };

  String _recognitionLabel(DocumentBlock block) => switch (block.recognitionStatus) {
    DocumentRecognitionStatus.recognized => '已由专用识别器解析',
    DocumentRecognitionStatus.needsSpecialist => '需要专用识别或人工校对',
    DocumentRecognitionStatus.sourcePreserved => '已保留原图区域，未强制转成文字',
    DocumentRecognitionStatus.failed => '识别失败，可从原图区域重试',
  };

  String _roleLabel(DocumentAuthorRole role) => switch (role) {
    DocumentAuthorRole.printedPrompt => '印刷题干',
    DocumentAuthorRole.studentAnswer => '学生作答',
    DocumentAuthorRole.teacherMark => '教师批改',
    DocumentAuthorRole.unknown => '角色待确认',
  };

  void _confirmRole(int index, DocumentAuthorRole role) => setState(() {
    _blocks[index] = const QuestionAssemblyService()
        .confirmAuthorRole(_blocks[index], role);
  });

  void _requestRetry(int index) => setState(() {
    _blocks[index] = const QuestionAssemblyService()
        .requestSpecialistRetry(_blocks[index]);
  });

  void _move(int index, int offset) => setState(() {
    final target = index + offset;
    if (target < 0 || target >= _blocks.length) return;
    final block = _blocks.removeAt(index);
    _blocks.insert(target, block);
  });

  void _add(DocumentBlockType type) => setState(() => _blocks.add(DocumentBlock(
    type: type,
    content: type == DocumentBlockType.formula ? r'$ $' : type == DocumentBlockType.table ? '|列1|列2|\n|---|---|\n|||': '',
  )));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('按原始顺序编辑内容块'),
      actions: <Widget>[TextButton(onPressed: () => widget.onApply(_blocks), child: const Text('完成'))],
    ),
    body: Column(children: <Widget>[
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text('拖动顺序可通过上下按钮调整；删除空块或 OCR 误识别块。完成后会按这里的顺序重组题目。', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
      ),
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _blocks.length,
        itemBuilder: (context, index) {
          final block = _blocks[index];
          return Card(child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                _MiniTypeTag(_label(block.type)),
                const Spacer(),
                IconButton(onPressed: index == 0 ? null : () => _move(index, -1), icon: const Icon(CupertinoIcons.arrow_up, size: 18)),
                IconButton(onPressed: index == _blocks.length - 1 ? null : () => _move(index, 1), icon: const Icon(CupertinoIcons.arrow_down, size: 18)),
                IconButton(onPressed: () => setState(() => _blocks.removeAt(index)), icon: const Icon(CupertinoIcons.trash, size: 18)),
              ]),
              if (block.recognitionEngine != DocumentRecognitionEngine.unknown) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  _recognitionLabel(block),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 6),
              ],
              Row(children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<DocumentAuthorRole>(
                    value: block.authorRole,
                    isDense: true,
                    decoration: const InputDecoration(labelText: '内容角色'),
                    items: DocumentAuthorRole.values.map((role) => DropdownMenuItem(
                      value: role,
                      child: Text(_roleLabel(role), style: const TextStyle(fontSize: 12)),
                    )).toList(growable: false),
                    onChanged: (role) {
                      if (role != null) _confirmRole(index, role);
                    },
                  ),
                ),
                if (block.sourceCropRef != null &&
                    (block.recognitionStatus == DocumentRecognitionStatus.failed ||
                     block.recognitionStatus == DocumentRecognitionStatus.sourcePreserved)) ...<Widget>[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _requestRetry(index),
                    icon: const Icon(CupertinoIcons.refresh, size: 15),
                    label: const Text('重试此块'),
                  ),
                ],
              ]),
              const SizedBox(height: 6),
              TextFormField(
                key: ValueKey('${block.type}-${index}-${block.content}'),
                initialValue: block.content,
                minLines: block.type == DocumentBlockType.table ? 3 : 2,
                maxLines: 8,
                onChanged: (value) =>
                    _blocks[index] = _blocks[index].copyWith(content: value),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: _label(block.type),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (block.type == DocumentBlockType.table && block.content.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 6), _MarkdownTablePreview(block.content),
              ],
            ]),
          ));
        },
      )),
      SafeArea(child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
          OutlinedButton.icon(onPressed: () => _add(DocumentBlockType.text), icon: const Icon(CupertinoIcons.textformat, size: 16), label: const Text('添加文字')),
          OutlinedButton.icon(onPressed: () => _add(DocumentBlockType.formula), icon: const Icon(CupertinoIcons.function, size: 16), label: const Text('添加公式')),
          OutlinedButton.icon(onPressed: () => _add(DocumentBlockType.table), icon: const Icon(CupertinoIcons.table, size: 16), label: const Text('添加表格')),
        ]),
      )),
    ]),
  );
}

class _MarkdownTablePreview extends StatelessWidget {
  const _MarkdownTablePreview(this.markdown);
  final String markdown;

  List<List<String>> get _rows => markdown.split('\n')
      .where((line) => line.trim().startsWith('|'))
      .map((line) => line.trim().replaceFirst(RegExp(r'^\|'), '')
          .replaceFirst(RegExp(r'\|$'), '').split('|')
          .map((cell) => cell.trim()).toList())
      .where((cells) => !cells.every((cell) => RegExp(r'^:?-{2,}:?$').hasMatch(cell)))
      .toList();

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows.isEmpty) return const SizedBox.shrink();
    final header = rows.first;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 28,
          dataRowMinHeight: 28,
          dataRowMaxHeight: 40,
          columns: header.map((cell) => DataColumn(label: Text(cell, style: const TextStyle(fontSize: 11)))).toList(),
          rows: rows.skip(1).map((row) => DataRow(cells: List<DataCell>.generate(
            header.length,
            (index) => DataCell(Text(index < row.length ? row[index] : '', style: const TextStyle(fontSize: 11))),
          ))).toList(),
        ),
      ),
    );
  }
}

class _MiniTypeTag extends StatelessWidget {
  const _MiniTypeTag(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(color: const Color(0xFFF5F3FF), borderRadius: BorderRadius.circular(4)),
    child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6D28D9))),
  );
}

/// 检测单个题框的风险提示。
///
/// 提取为顶层公开函数便于单元测试（题框比例异常、面积过大/过小、
/// 贴边、重叠、空题干、低可信度、含公式表格）。[allRegions] 用于
/// 重叠检测，[index] 为当前 region 在 allRegions 中的索引。
List<String> detectQuestionRegionRisks(
  QuestionRegion region,
  List<QuestionRegion> allRegions, {
  int index = 0,
}) {
  final risks = <String>[];
  if ((region.recognizedText ?? '').trim().isEmpty) {
    risks.add('未识别到题干文字');
  }
  if (region.source == QuestionRegionSource.layoutModel && region.confidence < .60) {
    risks.add('识别可信度较低，建议校对');
  }
  if (region.normalizedRect.left < .01 || region.normalizedRect.top < .01 ||
      region.normalizedRect.right > .99 || region.normalizedRect.bottom > .99) {
    risks.add('题框贴近页面边缘，可能被截断');
  }
  // 题框宽高比异常：正常题目宽高比一般在 0.2~8 之间，超出范围可能是误识别整页/单行。
  final rect = region.normalizedRect;
  if (rect.width > 0 && rect.height > 0) {
    final aspect = rect.width / rect.height;
    if (aspect > 8 || aspect < 0.125) {
      risks.add('题框宽高比异常（${aspect.toStringAsFixed(1)}:1），可能误框整页或单字');
    }
    final area = rect.width * rect.height;
    if (area > 0.85) {
      risks.add('题框占整页面积过大，可能包含多题');
    } else if (area < 0.005) {
      risks.add('题框面积过小，可能只截到单字或符号');
    }
  }
  for (var i = 0; i < allRegions.length; i++) {
    if (i == index) continue;
    final overlap = region.normalizedRect.intersect(allRegions[i].normalizedRect);
    final union = region.normalizedRect.width * region.normalizedRect.height +
        allRegions[i].normalizedRect.width * allRegions[i].normalizedRect.height -
        overlap.width * overlap.height;
    if (!overlap.isEmpty && union > 0 && overlap.width * overlap.height / union > .35) {
      risks.add('与第 ${allRegions[i].detectedNumber ?? i + 1} 题题框重叠');
      break;
    }
  }
  if (region.recognizedBlockTypes.any((item) => item == '公式' || item == '表格')) {
    risks.add('含公式或表格，建议核对格式');
  }
  if (region.documentBlocks.any((block) =>
      block.recognitionStatus == DocumentRecognitionStatus.needsSpecialist ||
      block.recognitionStatus == DocumentRecognitionStatus.failed)) {
    risks.add('手写或专用内容尚未完成识别，请查看原图并校对文字');
  }
  if (region.assemblyRiskCodes.contains(QuestionAssemblyRiskCode.readingOrderUncertain)) {
    risks.add('跨栏内容阅读顺序不确定，请核对内容块顺序');
  }
  if (region.assemblyRiskCodes.contains(QuestionAssemblyRiskCode.parentQuestionUncertain)) {
    risks.add('未能确认所属父题，请核对大题与小题关系');
  }
  if (region.assemblyRiskCodes.contains(QuestionAssemblyRiskCode.authorRoleUncertain)) {
    risks.add('题干、学生作答或教师批改角色不确定，请逐块确认');
  }
  // 公式格式异常：含公式块但公式列表为空，或公式缺少 $...$ / \(...\) / \[...\] 等 LaTex 标记。
  // 当公式格式异常时不重复加"含公式"提示，避免冗余。
  final hasFormulaBlock = region.recognizedBlockTypes.any((item) => item == '公式') ||
      region.formulas.isNotEmpty;
  if (hasFormulaBlock) {
    final formulaIssue = region.formulas.isEmpty ||
        region.formulas.any((f) =>
            !f.contains('\$') && !f.contains(r'\(') && !f.contains(r'\['));
    if (formulaIssue) {
      risks.remove('含公式或表格，建议核对格式');
      risks.add('公式格式异常，缺少 \$...\$ 或 \\(...\\) 等 LaTex 标记，建议校对');
    }
  }
  // 表格格式异常：含表格块但 Markdown 不完整（行数<2、缺分隔行、列数不一致）。
  final hasTableBlock = region.recognizedBlockTypes.any((item) => item == '表格') ||
      region.tables.isNotEmpty;
  if (hasTableBlock) {
    final tableIssue = region.tables.isEmpty ||
        region.tables.any(_isTableMalformed);
    if (tableIssue) {
      risks.remove('含公式或表格，建议核对格式');
      risks.add('表格格式异常，建议补全 Markdown 分隔行或对齐列数');
    }
  }
  // 选项缺失：题型为选择题但未识别到选项行；或识别到选项块但未提取到选项行。
  final type = region.questionType;
  final isChoiceLike = type == null ||
      type.isEmpty ||
      type == '未指定' ||
      type == '选择题';
  if (isChoiceLike && !hasOptionLine(region.recognizedText)) {
    if (type == '选择题') {
      risks.add('题型为选择题但未识别到选项行，请补选项');
    } else if (region.recognizedBlockTypes.any((t) => t == '选项')) {
      risks.add('识别到选项块但未提取到选项行，建议校对');
    }
  }
  final hasDiagram = region.recognizedBlockTypes.any((item) {
    final value = item.toLowerCase();
    return item == '图形' || value.contains('diagram') || value.contains('figure');
  });
  if (hasDiagram && (region.diagramNote ?? '').trim().isEmpty) {
    risks.add('识别到图形但缺少图形说明，请核对原图并补充');
  }
  return risks;
}

/// 判断 Markdown 表格是否格式异常：
/// - 表格行数 < 2（只有表头没有数据行）
/// - 第二行不是分隔行（|---|---|）
/// - 各行列数不一致
bool _isTableMalformed(String markdown) {
  final lines = markdown
      .split('\n')
      .where((line) => line.trim().startsWith('|'))
      .toList();
  if (lines.length < 2) return true;
  final separator = lines[1].trim();
  if (!RegExp(r'^\|[\s:-]+(\|[\s:-]+)+\|?$').hasMatch(separator)) return true;
  final colCount = lines.first.split('|').length;
  for (final line in lines) {
    if (line.split('|').length != colCount) return true;
  }
  return false;
}

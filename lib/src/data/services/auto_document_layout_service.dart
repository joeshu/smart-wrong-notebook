import 'dart:ui';

import 'package:smart_wrong_notebook/src/data/services/mineru_document_layout_service.dart';
import 'package:smart_wrong_notebook/src/data/services/paddle_cloud_document_layout_service.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/domain/services/document_layout_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/recognition_page_router.dart';

/// Cost-aware layout routing: use PaddleOCR first, and only use MinerU VLM
/// when the fast candidate set is not credible enough for user review.
///
/// Phase 10-2：用结构化 [LayoutStageCallback] 替换原 `LayoutProgressCallback`
/// 字符串回调。3 个顶层阶段对应 Auto 编排：① PaddleOCR 快速识别 →
/// ② 检查候选框质量 → ③ 升级 MinerU 深度解析。子 service（Paddle/MinerU）
/// 内部的细粒度阶段不向上展开，避免阶段条回退难处理。
class AutoDocumentLayoutService implements DocumentLayoutService {
  AutoDocumentLayoutService(this.config, {this.onStage});
  final LayoutProviderConfig config;
  final LayoutStageCallback? onStage;

  @override
  Future<LayoutDetectionResult> detectQuestionRegions({
    required String imagePath,
    String? pageRanges,
    LayoutStageCallback? onStage,
  }) async {
    // 子调用用本 service 自己的 onStage（构造时注入）。
    // abstract 方法参数 onStage 仅用于多态调用方传入，Auto 不向下传递
    // （否则会和构造注入的回调重复触发）。
    const totalStages = 3;
    String? fallbackReason;
    try {
      onStage?.call(current: 0, total: totalStages, label: 'PaddleOCR 快速识别');
      final paddleConfig = LayoutProviderConfig(type: LayoutProviderType.paddleCloud, apiKey: config.apiKey);
      final fast = await PaddleCloudDocumentLayoutService(paddleConfig).detectQuestionRegions(imagePath: imagePath, pageRanges: pageRanges);
      onStage?.call(current: 1, total: totalStages, label: '检查候选框质量');
      final qualityIssue = _qualityIssue(fast.regions);
      if (qualityIssue == null) {
        return _withDocument(fast, imagePath, '${fast.providerLabel}（自动策略：快速结果可用）');
      }
      fallbackReason = qualityIssue;
    } catch (e) {
      // 保留 PaddleOCR 抛出的具体错误（如 "HTTP 401 Token 无效或已过期"），
      // 让 UI 升级提示能反映真实失败原因，而非模糊的 "未返回可用结果"。
      fallbackReason = 'PaddleOCR 不可用：${e.toString()}';
    }
    onStage?.call(current: 2, total: totalStages, label: '升级 MinerU 深度解析', detail: fallbackReason);
    final mineruConfig = LayoutProviderConfig(type: LayoutProviderType.mineruCloud, apiKey: config.secondaryApiKey);
    final precise = await MineruDocumentLayoutService(mineruConfig).detectQuestionRegions(imagePath: imagePath, pageRanges: pageRanges);
    return LayoutDetectionResult(
      regions: precise.regions,
      providerLabel: '${precise.providerLabel}（自动策略：已升级）',
      warning: '升级原因：$fallbackReason。${precise.warning ?? '请逐题检查候选框。'}',
      document: const RecognitionPageRouter().route(
        documentId: imagePath,
        regions: precise.regions,
      ),
    );
  }

  LayoutDetectionResult _withDocument(
    LayoutDetectionResult result,
    String imagePath,
    String providerLabel,
  ) => LayoutDetectionResult(
    regions: result.regions,
    providerLabel: providerLabel,
    warning: result.warning,
    document: const RecognitionPageRouter().route(
      documentId: imagePath,
      regions: result.regions,
    ),
  );

  String? _qualityIssue(List<QuestionRegion> regions) {
    if (regions.length < 2) return 'PaddleOCR 仅识别到 ${regions.length} 个候选框';
    final blocks = regions.expand((region) => region.documentBlocks);
    if (blocks.any((block) =>
        block.type == DocumentBlockType.handwriting ||
        block.recognitionStatus == DocumentRecognitionStatus.needsSpecialist)) {
      return '检测到手写或需要专用识别的内容块';
    }
    if (blocks.any((block) =>
        block.riskCodes.contains(DocumentBlockRiskCode.formulaIncomplete) ||
        block.riskCodes.contains(DocumentBlockRiskCode.tableStructureInvalid))) {
      return '公式或表格结构需要深度解析';
    }
    final coverage = regions.fold<double>(0, (sum, item) => sum + item.normalizedRect.width * item.normalizedRect.height);
    if (coverage < .12 || coverage > 1.35) return 'PaddleOCR 候选框覆盖范围异常';
    for (var i = 0; i < regions.length; i++) {
      for (var j = i + 1; j < regions.length; j++) {
        if (_iou(regions[i].normalizedRect, regions[j].normalizedRect) > .55) return 'PaddleOCR 候选框重叠较多';
      }
    }
    return null;
  }

  double _iou(Rect a, Rect b) {
    final overlap = a.intersect(b);
    if (overlap.isEmpty) return 0;
    final intersection = overlap.width * overlap.height;
    final union = a.width * a.height + b.width * b.height - intersection;
    return union <= 0 ? 0 : intersection / union;
  }
}

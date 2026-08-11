import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/document_layout_service.dart';

/// First layout provider: reuses the user's existing configured vision model.
class VisionDocumentLayoutService implements DocumentLayoutService {
  VisionDocumentLayoutService(this._aiService);

  final AiAnalysisService _aiService;

  @override
  Future<LayoutDetectionResult> detectQuestionRegions({
    required String imagePath,
    String? pageRanges,
    LayoutStageCallback? onStage,
  }) async {
    // Phase 10-2：视觉模型走多模态对话接口，无独立 pageRanges 概念；
    // 单步调用前发一次 onStage，让 UI 阶段条渲染 1 个圆点。
    onStage?.call(current: 0, total: 1, label: '调用 AI 视觉模型');
    final regions =
        await _aiService.detectWorksheetQuestionRegions(imagePath: imagePath);
    return LayoutDetectionResult(
      regions: regions,
      providerLabel: '当前 AI 视觉模型',
    );
  }
}

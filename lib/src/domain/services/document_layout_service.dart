import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';

class LayoutDetectionResult {
  const LayoutDetectionResult({
    required this.regions,
    required this.providerLabel,
    this.warning,
    this.document,
  });

  final List<QuestionRegion> regions;
  final String providerLabel;
  final String? warning;
  final RecognitionDocument? document;
}

/// Phase 10-2：版面识别分阶段进度回调。
///
/// 各 [DocumentLayoutService] 实现在内部状态切换时调用本回调，向 UI 层
/// 透传当前阶段索引、总阶段数、阶段名以及可选的子进度文案（如 PaddleCloud
/// 的「5/12 页」、MinerU 的「已等待 8s」）。
///
/// **约定**：
/// - 回调由 service 在主 isolate 同步触发，UI 层直接 setState 即可。
/// - 失败路径**不**回调"完成"阶段：异常照常向上抛，由调用方 catch 块
///   处理失败 UI，避免误导用户认为识别成功。
/// - 轮询循环中**只在状态切换时**回调（pending→running→done），不每次
///   轮询都触发，避免 setState 风暴。子进度文案变更可通过 [detail]
///   节流后上报。
typedef LayoutStageCallback = void Function({
  required int current,
  required int total,
  required String label,
  String? detail,
});

abstract class DocumentLayoutService {
  Future<LayoutDetectionResult> detectQuestionRegions({
    required String imagePath,
    String? pageRanges,
    LayoutStageCallback? onStage,
  });
}

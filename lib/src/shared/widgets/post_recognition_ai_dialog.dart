import 'package:flutter/material.dart';

/// Phase 10-3：「识别完成后是否交给 AI」三选一结果。
enum PostRecognitionAiChoice {
  /// 仅保留 OCR/文档识别结果，所有题框 `analyzeWithAi=false`。
  none,

  /// 保留各题默认 `analyzeWithAi`，由用户在工作台逐题切换。
  perQuestion,

  /// 所有题框 `analyzeWithAi=true`。
  all,
}

/// Phase 10-3：「识别完成，是否交给普通 AI？」统一决策弹窗。
///
/// 替代原本散落在 `worksheet_region_editor_screen` 中的私有实现，
/// 让 capture 入口 / analysis loading 入口可在 PaddleOCR/MinerU/Auto
/// 等路径上复用同一个决策点。
///
/// - [regionCount]：识别到的候选题框数量，用于文案。
/// - [providerLabel]：识别引擎名（如 "PaddleOCR"），用于文案。
/// - [defaultChoice]：默认选中态（用于"识别后默认是否交给 AI"设置项，
///   设置为 [PostRecognitionAiChoice.all] 时高亮 FilledButton）。
class PostRecognitionAiDialog {
  PostRecognitionAiDialog._();

  /// 弹出决策弹窗，返回用户选择；用户取消（点关闭按钮）返回 null。
  static Future<PostRecognitionAiChoice?> show(
    BuildContext context, {
    required int regionCount,
    String providerLabel = 'OCR/文档',
    PostRecognitionAiChoice? defaultChoice,
  }) {
    return showDialog<PostRecognitionAiChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('识别完成，是否交给普通 AI？'),
        content: Text(
          '已识别 $regionCount 个候选题框及其文字内容。\n\n'
          '普通 AI 可以继续完成题目理解、公式/几何分析、答案、错因、知识点和举一反三练习；'
          '不调用则只保留 $providerLabel 识别结果。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              PostRecognitionAiChoice.none,
            ),
            child: const Text('仅保留识别结果'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              PostRecognitionAiChoice.perQuestion,
            ),
            child: const Text('逐题选择'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              PostRecognitionAiChoice.all,
            ),
            child: const Text('全部交给普通 AI'),
          ),
        ],
      ),
    );
  }
}

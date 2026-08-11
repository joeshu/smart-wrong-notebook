import 'package:flutter/cupertino.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';

/// Phase 10-1：LayoutProviderType 统一显示信息扩展。
///
/// 替代原本散落在 9+ 处的硬编码中文标签，作为唯一的引擎文案来源。
extension LayoutProviderTypeLabel on LayoutProviderType {
  /// 引擎短名（用于徽章、列表项标题）。
  String get displayName => switch (this) {
        LayoutProviderType.currentVision => '普通AI视觉',
        LayoutProviderType.paddleCloud => 'PaddleOCR',
        LayoutProviderType.mineruCloud => 'MinerU',
        LayoutProviderType.autoCloud => '自动',
        LayoutProviderType.customHttp => '自定义 HTTP',
        LayoutProviderType.manualOnly => '仅手动',
      };

  /// 引擎完整名（用于设置页 RadioListTile、引擎选择弹窗标题）。
  String get fullLabel => switch (this) {
        LayoutProviderType.currentVision => '当前 AI 视觉模型',
        LayoutProviderType.paddleCloud => 'PaddleOCR AI Studio · 快速识别',
        LayoutProviderType.mineruCloud => 'MinerU VLM · 深度解析',
        LayoutProviderType.autoCloud => '自动：PaddleOCR 优先，MinerU 兜底',
        LayoutProviderType.customHttp => '自定义 HTTP 版面服务',
        LayoutProviderType.manualOnly => '仅手动框选',
      };

  /// 引擎描述（用于选择弹窗副标题、设置页 tile subtitle）。
  String get description => switch (this) {
        LayoutProviderType.currentVision => '调用 AI 模型直接看图识别，无需额外配置',
        LayoutProviderType.paddleCloud => '快速版面识别，适合清晰题目',
        LayoutProviderType.mineruCloud => 'VLM 深度解析，适合复杂版面与公式',
        LayoutProviderType.autoCloud => 'PaddleOCR 成功即返回，失败转 MinerU 兜底',
        LayoutProviderType.customHttp => '通过 HTTP 调用自建/局域网版面识别服务',
        LayoutProviderType.manualOnly => '不使用识别引擎，手工框选题目',
      };

  /// 引擎图标。
  IconData get icon => switch (this) {
        LayoutProviderType.currentVision => CupertinoIcons.sparkles,
        LayoutProviderType.paddleCloud => CupertinoIcons.doc_text_search,
        LayoutProviderType.mineruCloud => CupertinoIcons.doc_richtext,
        LayoutProviderType.autoCloud => CupertinoIcons.wand_stars,
        LayoutProviderType.customHttp => CupertinoIcons.link,
        LayoutProviderType.manualOnly => CupertinoIcons.hand_draw,
      };
}

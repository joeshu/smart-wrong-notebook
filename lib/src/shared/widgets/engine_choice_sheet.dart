import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';
import 'package:smart_wrong_notebook/src/shared/extensions/layout_provider_type_label.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';

/// Phase 10-1：统一的识别引擎选择器。
///
/// 替代原本散落在 `capture_entry_sheet` / `analysis_loading_screen` /
/// `worksheet_region_editor_screen` 三处的硬编码实现。
///
/// 通过 [EngineChoiceSheet.show] 弹出底部选择面板，返回用户选择的引擎
/// 或 `null`（取消）。未配置 token 的引擎会自动禁用，并显示"未配置"
/// 标签；同时提供"去设置"入口。
class EngineChoiceSheet extends StatelessWidget {
  const EngineChoiceSheet({
    super.key,
    required this.config,
    this.title = '选择识别引擎',
    this.subtitle = '选择本次用于识别题干、公式、选项和图形的服务。',
    this.selectedType,
    this.onOpenSettings,
    this.includeCurrentVision = true,
    this.includeManualOnly = true,
  });

  /// 当前 LayoutProvider 配置，用于判断各引擎是否就绪。
  final LayoutProviderConfig config;

  /// 弹窗标题。
  final String title;

  /// 弹窗副标题。
  final String subtitle;

  /// 当前选中的引擎（用于显示选中态）。
  final LayoutProviderType? selectedType;

  /// "去设置"回调；不传则不显示该入口。
  final VoidCallback? onOpenSettings;

  /// 是否包含「当前 AI 视觉模型」选项（默认包含）。
  /// 拍照入口可能不需要此项（已在外层判定）。
  final bool includeCurrentVision;

  /// 是否包含「仅手动框选」选项（默认包含）。
  final bool includeManualOnly;

  /// 弹出选择面板。返回用户选择的引擎类型，或 `null`（取消）。
  static Future<LayoutProviderType?> show(
    BuildContext context, {
    required LayoutProviderConfig config,
    String title = '选择识别引擎',
    String subtitle = '选择本次用于识别题干、公式、选项和图形的服务。',
    LayoutProviderType? selectedType,
    VoidCallback? onOpenSettings,
    bool includeCurrentVision = true,
    bool includeManualOnly = true,
  }) {
    return showModalBottomSheet<LayoutProviderType>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => EngineChoiceSheet(
        config: config,
        title: title,
        subtitle: subtitle,
        selectedType: selectedType,
        onOpenSettings: onOpenSettings,
        includeCurrentVision: includeCurrentVision,
        includeManualOnly: includeManualOnly,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final allTypes = <LayoutProviderType>[
      if (includeCurrentVision) LayoutProviderType.currentVision,
      LayoutProviderType.paddleCloud,
      LayoutProviderType.mineruCloud,
      LayoutProviderType.autoCloud,
      LayoutProviderType.customHttp,
      if (includeManualOnly) LayoutProviderType.manualOnly,
    ];
    final hasUnconfigured = allTypes.any((t) => !_isTypeReady(t));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: TextStyle(
                    fontSize: 12, color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            for (final type in allTypes)
              _EngineTile(
                type: type,
                ready: _isTypeReady(type),
                selected: type == selectedType,
                onTap: () => Navigator.pop(context, type),
              ),
            if (hasUnconfigured && onOpenSettings != null) ...<Widget>[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.warningContainerLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(CupertinoIcons.exclamationmark_triangle_fill,
                        size: 14, color: AppColors.warning),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '未配置的服务不可用，请先填写版面识别 Token。',
                        style: TextStyle(fontSize: 12, color: AppColors.warning),
                      ),
                    ),
                    TextButton(
                      onPressed: onOpenSettings,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('去设置'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 复用 LayoutProviderConfig.isReady 的判断逻辑，
  /// 但基于当前 [config] 模拟出每种 type 的就绪状态。
  bool _isTypeReady(LayoutProviderType type) {
    switch (type) {
      case LayoutProviderType.manualOnly:
      case LayoutProviderType.currentVision:
        return true;
      case LayoutProviderType.paddleCloud:
        return config.apiKey.isNotEmpty;
      case LayoutProviderType.mineruCloud:
        return config.apiKey.isNotEmpty;
      case LayoutProviderType.autoCloud:
        return config.apiKey.isNotEmpty &&
            config.secondaryApiKey.isNotEmpty;
      case LayoutProviderType.customHttp:
        return config.baseUrl.isNotEmpty;
    }
  }
}

class _EngineTile extends StatelessWidget {
  const _EngineTile({
    required this.type,
    required this.ready,
    required this.selected,
    required this.onTap,
  });

  final LayoutProviderType type;
  final bool ready;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      enabled: ready,
      leading: Icon(type.icon,
          color: ready ? colorScheme.primary : colorScheme.outline),
      title: Text(
        type.fullLabel,
        style: TextStyle(
          color: ready ? null : colorScheme.outline,
        ),
      ),
      subtitle: Text(
        ready
            ? type.description
            : '未配置 · ${type.description}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!ready)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.dangerContainerLight,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '未配置',
                style: TextStyle(fontSize: 10, color: AppColors.danger),
              ),
            )
          else if (selected)
            const Icon(CupertinoIcons.checkmark_circle_fill,
                color: AppColors.primary, size: 20),
        ],
      ),
      onTap: onTap,
    );
  }
}

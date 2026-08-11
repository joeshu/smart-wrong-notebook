import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 横向阶段进度指示器：N 个圆点 + 连接线，当前阶段高亮，已完成阶段带 ✓。
///
/// Phase 10-2：从 `analysis_loading_screen.dart` 的私有 `_StageIndicator`
/// 提取为公共组件，供 AI 解析、layout service 识别等场景复用。
///
/// 与原私有版本相比新增 [detail] 字段：渲染在阶段条下方一行小字，
/// 用于透传子进度文案（如 PaddleCloud 的「5/12 页」、MinerU 的「已等待 8s」）。
class StageIndicator extends StatelessWidget {
  const StageIndicator({
    super.key,
    required this.steps,
    required this.current,
    required this.accent,
    required this.dimColor,
    this.detail,
  });

  /// 阶段名列表（顺序即阶段顺序）。长度决定圆点数量。
  final List<String> steps;

  /// 当前阶段索引（0..steps.length-1）。负值表示尚未开始；≥length 视为已完成。
  final int current;

  /// 高亮色（当前/已完成）。通常传 `Theme.of(context).colorScheme.primary`。
  final Color accent;

  /// 未到达阶段色。通常传 `colorScheme.outlineVariant`。
  final Color dimColor;

  /// 可选：渲染在阶段条下方的子进度文案。null 时不渲染。
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final stageRow = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          // 连接线
          final filled = i < current * 2 + 1;
          return Container(
            width: 18,
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            color: filled ? accent : dimColor,
          );
        }
        final idx = i ~/ 2;
        final isDone = idx < current;
        final isCurrent = idx == current;
        final color = isCurrent
            ? accent
            : isDone
                ? accent.withValues(alpha: 0.6)
                : dimColor;
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: isCurrent ? accent : (isDone ? color : null),
            border: Border.all(color: color, width: 1.5),
            shape: BoxShape.circle,
          ),
          child: isDone
              ? const Icon(CupertinoIcons.checkmark, size: 8, color: Colors.white)
              : null,
        );
      }),
    );
    if (detail == null || detail!.isEmpty) return stageRow;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        stageRow,
        const SizedBox(height: 6),
        Text(
          detail!,
          style: TextStyle(fontSize: 11, color: dimColor),
        ),
      ],
    );
  }
}

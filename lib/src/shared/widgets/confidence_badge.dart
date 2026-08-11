import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

/// OCR 置信度徽章。展示彩色背景 + 文字 + 百分比，引导用户校对低置信度内容。
///
/// 阈值（与 worksheet_region_editor_screen.dart 的 _qualityColor/_qualityLabel 对齐）：
/// - >= 0.85：绿色，"识别可靠"
/// - >= 0.7：蓝色，"识别较可靠"
/// - >= 0.5：橙色，"建议校对"
/// - < 0.5：红色，"建议重新识别"
/// - null：灰色，"未记录置信度"
class ConfidenceBadge extends StatelessWidget {
  const ConfidenceBadge({
    super.key,
    required this.confidence,
    this.compact = false,
  });

  final double? confidence;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = _color;
    final label = _label;
    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 0.5),
        ),
        child: Text(
          confidence == null ? label : '$label ${(confidence! * 100).round()}%',
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            confidence == null ? label : '$label ${(confidence! * 100).round()}%',
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Color get _color {
    if (confidence == null) return const Color(0xFF94A3B8);
    final c = confidence!;
    if (c >= 0.85) return const Color(0xFF10B981);
    if (c >= 0.7) return const Color(0xFF3B82F6);
    if (c >= 0.5) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  String get _label {
    if (confidence == null) return '未记录置信度';
    final c = confidence!;
    if (c >= 0.85) return '识别可靠';
    if (c >= 0.7) return '识别较可靠';
    if (c >= 0.5) return '建议校对';
    return '建议重新识别';
  }

  IconData get _icon {
    if (confidence == null) return CupertinoIcons.question_circle;
    final c = confidence!;
    if (c >= 0.85) return CupertinoIcons.checkmark_seal_fill;
    if (c >= 0.7) return CupertinoIcons.checkmark_seal;
    if (c >= 0.5) return CupertinoIcons.exclamationmark_triangle;
    return CupertinoIcons.xmark_circle;
  }
}

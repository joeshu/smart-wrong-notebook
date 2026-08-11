import 'package:flutter/material.dart';

/// Phase 10-4：字段校对状态五态枚举（从 worksheet_region_editor 抽离）。
///
/// 用于统一对照工作台、识别结果页与校对页的字段状态文案与配色，避免
/// 不同位置出现「需校对 / 待校对 / 未检测到 / 未识别」等不一致文案。
/// [edited] 表示用户已手动校对过该字段，与原始识别结果不同。
enum FieldStatus {
  recognized,
  missing,
  needsReview,
  notApplicable,
  edited,
}

/// Phase 10-4：FieldStatus 文案与配色扩展。
extension FieldStatusStyle on FieldStatus {
  String get label => switch (this) {
        FieldStatus.recognized => '已识别',
        FieldStatus.missing => '未识别',
        FieldStatus.needsReview => '待校对',
        FieldStatus.notApplicable => '不适用',
        FieldStatus.edited => '已校对',
      };

  Color get backgroundColor => switch (this) {
        FieldStatus.recognized => const Color(0xFFF0FDF4),
        FieldStatus.needsReview => const Color(0xFFFFF7ED),
        FieldStatus.missing => const Color(0xFFFEF2F2),
        FieldStatus.notApplicable => const Color(0xFFF1F5F9),
        FieldStatus.edited => const Color(0xFFECFCCB),
      };

  Color get borderColor => switch (this) {
        FieldStatus.recognized => const Color(0xFFBBF7D0),
        FieldStatus.needsReview => const Color(0xFFFED7AA),
        FieldStatus.missing => const Color(0xFFFECACA),
        FieldStatus.notApplicable => const Color(0xFFE2E8F0),
        FieldStatus.edited => const Color(0xFFA3E635),
      };

  Color get foregroundColor => switch (this) {
        FieldStatus.recognized => const Color(0xFF166534),
        FieldStatus.needsReview => const Color(0xFF9A3412),
        FieldStatus.missing => const Color(0xFF991B1B),
        FieldStatus.notApplicable => const Color(0xFF475569),
        FieldStatus.edited => const Color(0xFF3F6212),
      };
}

/// Phase 10-4：字段状态徽章组件（从 worksheet_region_editor 抽离）。
///
/// 渲染形如「题干 · 已识别」的圆角徽章。`label` 为字段名，`status`
/// 决定配色与文案后缀。可直接用于识别结果页、校对页、对照工作台。
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.status = FieldStatus.recognized,
  });

  final String label;
  final FieldStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: status.backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: status.borderColor),
      ),
      child: Text(
        '$label · ${status.label}',
        style: TextStyle(fontSize: 10, color: status.foregroundColor),
      ),
    );
  }
}

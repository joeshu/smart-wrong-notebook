import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';

/// 科目头像：圆形底色（科目色 10% 透明度）+ 科目图标。
///
/// 统一首页最近错题卡与错题本三种视图（卡片/列表/时间线）的头像样式，
/// 避免各页面用 Container + BoxDecoration 重复实现同一语义。
///
/// [size] 控制直径；[iconSize] 默认取 [size] 的一半左右。
class SubjectAvatar extends StatelessWidget {
  const SubjectAvatar({
    super.key,
    required this.question,
    this.size,
    this.iconSize,
  });

  final QuestionRecord question;
  final double? size;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final resolvedSize = size ??
        (MediaQuery.of(context).size.width < 360 ? 36.0 : 40.0);
    final resolvedIconSize = iconSize ?? (resolvedSize * 0.45);
    return Container(
      width: resolvedSize,
      height: resolvedSize,
      decoration: BoxDecoration(
        color: question.subject.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(resolvedSize / 2),
      ),
      child: Icon(
        question.subject.icon,
        size: resolvedIconSize,
        color: question.subject.color,
      ),
    );
  }
}

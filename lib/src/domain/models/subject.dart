import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

enum Subject {
  chinese('语文', CupertinoIcons.doc_text, Color(0xFF16A34A)),
  math('数学', CupertinoIcons.function, Color(0xFF6366F1)),
  english('英语', CupertinoIcons.textformat_abc, Color(0xFFD97706)),
  physics('物理', CupertinoIcons.bolt, Color(0xFFEA580C)),
  chemistry('化学', CupertinoIcons.flame, Color(0xFF7C3AED)),
  biology('生物', CupertinoIcons.leaf_arrow_circlepath, Color(0xFF16A34A)),
  history('历史', CupertinoIcons.book, Color(0xFFD97706)),
  geography('地理', CupertinoIcons.globe, Color(0xFF6366F1)),
  politics('政治', CupertinoIcons.building_2_fill, Color(0xFF7C3AED)),
  science('科学', CupertinoIcons.lightbulb, Color(0xFFEA580C)),
  custom('自定义', CupertinoIcons.question, Colors.grey);

  const Subject(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  /// 把科目名/展示名解析成中文展示名；未知或自定义科目返回 null。
  ///
  /// 复制粘贴录入默认 [Subject.custom]（name='custom'），图片录入默认
  /// [Subject.math]（name='math'）。这些英文枚举名直接拼进分析 prompt 会变成
  /// "custom科目的错题"/"math科目的错题"，既无意义又让模型丢失科目上下文，
  /// 因此对外展示统一用中文 label（如"数学"），无法识别时返回 null 由调用方
  /// 改用中性描述并请模型在返回结果里自行判定科目。
  static String? resolveLabel(String name) {
    if (name.isEmpty) return null;
    for (final subject in Subject.values) {
      if (subject.name == name || subject.label == name) return subject.label;
    }
    return null;
  }
}
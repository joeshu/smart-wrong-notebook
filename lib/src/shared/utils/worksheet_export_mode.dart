/// 组卷导出的三种模式。
enum WorksheetExportMode {
  /// 练习卷：仅保留题干与答题留白，隐藏答案和解析。
  practice,

  /// 答案卷：题干 + 正确答案 + 完整解析。
  answer,

  /// 订正卷：题干 + 错因 + 学习建议 + 订正留白。
  correction;

  String get label => switch (this) {
        WorksheetExportMode.practice => '练习卷',
        WorksheetExportMode.answer => '答案卷',
        WorksheetExportMode.correction => '订正卷',
      };
}

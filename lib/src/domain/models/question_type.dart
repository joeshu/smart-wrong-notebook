import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 错题的题型分类。
///
/// 与 [Subject] / [MasteryLevel] / [ContentStatus] 一样以独立 `text` 列持久化
/// （`question_records.questionType`，schemaVersion=11 引入），允许为空——
/// PaddleOCR / MinerU 仅做版面识别时不一定能推断题型，普通 AI 分析后才补全。
///
/// 序列化走 `name`，反序列化用 `QuestionType.values.firstWhere`，
/// 与 [Subject] 保持一致。UI 标签通过 [QuestionTypeLabel] 扩展提供。
enum QuestionType {
  singleChoice,
  multipleChoice,
  trueFalse,
  fillIn,
  shortAnswer,
  essay,
  calculation,
  proof,
  experiment,
  other,
}

/// 题型中文标签与图标扩展，集中维护便于详情页、筛选器、导出共用。
extension QuestionTypeLabel on QuestionType {
  String get label => switch (this) {
        QuestionType.singleChoice => '单选题',
        QuestionType.multipleChoice => '多选题',
        QuestionType.trueFalse => '判断题',
        QuestionType.fillIn => '填空题',
        QuestionType.shortAnswer => '简答题',
        QuestionType.essay => '论述题',
        QuestionType.calculation => '计算题',
        QuestionType.proof => '证明题',
        QuestionType.experiment => '实验题',
        QuestionType.other => '其他题型',
      };

  IconData get icon => switch (this) {
        QuestionType.singleChoice => CupertinoIcons.circle,
        QuestionType.multipleChoice => CupertinoIcons.list_bullet,
        QuestionType.trueFalse => CupertinoIcons.checkmark_seal,
        QuestionType.fillIn => CupertinoIcons.text_cursor,
        QuestionType.shortAnswer => CupertinoIcons.text_alignleft,
        QuestionType.essay => CupertinoIcons.doc_text,
        QuestionType.calculation => CupertinoIcons.function,
        QuestionType.proof => CupertinoIcons.equal_circle,
        QuestionType.experiment => CupertinoIcons.lightbulb,
        QuestionType.other => CupertinoIcons.question,
      };
}

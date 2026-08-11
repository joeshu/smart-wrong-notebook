import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_content_options.dart';
import 'package:smart_wrong_notebook/src/shared/utils/markdown_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/worksheet_export_mode.dart';

void main() {
  late MarkdownExportService service;

  setUp(() {
    service = MarkdownExportService();
  });

  List<QuestionRecord> _sampleQuestions() => <QuestionRecord>[
        QuestionRecord.draft(
          id: 'q-1',
          imagePath: '',
          subject: Subject.math,
          recognizedText: '已知 2x+1=5，求 x 的值',
        ).copyWith(
          analysisResult: const AnalysisResult(
            finalAnswer: 'x=2',
            steps: <String>['移项得 2x=4', '两边除以 2 得 x=2'],
            aiTags: <String>['方程'],
            knowledgePoints: <String>['代数'],
            mistakeReason: '移项时忘变号',
            studyAdvice: '注意变号',
          ),
        ),
        QuestionRecord.draft(
          id: 'q-2',
          imagePath: '',
          subject: Subject.english,
          recognizedText: 'Choose the correct answer',
        ),
      ];

  test('generateMarkdown produces a structured markdown report header', () async {
    final markdown = await service.generateMarkdown(
      questions: _sampleQuestions(),
      mode: WorksheetExportMode.answer,
      contentOptions: ExportContentOptions.all,
      studentName: '张三',
      className: '三年二班',
    );

    expect(markdown, startsWith('# 错题本整理报告'));
    expect(markdown, contains('- **学生姓名：** 张三'));
    expect(markdown, contains('- **班级：** 三年二班'));
    expect(markdown, contains('- **导出日期：**'));
    expect(markdown, contains('- **题目总数：** 2 道'));
    expect(markdown, contains('- **导出模式：** 答案卷'));
  });

  test('generateMarkdown groups questions by subject with H2 headers', () async {
    final markdown = await service.generateMarkdown(
      questions: _sampleQuestions(),
      mode: WorksheetExportMode.answer,
      contentOptions: ExportContentOptions.all,
    );

    expect(markdown, contains('## 数学（1 题）'));
    expect(markdown, contains('## 英语（1 题）'));
    expect(markdown, contains('### 题 1'));
    expect(markdown, contains('### 题 2'));
  });

  test('generateMarkdown includes analysis fields in answer mode', () async {
    final markdown = await service.generateMarkdown(
      questions: _sampleQuestions(),
      mode: WorksheetExportMode.answer,
      contentOptions: ExportContentOptions.all,
    );

    expect(markdown, contains('**正确答案：** x=2'));
    expect(markdown, contains('**知识点：** 代数、方程'));
    expect(markdown, contains('**错因：** 移项时忘变号'));
    expect(markdown, contains('**学习建议：** 注意变号'));
    expect(markdown, contains('已知 2x+1=5，求 x 的值'));
  });

  test('generateMarkdown hides correct answer in practice mode', () async {
    final markdown = await service.generateMarkdown(
      questions: _sampleQuestions(),
      mode: WorksheetExportMode.practice,
      contentOptions: ExportContentOptions.all,
    );

    expect(markdown, contains('### 题 1'));
    expect(markdown, isNot(contains('**正确答案：** x=2')));
  });

  test('generateMarkdown appends statistics section', () async {
    final markdown = await service.generateMarkdown(
      questions: _sampleQuestions(),
      mode: WorksheetExportMode.answer,
      contentOptions: const ExportContentOptions(),
    );

    expect(markdown, contains('## 统计'));
    expect(markdown, contains('- **总题数：** 2 道'));
    expect(markdown, contains('### 按学科分布'));
    expect(markdown, contains('### 按掌握度分布'));
  });
}

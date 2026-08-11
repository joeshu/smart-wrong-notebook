import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/shared/utils/csv_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_content_options.dart';
import 'package:smart_wrong_notebook/src/shared/utils/json_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/markdown_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/worksheet_export_mode.dart';

/// Phase 11-9：空字段 / 缺失附件导出容错回归测试。
///
/// 验证当题目缺少图、AI 分析、知识点等字段时，各导出服务不抛异常，
/// 并能生成结构合法的输出。
void main() {
  group('空字段容错', () {
    test('完全空白题目（无图无文本无分析）能被 Markdown 导出', () async {
      final questions = <QuestionRecord>[
        QuestionRecord.draft(
          id: 'empty-1',
          imagePath: '',
          subject: Subject.math,
          recognizedText: '',
        ),
      ];
      final markdown = await MarkdownExportService().generateMarkdown(
        questions: questions,
        mode: WorksheetExportMode.answer,
        contentOptions: ExportContentOptions.all,
      );
      expect(markdown, startsWith('# 错题本整理报告'));
      expect(markdown, contains('题 1'));
    });

    test('完全空白题目能被 JSON 导出且结构合法', () async {
      final questions = <QuestionRecord>[
        QuestionRecord.draft(
          id: 'empty-2',
          imagePath: '',
          subject: Subject.math,
          recognizedText: '',
        ),
      ];
      final json = await JsonExportService().generateJson(
        questions: questions,
        contentOptions: const ExportContentOptions(),
      );
      expect(json, contains('"questions"'));
      expect(json, contains('"id": "empty-2"'));
    });

    test('完全空白题目能被 CSV 导出且表头完整', () async {
      final questions = <QuestionRecord>[
        QuestionRecord.draft(
          id: 'empty-3',
          imagePath: '',
          subject: Subject.math,
          recognizedText: '',
        ),
      ];
      final csv = await CsvExportService().generateCsv(
        questions: questions,
        contentOptions: const ExportContentOptions(),
      );
      final lines = csv.split('\n').where((l) => l.isNotEmpty).toList();
      expect(lines.length, greaterThanOrEqualTo(2)); // 表头 + 1 行
      expect(lines.first, contains('学科'));
    });

    test(' imagePath 指向不存在文件时不阻塞 Markdown 导出', () async {
      final questions = <QuestionRecord>[
        QuestionRecord.draft(
          id: 'missing-img',
          imagePath: '/nonexistent/path/to/image.png',
          subject: Subject.math,
          recognizedText: '题干文本',
        ),
      ];
      final markdown = await MarkdownExportService().generateMarkdown(
        questions: questions,
        mode: WorksheetExportMode.answer,
        contentOptions: const ExportContentOptions(),
      );
      expect(markdown, contains('题干文本'));
    });

    test('混合空字段与完整字段的多题导出不报错', () async {
      final questions = <QuestionRecord>[
        QuestionRecord.draft(
          id: 'full',
          imagePath: '',
          subject: Subject.math,
          recognizedText: '完整题',
        ),
        QuestionRecord.draft(
          id: 'empty',
          imagePath: '',
          subject: Subject.math,
          recognizedText: '',
        ),
        QuestionRecord.draft(
          id: 'no-subject-text',
          imagePath: '',
          subject: Subject.english,
          recognizedText: '   ',
        ),
      ];
      final markdown = await MarkdownExportService().generateMarkdown(
        questions: questions,
        mode: WorksheetExportMode.answer,
        contentOptions: ExportContentOptions.all,
      );
      expect(markdown, contains('题 1'));
      expect(markdown, contains('题 2'));
      expect(markdown, contains('题 3'));
    });
  });
}

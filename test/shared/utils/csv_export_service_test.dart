import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/shared/utils/csv_export_service.dart';

void main() {
  late CsvExportService service;

  setUp(() {
    service = CsvExportService();
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
            steps: <String>['移项得 2x=4'],
            aiTags: <String>['方程'],
            knowledgePoints: <String>['代数'],
            mistakeReason: '审题不清',
            studyAdvice: '多复习',
          ),
        ),
        QuestionRecord.draft(
          id: 'q-2',
          imagePath: '',
          subject: Subject.english,
          recognizedText: 'Choose the correct answer',
        ),
      ];

  test('generateCsv starts with header row containing all columns', () async {
    final csv = await service.generateCsv(questions: _sampleQuestions());

    final lines = csv.split('\n');
    expect(lines.first, contains('"题号"'));
    expect(lines.first, contains('"学科"'));
    expect(lines.first, contains('"题干"'));
    expect(lines.first, contains('"知识点"'));
    expect(lines.first, contains('"错因"'));
    expect(lines.first, contains('"掌握度"'));
    expect(lines.first, contains('"难度"'));
    expect(lines.first, contains('"复习次数"'));
    expect(lines.first, contains('"收藏"'));
    expect(lines.first, contains('"创建日期"'));
    expect(lines.first, contains('"上次复习日期"'));
    expect(lines.first, contains('"下次复习日期"'));
  });

  test('generateCsv writes one data row per question with index', () async {
    final csv = await service.generateCsv(questions: _sampleQuestions());

    final lines = csv.split('\n').where((l) => l.trim().isNotEmpty).toList();
    // 1 header + 2 data rows.
    expect(lines, hasLength(3));
    expect(lines[1], contains('"1"'));
    expect(lines[1], contains('"数学"'));
    expect(lines[1], contains('"已知 2x+1=5，求 x 的值"'));
    expect(lines[1], contains('"代数、方程"'));
    expect(lines[1], contains('"审题不清"'));
    expect(lines[2], contains('"2"'));
    expect(lines[2], contains('"英语"'));
    expect(lines[2], contains('"Choose the correct answer"'));
  });

  test('generateCsv escapes embedded quotes and commas', () async {
    final questions = <QuestionRecord>[
      QuestionRecord.draft(
        id: 'q-esc',
        imagePath: '',
        subject: Subject.math,
        recognizedText: '题干,带逗号 and "引号"',
      ),
    ];

    final csv = await service.generateCsv(questions: questions);

    // 字段用双引号包裹，内部双引号转义为两个双引号。
    expect(csv, contains('"题干,带逗号 and ""引号"""'));
  });
}

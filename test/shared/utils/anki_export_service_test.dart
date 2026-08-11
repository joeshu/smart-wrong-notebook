import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/shared/utils/anki_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_content_options.dart';

void main() {
  late AnkiExportService service;
  late Directory tempDir;
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('anki_export_test_');
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    });
    service = AnkiExportService();
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
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

  test('generateAnkiImportText emits TSV header with tabs', () async {
    final text = await service.generateAnkiImportText(
      questions: _sampleQuestions(),
      contentOptions: ExportContentOptions.all,
    );

    expect(text, contains('正面\t背面\t学科\t知识点\t错因'));
  });

  test('generateAnkiImportText writes one row per question', () async {
    final text = await service.generateAnkiImportText(
      questions: _sampleQuestions(),
      contentOptions: ExportContentOptions.all,
    );

    final lines = text.split('\n').where((l) => l.isNotEmpty).toList();
    // 1 header + 2 data rows.
    expect(lines, hasLength(3));
    expect(lines[1], contains('数学'));
    expect(lines[1], contains('已知 2x+1=5，求 x 的值'));
    expect(lines[1], contains('代数、方程'));
    expect(lines[1], contains('审题不清'));
    expect(lines[2], contains('英语'));
    expect(lines[2], contains('Choose the correct answer'));
  });

  test('generateAnkiImportText builds back side HTML with correct answer', () async {
    final text = await service.generateAnkiImportText(
      questions: _sampleQuestions(),
      contentOptions: ExportContentOptions.all,
    );

    expect(text, contains('<b>正确答案：</b>x=2'));
    expect(text, contains('<b>解题步骤：</b>'));
    expect(text, contains('<b>知识点：</b>代数、方程'));
  });

  test('generateAnkiImportText creates anki_images directory in export dir',
      () async {
    await service.generateAnkiImportText(
      questions: _sampleQuestions(),
      contentOptions: ExportContentOptions.all,
    );

    final imageDir =
        Directory('${tempDir.path}/exports/${AnkiExportService.imageDirName}');
    expect(imageDir.existsSync(), isTrue);
  });

  test('generateAnkiImportText escapes HTML special chars in question text',
      () async {
    final questions = <QuestionRecord>[
      QuestionRecord.draft(
        id: 'q-esc',
        imagePath: '',
        subject: Subject.math,
        recognizedText: 'a<b>c & d',
      ),
    ];

    final text = await service.generateAnkiImportText(
      questions: questions,
      contentOptions: ExportContentOptions.all,
    );

    expect(text, contains('a&lt;b&gt;c &amp; d'));
  });
}

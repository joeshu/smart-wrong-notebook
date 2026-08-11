import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/shared/utils/pdf_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/worksheet_export_mode.dart';

/// 禁用网络：让 [PdfGoogleFonts] 立即抛错，触发 [_loadCjkFont] 的 catch 分支
/// 回退到 Helvetica，避免测试在 CI 等无外网环境卡住 HTTP 超时。
class _NoNetworkHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw const SocketException('Network disabled in PDF export test');
  }
}

void main() {
  late Directory tempDir;
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('pdf_export_test_');
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    });
    HttpOverrides.global = _NoNetworkHttpOverrides();
  });

  tearDown(() {
    HttpOverrides.global = null;
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

  test('generatePdf writes a non-empty file beginning with %PDF', () async {
    final file = await PdfExportService.generatePdf(
      _sampleQuestions(),
      title: '错题本PDF测试',
      mode: WorksheetExportMode.answer,
    );

    expect(file.existsSync(), isTrue);
    final bytes = await file.readAsBytes();
    expect(bytes, isNotEmpty);
    final magic = String.fromCharCodes(bytes.take(4));
    expect(magic, '%PDF');
  });

  test('generatePdf writes file under the exports directory of the temp root',
      () async {
    final file = await PdfExportService.generatePdf(
      _sampleQuestions(),
      mode: WorksheetExportMode.answer,
    );

    expect(file.path, startsWith(tempDir.path));
    expect(file.path, contains('exports'));
    expect(file.path, endsWith('.pdf'));
  });

  test('generatePdf in practice mode still produces a valid PDF', () async {
    final file = await PdfExportService.generatePdf(
      _sampleQuestions(),
      mode: WorksheetExportMode.practice,
    );

    final bytes = await file.readAsBytes();
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('generatePdf with formula content produces valid PDF', () async {
    final questions = <QuestionRecord>[
      QuestionRecord.draft(
        id: 'q-formula',
        imagePath: '',
        subject: Subject.math,
        recognizedText: r'解方程 $x^2 + 2x - 3 = 0$',
      ).copyWith(
        contentFormat: QuestionContentFormat.latexMixed,
        analysisResult: const AnalysisResult(
          finalAnswer: r'$x = 1$ 或 $x = -3$',
          steps: <String>[r'使用求根公式：$x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}$'],
          aiTags: <String>[],
          knowledgePoints: <String>[],
          mistakeReason: '',
          studyAdvice: '',
        ),
      ),
    ];

    final file = await PdfExportService.generatePdf(
      questions,
      title: '公式测试',
      mode: WorksheetExportMode.practice,
    );

    final bytes = await file.readAsBytes();
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('generatePdf with table content produces valid PDF', () async {
    final questions = <QuestionRecord>[
      QuestionRecord.draft(
        id: 'q-table',
        imagePath: '',
        subject: Subject.math,
        recognizedText: '''计算以下数据的平均值：
| 序号 | 数值 |
| --- | --- |
| 1 | 10 |
| 2 | 20 |
| 3 | 30 |''',
      ).copyWith(
        analysisResult: const AnalysisResult(
          finalAnswer: '20',
          steps: <String>['(10+20+30)/3 = 20'],
          aiTags: <String>[],
          knowledgePoints: <String>[],
          mistakeReason: '',
          studyAdvice: '',
        ),
      ),
    ];

    final file = await PdfExportService.generatePdf(
      questions,
      title: '表格测试',
      mode: WorksheetExportMode.practice,
    );

    final bytes = await file.readAsBytes();
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('generatePdf with failed status question produces valid PDF', () async {
    final questions = <QuestionRecord>[
      QuestionRecord.draft(
        id: 'q-failed',
        imagePath: '',
        subject: Subject.math,
        recognizedText: '识别失败的题目',
      ).copyWith(contentStatus: ContentStatus.failed),
    ];

    final file = await PdfExportService.generatePdf(
      questions,
      title: '失败状态测试',
      mode: WorksheetExportMode.practice,
    );

    final bytes = await file.readAsBytes();
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('generatePdf with all modes produces valid PDFs', () async {
    final questions = _sampleQuestions();
    for (final mode in WorksheetExportMode.values) {
      final file = await PdfExportService.generatePdf(
        questions,
        title: '模式测试 - ${mode.name}',
        mode: mode,
      );
      final bytes = await file.readAsBytes();
      expect(bytes, isNotEmpty, reason: 'Mode ${mode.name} produced empty PDF');
      expect(String.fromCharCodes(bytes.take(4)), '%PDF', reason: 'Mode ${mode.name} produced invalid PDF');
    }
  });
}

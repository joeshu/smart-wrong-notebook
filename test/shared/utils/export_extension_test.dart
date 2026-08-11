import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/shared/utils/anki_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_content_options.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_history_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/pdf_layout_options.dart';

const _mockKatexCss = '/* mock katex css */';
const _mockKatexJs = '/* mock katex js */';

ByteData _byteDataFromString(String s) => ByteData.sublistView(utf8.encode(s));

Future<ByteData?> _mockAssetHandler(ByteData? message) async {
  if (message == null) return null;
  final key = utf8.decode(message.buffer.asUint8List());
  if (key == 'assets/katex/katex.min.css') {
    return _byteDataFromString(_mockKatexCss);
  }
  if (key == 'assets/katex/katex.min.js') {
    return _byteDataFromString(_mockKatexJs);
  }
  return null;
}

/// Phase 11-9：导出能力扩展回归测试。
///
/// 覆盖：
/// 1. Anki 空字段容错 + 知识点树路径输出（Phase 11-3）。
/// 2. HTML 大题量性能基线（Phase 11-9）。
/// 3. PdfLayoutOptions 新增 headerText / {knowledgePath} 占位符（Phase 11-5）。
/// 4. ExportHistoryService 持久化（Phase 11-7）。
void main() {
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;

  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('export_ext_test_');
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    });
    // mock KaTeX CSS/JS 资源加载（HTML 导出依赖）。
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', _mockAssetHandler);
    // ExportHistoryService 用 SharedPreferences，需 mock 初始空值。
    SharedPreferences.setMockInitialValues(<String, Object>{});
    HtmlExportCache.clear();
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    HtmlExportCache.clear();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Anki 空字段容错（Phase 11-3/9）', () {
    test('完全空白题目（无图无文本无分析）能被 Anki 导出且行结构合法', () async {
      final questions = <QuestionRecord>[
        QuestionRecord.draft(
          id: 'anki-empty',
          imagePath: '',
          subject: Subject.math,
          recognizedText: '',
        ),
      ];
      final text = await AnkiExportService().generateAnkiImportText(
        questions: questions,
        contentOptions: ExportContentOptions.all,
      );
      final lines = text.split('\n').where((l) => l.isNotEmpty).toList();
      expect(lines.length, greaterThanOrEqualTo(2)); // 表头 + 1 行
      expect(lines.first, contains('正面'));
      expect(lines.last, contains('数学'));
    });

    test('imagePath 指向不存在文件时 Anki 导出不阻塞', () async {
      final questions = <QuestionRecord>[
        QuestionRecord.draft(
          id: 'anki-missing-img',
          imagePath: '/nonexistent/path/to/img.png',
          subject: Subject.math,
          recognizedText: '题干',
        ),
      ];
      final text = await AnkiExportService().generateAnkiImportText(
        questions: questions,
        contentOptions: ExportContentOptions.all,
      );
      expect(text, contains('题干'));
    });
  });

  group('Anki 知识点树路径（Phase 11-3）', () {
    test('includeKnowledgeTree 打开时背面输出知识点路径', () async {
      final questions = <QuestionRecord>[
        QuestionRecord.draft(
          id: 'q-tree',
          imagePath: '',
          subject: Subject.math,
          recognizedText: '题干',
        ).copyWith(
          analysisResult: const AnalysisResult(
            finalAnswer: '答案',
            steps: <String>[],
            aiTags: <String>[],
            knowledgePoints: <String>[],
            mistakeReason: '',
            studyAdvice: '',
          ),
        ),
      ];
      final text = await AnkiExportService().generateAnkiImportText(
        questions: questions,
        contentOptions:
            const ExportContentOptions(includeKnowledgeTree: true),
        knowledgeTreePaths: const <String, List<String>>{
          'q-tree': <String>['数学 > 代数 > 二次方程'],
        },
      );
      expect(text, contains('知识点路径'));
      expect(text, contains('数学 &gt; 代数 &gt; 二次方程'));
    });

    test('includeKnowledgeTree 关闭时不输出知识点路径', () async {
      final questions = <QuestionRecord>[
        QuestionRecord.draft(
          id: 'q-tree-2',
          imagePath: '',
          subject: Subject.math,
          recognizedText: '题干',
        ).copyWith(
          analysisResult: const AnalysisResult(
            finalAnswer: '答案',
            steps: <String>[],
            aiTags: <String>[],
            knowledgePoints: <String>[],
            mistakeReason: '',
            studyAdvice: '',
          ),
        ),
      ];
      final text = await AnkiExportService().generateAnkiImportText(
        questions: questions,
        contentOptions: const ExportContentOptions(includeKnowledgeTree: false),
        knowledgeTreePaths: const <String, List<String>>{
          'q-tree-2': <String>['数学 > 代数'],
        },
      );
      expect(text, isNot(contains('知识点路径')));
    });
  });

  group('HTML 大题量性能基线（Phase 11-9）', () {
    test('50 题导出 HTML 在合理时间内完成且体积可控', () async {
      final questions = List<QuestionRecord>.generate(
        50,
        (i) => QuestionRecord.draft(
          id: 'perf-$i',
          imagePath: '',
          subject: Subject.math,
          recognizedText: '第 ${i + 1} 题题干内容',
        ).copyWith(
          analysisResult: AnalysisResult(
            finalAnswer: '答案 $i',
            steps: const <String>['步骤1', '步骤2'],
            aiTags: const <String>[],
            knowledgePoints: const <String>[],
            mistakeReason: '',
            studyAdvice: '',
          ),
        ),
      );

      final stopwatch = Stopwatch()..start();
      final result = await HtmlExportService.generateHtml(
        questions,
        title: '性能测试',
        contentOptions: ExportContentOptions.all,
      );
      stopwatch.stop();

      // 50 题无图导出应在 5 秒内完成（CI 环境宽松上限）。
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
      // HTML 体积应小于 2MB（无图、无 KaTeX 字体内联到 result）。
      expect(result.htmlSizeBytes, lessThan(2 * 1024 * 1024));
      expect(result.totalQuestions, 50);
    });

    test('流式写入阈值：50 题导出不抛异常（触发流式路径）', () async {
      // 50 题应触发流式写入（_streamingQuestionThreshold = 50）。
      final questions = List<QuestionRecord>.generate(
        50,
        (i) => QuestionRecord.draft(
          id: 'stream-$i',
          imagePath: '',
          subject: Subject.math,
          recognizedText: '题 $i',
        ),
      );
      final result = await HtmlExportService.generateHtml(
        questions,
        title: '流式测试',
      );
      expect(result.totalQuestions, 50);
    });
  });

  group('PdfLayoutOptions 占位符（Phase 11-5）', () {
    test('resolveFooter 支持 {knowledgePath} 占位符', () {
      final result = PdfLayoutOptions.resolveFooter(
        '第 {page} 页 | {knowledgePath}',
        3,
        10,
        '2026-07-22',
        '张三',
        knowledgePath: '数学 > 代数',
      );
      expect(result, '第 3 页 | 数学 > 代数');
    });

    test('resolveFooter 支持 {知识点路径} 中文别名', () {
      final result = PdfLayoutOptions.resolveFooter(
        '{知识点路径} - 第 {page} 页',
        1,
        5,
        '',
        null,
        knowledgePath: '英语 > 语法',
      );
      expect(result, '英语 > 语法 - 第 1 页');
    });

    test('resolveHeader 自定义文本覆盖默认标题', () {
      final result = PdfLayoutOptions.resolveHeader(
        '{knowledgePath} · {studentName}',
        '默认标题',
        knowledgePath: '物理 > 力学',
        studentName: '李四',
      );
      expect(result, '物理 > 力学 · 李四');
    });

    test('resolveHeader 为空时返回默认标题', () {
      final result = PdfLayoutOptions.resolveHeader(
        null,
        '错题本报告',
      );
      expect(result, '错题本报告');
    });

    test('PdfLayoutOptions.copyWith 支持 headerText', () {
      const opts = PdfLayoutOptions();
      final copied = opts.copyWith(headerText: '{knowledgePath}');
      expect(copied.headerText, '{knowledgePath}');
      expect(copied.footerText, isNull); // 未改的字段保持原值
    });
  });

  group('ExportHistoryService 持久化（Phase 11-7）', () {
    test('add 后 list 能读到记录且按时间倒序', () async {
      await ExportHistoryService.clear();
      await ExportHistoryService.add(ExportHistoryEntry(
        timestamp: 1000,
        format: 'PDF',
        template: '错题报告',
        questionCount: 10,
        title: '第一批',
      ));
      await ExportHistoryService.add(ExportHistoryEntry(
        timestamp: 2000,
        format: 'Markdown',
        template: '复习卡',
        questionCount: 5,
        title: '第二批',
      ));

      final list = await ExportHistoryService.list();
      expect(list, hasLength(2));
      // 最新（timestamp 大）的在前。
      expect(list.first.format, 'Markdown');
      expect(list.first.timestamp, 2000);
      expect(list.last.format, 'PDF');
    });

    test('超过 10 条自动丢弃最旧的', () async {
      await ExportHistoryService.clear();
      for (var i = 0; i < 12; i++) {
        await ExportHistoryService.add(ExportHistoryEntry(
          timestamp: i,
          format: '格式$i',
          template: '模板',
          questionCount: i,
          title: '标题$i',
        ));
      }
      final list = await ExportHistoryService.list();
      expect(list, hasLength(10));
      // 保留 timestamp 2..11（丢弃 0、1）。
      expect(list.last.timestamp, 2); // 最旧的是 timestamp=2
      expect(list.first.timestamp, 11); // 最新的是 timestamp=11
    });

    test('clear 清空全部记录', () async {
      await ExportHistoryService.add(ExportHistoryEntry(
        timestamp: 1,
        format: 'PDF',
        template: '错题报告',
        questionCount: 1,
        title: 't',
      ));
      await ExportHistoryService.clear();
      final list = await ExportHistoryService.list();
      expect(list, isEmpty);
    });
  });
}

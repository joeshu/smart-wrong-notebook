import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_content_options.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_export_service.dart';

const _mockKatexCss = '/* mock katex css for test */';
const _mockKatexJs = '/* mock katex js for test */';

ByteData _byteDataFromString(String s) =>
    ByteData.sublistView(utf8.encode(s));

Future<ByteData?> _mockAssetHandler(ByteData? message) async {
  if (message == null) return null;
  final key = utf8.decode(message.buffer.asUint8List());
  if (key == 'assets/katex/katex.min.css') {
    return _byteDataFromString(_mockKatexCss);
  }
  if (key == 'assets/katex/katex.min.js') {
    return _byteDataFromString(_mockKatexJs);
  }
  // woff2 字体：返回 null，HtmlExportService._inlineAllFontFaces 会 catch 异常
  // 后保留原始 url，不影响 HTML 生成。
  return null;
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      _mockAssetHandler,
    );
    HtmlExportCache.clear();
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    HtmlExportCache.clear();
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

  test('generateHtmlString returns self-contained HTML document', () async {
    final html = await HtmlExportService.generateHtmlString(
      _sampleQuestions(),
      title: '错题本HTML测试',
      noImage: true,
    );

    expect(html, startsWith('<!DOCTYPE html>'));
    expect(html, contains('<html'));
    expect(html, contains('</html>'));
    expect(html, contains('<title>错题本HTML测试</title>'));
  });

  test('generateHtmlString renders cover and TOC by default layout', () async {
    final html = await HtmlExportService.generateHtmlString(
      _sampleQuestions(),
      title: '错题本报告',
      noImage: true,
    );

    // 默认 PdfLayoutOptions.includeCover=true，封面包含题目总数。
    expect(html, contains('错题本报告'));
    expect(html, contains('数学'));
    expect(html, contains('英语'));
    expect(html, contains('已知 2x+1=5，求 x 的值'));
    expect(html, contains('Choose the correct answer'));
  });

  test('generateHtmlString inlines KaTeX CSS and JS', () async {
    final html = await HtmlExportService.generateHtmlString(
      _sampleQuestions(),
      noImage: true,
    );

    expect(html, contains(_mockKatexCss));
    expect(html, contains(_mockKatexJs));
  });

  test('generateHtmlString caches result when contentOptions provided', () async {
    final questions = _sampleQuestions();
    const options = ExportContentOptions.all;

    final first = await HtmlExportService.generateHtmlString(
      questions,
      noImage: true,
      contentOptions: options,
    );

    // 第二次相同参数应命中缓存（返回相同字符串引用）。
    final second = await HtmlExportService.generateHtmlString(
      questions,
      noImage: true,
      contentOptions: options,
    );

    expect(identical(first, second), isTrue);
  });

  test('buildExportFileName produces sanitized file name with extension',
      () {
    final name = HtmlExportService.buildExportFileName(
      _sampleQuestions(),
      extension: 'html',
    );

    expect(name, endsWith('.html'));
    // 包含题量与学科范围。
    expect(name, contains('2题'));
    expect(name, contains('多学科'));
  });
}

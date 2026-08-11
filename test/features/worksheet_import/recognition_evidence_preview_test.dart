import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/features/worksheet_import/presentation/worksheet_region_editor_screen.dart';

/// `RecognitionEvidencePreview` 对照工作台的 widget 测试。
///
/// 覆盖字段状态四态展示（含选项/图形 pill）、空间风险在字段状态区
/// 合并显示、展开/收起按钮、附件缺失占位符。
///
/// 测试全部使用不存在的图片路径，让 `_buildImage` 走"原图附件缺失"
/// 分支；这样既验证了附件缺失提示，又规避了 `CachedQuestionImage`
/// 在测试环境中 spawn isolate 解码图片导致的超时风险。原图左上角的
/// "题框风险"角标依赖图片存在才显示，留给集成测试覆盖。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const missingImagePath = '/__non_existent_path__/missing.png';

  QuestionRegion _region({
    String id = 'r1',
    Rect? rect,
    String? text,
    String? questionType,
    List<String> blockTypes = const <String>[],
    List<String> formulas = const <String>[],
    List<String> tables = const <String>[],
  }) {
    return QuestionRegion(
      id: id,
      normalizedRect: rect ?? const Rect.fromLTWH(0.1, 0.1, 0.3, 0.2),
      recognizedText: text,
      recognizedBlockTypes: blockTypes,
      questionType: questionType,
      formulas: formulas,
      tables: tables,
    );
  }

  Widget _wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: child),
        ),
      );

  group('RecognitionEvidencePreview 字段状态', () {
    testWidgets('附件缺失时显示占位文案，字段状态仍渲染', (tester) async {
      final region = _region(text: '一道题目');
      await tester.pumpWidget(_wrap(RecognitionEvidencePreview(
        sourceImagePath: missingImagePath,
        region: region,
        stem: '一道题目',
        formulas: const <String>[],
        tables: const <String>[],
      )));
      await tester.pump();

      expect(find.text('原图附件缺失'), findsOneWidget);
      expect(find.text('题干 · 已识别'), findsOneWidget);
    });

    testWidgets('选项 pill 在非选择题显示"不适用"', (tester) async {
      final region = _region(text: '一道填空题', questionType: '填空题');
      await tester.pumpWidget(_wrap(RecognitionEvidencePreview(
        sourceImagePath: missingImagePath,
        region: region,
        stem: '一道填空题',
        formulas: const <String>[],
        tables: const <String>[],
      )));
      await tester.pump();

      expect(find.text('选项 · 不适用'), findsOneWidget);
      expect(find.text('题干 · 已识别'), findsOneWidget);
      expect(find.text('公式 · 未识别'), findsOneWidget);
      expect(find.text('表格 · 未识别'), findsOneWidget);
      expect(find.text('图形 · 待校对'), findsOneWidget);
    });

    testWidgets('选项 pill 在选择题识别到选项行时显示"已识别"', (tester) async {
      final region = _region(
        text: '一道选择题\nA. 选项一\nB. 选项二',
        questionType: '选择题',
      );
      await tester.pumpWidget(_wrap(RecognitionEvidencePreview(
        sourceImagePath: missingImagePath,
        region: region,
        stem: '一道选择题',
        formulas: const <String>[],
        tables: const <String>[],
      )));
      await tester.pump();

      expect(find.text('选项 · 已识别'), findsOneWidget);
    });

    testWidgets('图形 pill 在 blockTypes 含"图形"时显示"已识别"', (tester) async {
      final region = _region(
        text: '一道题',
        blockTypes: const <String>['图形'],
      );
      await tester.pumpWidget(_wrap(RecognitionEvidencePreview(
        sourceImagePath: missingImagePath,
        region: region,
        stem: '一道题',
        formulas: const <String>[],
        tables: const <String>[],
      )));
      await tester.pump();

      expect(find.text('图形 · 已识别'), findsOneWidget);
    });

    testWidgets('题干为空时显示"待校对"和"暂无题干文字"', (tester) async {
      final region = _region(text: '');
      await tester.pumpWidget(_wrap(RecognitionEvidencePreview(
        sourceImagePath: missingImagePath,
        region: region,
        stem: '',
        formulas: const <String>[],
        tables: const <String>[],
      )));
      await tester.pump();

      expect(find.text('题干 · 待校对'), findsOneWidget);
      expect(find.text('暂无题干文字'), findsOneWidget);
    });
  });

  group('RecognitionEvidencePreview 空间风险合并进对照区', () {
    testWidgets('题框贴边风险在字段状态区下方显示', (tester) async {
      final region = _region(
        rect: const Rect.fromLTWH(0.0, 0.1, 0.3, 0.2),
        text: '一道贴边的题目',
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      await tester.pumpWidget(_wrap(RecognitionEvidencePreview(
        sourceImagePath: missingImagePath,
        region: region,
        stem: '一道贴边的题目',
        formulas: const <String>[],
        tables: const <String>[],
        risks: risks,
      )));
      await tester.pump();

      expect(find.textContaining('题框贴近页面边缘'), findsOneWidget);
    });

    testWidgets('比例异常风险也合并显示', (tester) async {
      final region = _region(
        rect: const Rect.fromLTWH(0.1, 0.45, 0.8, 0.02), // aspect = 40
        text: '过宽的题框',
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      await tester.pumpWidget(_wrap(RecognitionEvidencePreview(
        sourceImagePath: missingImagePath,
        region: region,
        stem: '过宽的题框',
        formulas: const <String>[],
        tables: const <String>[],
        risks: risks,
      )));
      await tester.pump();

      expect(find.textContaining('宽高比异常'), findsOneWidget);
    });

    testWidgets('面积过大风险也合并显示', (tester) async {
      final region = _region(
        rect: const Rect.fromLTWH(0.02, 0.02, 0.96, 0.96),
        text: '过大题框',
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      await tester.pumpWidget(_wrap(RecognitionEvidencePreview(
        sourceImagePath: missingImagePath,
        region: region,
        stem: '过大题框',
        formulas: const <String>[],
        tables: const <String>[],
        risks: risks,
      )));
      await tester.pump();

      expect(find.textContaining('面积过大'), findsOneWidget);
    });

    testWidgets('非空间风险（含公式/表格）不出现在对照区风险行', (tester) async {
      final region = _region(
        text: '题干',
        blockTypes: const <String>['公式'],
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      await tester.pumpWidget(_wrap(RecognitionEvidencePreview(
        sourceImagePath: missingImagePath,
        region: region,
        stem: '题干',
        formulas: const <String>[],
        tables: const <String>[],
        risks: risks,
      )));
      await tester.pump();

      // 「含公式或表格」属于结构风险，不应出现在对照区风险行
      expect(find.textContaining('含公式或表格'), findsNothing);
    });
  });

  group('RecognitionEvidencePreview 展开/收起', () {
    testWidgets('短内容时不显示展开按钮', (tester) async {
      final region = _region(text: '短题干');
      await tester.pumpWidget(_wrap(RecognitionEvidencePreview(
        sourceImagePath: missingImagePath,
        region: region,
        stem: '短题干',
        formulas: const <String>[],
        tables: const <String>[],
      )));
      await tester.pump();

      expect(find.text('展开完整内容'), findsNothing);
      expect(find.text('收起'), findsNothing);
    });

    testWidgets('长题干显示展开按钮，点击后切换为收起', (tester) async {
      final longStem = '这是一段非常长的题干内容，' * 10; // 远超 60 字符
      final region = _region(text: longStem);
      await tester.pumpWidget(_wrap(RecognitionEvidencePreview(
        sourceImagePath: missingImagePath,
        region: region,
        stem: longStem,
        formulas: const <String>[],
        tables: const <String>[],
      )));
      await tester.pump();

      expect(find.text('展开完整内容'), findsOneWidget);

      await tester.tap(find.text('展开完整内容'));
      await tester.pump();

      expect(find.text('收起'), findsOneWidget);
      expect(find.text('展开完整内容'), findsNothing);
    });

    testWidgets('长公式也触发展开按钮', (tester) async {
      const longFormula = '\\frac{a+b+c+d+e+f+g+h+i+j+k+l+m+n+o+p+q+r+s+t}{x+y+z}';
      final region = _region(text: '题干', formulas: const <String>[longFormula]);
      await tester.pumpWidget(_wrap(RecognitionEvidencePreview(
        sourceImagePath: missingImagePath,
        region: region,
        stem: '题干',
        formulas: const <String>[longFormula],
        tables: const <String>[],
      )));
      await tester.pump();

      expect(find.text('展开完整内容'), findsOneWidget);
    });
  });
}

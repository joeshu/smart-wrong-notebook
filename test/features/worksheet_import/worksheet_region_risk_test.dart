import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/features/worksheet_import/presentation/worksheet_region_editor_screen.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/status_pill.dart';

QuestionRegion _region({
  String id = 'r1',
  Rect? rect,
  String? text,
  double confidence = 1,
  QuestionRegionSource source = QuestionRegionSource.manual,
  List<String> blockTypes = const <String>[],
  String? questionType,
  List<String> formulas = const <String>[],
  List<String> tables = const <String>[],
  List<String> options = const <String>[],
  String? diagramNote,
}) {
  return QuestionRegion(
    id: id,
    normalizedRect: rect ?? const Rect.fromLTWH(0.1, 0.1, 0.3, 0.2),
    recognizedText: text,
    confidence: confidence,
    source: source,
    recognizedBlockTypes: blockTypes,
    questionType: questionType,
    formulas: formulas,
    tables: tables,
    options: options,
    diagramNote: diagramNote,
  );
}

void main() {
  group('FieldStatus 四态统一', () {
    testWidgets('StatusPill 渲染各状态文案与配色', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                StatusPill(label: '题干', status: FieldStatus.recognized),
                StatusPill(label: '公式', status: FieldStatus.needsReview),
                StatusPill(label: '选项', status: FieldStatus.missing),
                StatusPill(label: '图形', status: FieldStatus.notApplicable),
              ],
            ),
          ),
        ),
      );

      expect(find.text('题干 · 已识别'), findsOneWidget);
      expect(find.text('公式 · 待校对'), findsOneWidget);
      expect(find.text('选项 · 未识别'), findsOneWidget);
      expect(find.text('图形 · 不适用'), findsOneWidget);
    });

    test('FieldStatus.label 文案固定为四态', () {
      expect(FieldStatus.recognized.label, '已识别');
      expect(FieldStatus.missing.label, '未识别');
      expect(FieldStatus.needsReview.label, '待校对');
      expect(FieldStatus.notApplicable.label, '不适用');
    });

    test('FieldStatus 配色不重复且非透明', () {
      final statuses = FieldStatus.values;
      final bgColors = statuses.map((s) => s.backgroundColor).toSet();
      final fgColors = statuses.map((s) => s.foregroundColor).toSet();
      expect(bgColors.length, statuses.length, reason: '背景色应四态各不相同');
      expect(fgColors.length, statuses.length, reason: '前景色应四态各不相同');
    });
  });

  group('detectQuestionRegionRisks 题框风险检测', () {
    test('空题干提示待校对', () {
      final region = _region(text: '   ');
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks, contains('未识别到题干文字'));
    });

    test('题框宽高比异常（过宽）', () {
      final region = _region(
        rect: const Rect.fromLTWH(0.1, 0.45, 0.8, 0.02), // aspect = 40
        text: '题干',
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks.any((m) => m.contains('宽高比异常')), isTrue);
    });

    test('题框宽高比异常（过高）', () {
      final region = _region(
        rect: const Rect.fromLTWH(0.45, 0.05, 0.02, 0.9), // aspect = 0.022
        text: '题干',
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks.any((m) => m.contains('宽高比异常')), isTrue);
    });

    test('题框占整页面积过大', () {
      final region = _region(
        rect: const Rect.fromLTWH(0.02, 0.02, 0.96, 0.96), // area ≈ 0.92
        text: '题干',
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks, contains('题框占整页面积过大，可能包含多题'));
    });

    test('题框面积过小', () {
      final region = _region(
        rect: const Rect.fromLTWH(0.5, 0.5, 0.04, 0.04), // area = 0.0016
        text: '题干',
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks, contains('题框面积过小，可能只截到单字或符号'));
    });

    test('题框贴近页面边缘', () {
      final region = _region(
        rect: const Rect.fromLTWH(0.0, 0.1, 0.3, 0.2), // left = 0
        text: '题干',
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks, contains('题框贴近页面边缘，可能被截断'));
    });

    test('与其它题框重叠', () {
      final r1 = _region(
        id: 'r1',
        rect: const Rect.fromLTWH(0.1, 0.1, 0.4, 0.4),
        text: '题干1',
      );
      final r2 = _region(
        id: 'r2',
        rect: const Rect.fromLTWH(0.2, 0.2, 0.4, 0.4), // 与 r1 大面积重叠
        text: '题干2',
      );
      final risks = detectQuestionRegionRisks(r1, <QuestionRegion>[r1, r2], index: 0);
      expect(risks.any((m) => m.contains('题框重叠')), isTrue);
    });

    test('含公式且公式完整 → 含公式提示核对格式', () {
      final region = _region(
        text: '题干',
        blockTypes: const <String>['公式'],
        formulas: const <String>[r'$x^2 + y^2 = r^2$'],
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks, contains('含公式或表格，建议核对格式'));
      expect(risks.any((m) => m.contains('公式格式异常')), isFalse);
    });

    test('含表格且表格完整 → 含表格提示核对格式', () {
      final region = _region(
        text: '题干',
        blockTypes: const <String>['表格'],
        tables: const <String>['| a | b |\n|---|---|\n| 1 | 2 |'],
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks, contains('含公式或表格，建议核对格式'));
      expect(risks.any((m) => m.contains('表格格式异常')), isFalse);
    });

    test('含公式块但公式列表为空 → 公式格式异常', () {
      final region = _region(text: '题干', blockTypes: const <String>['公式']);
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks.any((m) => m.contains('公式格式异常')), isTrue);
      // 不应同时出现"含公式或表格"的冗余提示
      expect(risks, isNot(contains('含公式或表格，建议核对格式')));
    });

    test('公式缺少 LaTex 标记 → 公式格式异常', () {
      final region = _region(
        text: '题干',
        formulas: const <String>['x^2 + y^2'],  // 没有 $...$ 或 \(...\)
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks.any((m) => m.contains('公式格式异常')), isTrue);
    });

    test('表格 Markdown 缺分隔行 → 表格格式异常', () {
      final region = _region(
        text: '题干',
        tables: const <String>['| a | b |\n| 1 | 2 |'],  // 缺 |---|---|
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks.any((m) => m.contains('表格格式异常')), isTrue);
    });

    test('表格 Markdown 列数不一致 → 表格格式异常', () {
      final region = _region(
        text: '题干',
        tables: const <String>['| a | b |\n|---|---|\n| 1 | 2 | 3 |'],  // 第三行列多
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks.any((m) => m.contains('表格格式异常')), isTrue);
    });

    test('题型为选择题但无选项行 → 选项缺失风险', () {
      final region = _region(
        text: '一道选择题但没有选项',
        questionType: '选择题',
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks, contains('题型为选择题但未识别到选项行，请补选项'));
    });

    test('识别到选项块但无选项行 → 选项缺失风险', () {
      final region = _region(
        text: '题干无选项',
        blockTypes: const <String>['选项'],
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks, contains('识别到选项块但未提取到选项行，建议校对'));
    });

    test('低可信度布局模型识别提示校对', () {
      final region = _region(
        text: '题干',
        confidence: 0.4,
        source: QuestionRegionSource.layoutModel,
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks, contains('识别可信度较低，建议校对'));
    });

    test('正常题框无风险', () {
      final region = _region(
        rect: const Rect.fromLTWH(0.1, 0.1, 0.3, 0.2),
        text: '一道正常的题目',
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks, isEmpty);
    });

    test('手动框选低可信度不触发（仅布局模型触发）', () {
      final region = _region(
        text: '题干',
        confidence: 0.3,
        source: QuestionRegionSource.manual,
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks, isNot(contains('识别可信度较低，建议校对')));
    });
  });

  group('recognitionFieldStatus 单题字段四态判定', () {
    test('题干：空 → 待校对，非空 → 已识别', () {
      expect(
        recognitionFieldStatus('题干', _region(text: '   ')),
        FieldStatus.needsReview,
      );
      expect(
        recognitionFieldStatus('题干', _region(text: '一道题目')),
        FieldStatus.recognized,
      );
    });

    test('题干：stemOverride 优先于 region.recognizedText', () {
      final region = _region(text: '原文');
      expect(
        recognitionFieldStatus('题干', region, stemOverride: '  '),
        FieldStatus.needsReview,
      );
      expect(
        recognitionFieldStatus('题干', region, stemOverride: '校对后题干'),
        FieldStatus.recognized,
      );
    });

    test('公式：formulas 非空或 blockTypes 含"公式" → 已识别，否则未识别', () {
      expect(
        recognitionFieldStatus('公式', _region(text: '题干')),
        FieldStatus.missing,
      );
      expect(
        recognitionFieldStatus('公式', _region(text: '题干', formulas: const <String>['x^2'])),
        FieldStatus.recognized,
      );
      expect(
        recognitionFieldStatus('公式', _region(text: '题干', blockTypes: const <String>['公式'])),
        FieldStatus.recognized,
      );
    });

    test('表格：tables 非空或 blockTypes 含"表格" → 已识别，否则未识别', () {
      expect(
        recognitionFieldStatus('表格', _region(text: '题干')),
        FieldStatus.missing,
      );
      expect(
        recognitionFieldStatus('表格', _region(text: '题干', tables: const <String>['| a | b |'])),
        FieldStatus.recognized,
      );
    });

    test('选项：非选择题 → 不适用', () {
      expect(
        recognitionFieldStatus('选项', _region(text: '题干', questionType: '填空题')),
        FieldStatus.notApplicable,
      );
      expect(
        recognitionFieldStatus('选项', _region(text: '题干', questionType: '计算题')),
        FieldStatus.notApplicable,
      );
    });

    test('选项：选择题未识别到选项行 → 待校对', () {
      final region = _region(text: '一道选择题但没有选项', questionType: '选择题');
      expect(recognitionFieldStatus('选项', region), FieldStatus.needsReview);
    });

    test('选项：选择题识别到 A.B.C. 选项行 → 已识别', () {
      final region = _region(
        text: '一道选择题\nA. 选项一\nB. 选项二',
        questionType: '选择题',
      );
      expect(recognitionFieldStatus('选项', region), FieldStatus.recognized);
    });

    test('选项：题型未指定时按选项行判定', () {
      expect(
        recognitionFieldStatus('选项', _region(text: '无选项文本')),
        FieldStatus.needsReview,
      );
      expect(
        recognitionFieldStatus('选项', _region(text: 'A. 选项一\nB. 选项二')),
        FieldStatus.recognized,
      );
    });

    test('选项：题型为"未指定"按选项行判定（不视为非选择题）', () {
      expect(
        recognitionFieldStatus('选项', _region(text: 'A. 选项', questionType: '未指定')),
        FieldStatus.recognized,
      );
    });

    test('图形：blockTypes 含"图形"/"diagram" → 已识别，否则待校对', () {
      expect(
        recognitionFieldStatus('图形', _region(text: '题干')),
        FieldStatus.needsReview,
      );
      expect(
        recognitionFieldStatus('图形', _region(text: '题干', blockTypes: const <String>['图形'])),
        FieldStatus.recognized,
      );
      expect(
        recognitionFieldStatus('图形', _region(text: '题干', blockTypes: const <String>['diagram'])),
        FieldStatus.recognized,
      );
    });

    test('选项：用户已显式编辑过 options → 已校对（与自动解析区分）', () {
      final region = _region(
        text: '题干',
        questionType: '选择题',
        options: const <String>['A. 红色', 'B. 蓝色'],
      );
      expect(recognitionFieldStatus('选项', region), FieldStatus.edited);
    });

    test('图形：已填写 diagramNote → 已校对（人工核对完成）', () {
      expect(
        recognitionFieldStatus('图形',
            _region(text: '题干', blockTypes: const <String>['图形'], diagramNote: '直角三角形 ABC')),
        FieldStatus.edited,
      );
      // 没有图形块但已填备注（用户主动添加备注的场景）也算已校对
      expect(
        recognitionFieldStatus('图形',
            _region(text: '题干', diagramNote: '函数图像 y=x^2')),
        FieldStatus.edited,
      );
      // 空白备注视为未填写
      expect(
        recognitionFieldStatus('图形',
            _region(text: '题干', blockTypes: const <String>['图形'], diagramNote: '   ')),
        FieldStatus.recognized,
      );
    });
  });

  group('专用识别状态风险', () {
    test('待专用识别块要求人工校对', () {
      const region = QuestionRegion(
        id: 'handwriting',
        normalizedRect: Rect.fromLTWH(.1, .1, .8, .3),
        recognizedText: '题干',
        documentBlocks: <DocumentBlock>[
          DocumentBlock(
            type: DocumentBlockType.handwriting,
            content: '',
            recognitionEngine: DocumentRecognitionEngine.handwritingOcr,
            recognitionStatus: DocumentRecognitionStatus.needsSpecialist,
            sourceCropRef: 'crop://page?left=.1',
          ),
        ],
      );

      expect(
        detectQuestionRegionRisks(region, const <QuestionRegion>[region]),
        contains('手写或专用内容尚未完成识别，请查看原图并校对文字'),
      );
    });
  });

  group('选项行解析与规范化', () {
    test('parseOptionLines 从 recognizedText 提取选项行', () {
      expect(parseOptionLines(null), isEmpty);
      expect(parseOptionLines(''), isEmpty);
      expect(parseOptionLines('题干\nA. 选项一\nB. 选项二'),
          <String>['A. 选项一', 'B. 选项二']);
      // 支持中文顿号、半角句号
      expect(parseOptionLines('A、第一项\nB．第二项'),
          <String>['A. 第一项', 'B. 第二项']);
      // 非选项行被忽略
      expect(parseOptionLines('题干\n解答\nA. 选项一'),
          <String>['A. 选项一']);
    });

    test('normalizeOptions 自动补 A./B./C./D. 前缀', () {
      expect(normalizeOptions('红色\n蓝色\n绿色'),
          <String>['A. 红色', 'B. 蓝色', 'C. 绿色']);
      // 已有前缀的保留原字母
      expect(normalizeOptions('A. 红色\nB. 蓝色'),
          <String>['A. 红色', 'B. 蓝色']);
      // 空行被过滤
      expect(normalizeOptions('红色\n\n蓝色'),
          <String>['A. 红色', 'B. 蓝色']);
      // 全空 → 空列表（用于清空 options）
      expect(normalizeOptions('  \n  '), isEmpty);
    });

    test('hasOptionLine 与 parseOptionLines 一致性', () {
      // 有选项行时两者都为 true/非空
      const text = '题干\nA. 选项一\nB. 选项二';
      expect(hasOptionLine(text), isTrue);
      expect(parseOptionLines(text), hasLength(2));
      // 无选项行时两者都为 false/空
      const noOption = '题干没有选项';
      expect(hasOptionLine(noOption), isFalse);
      expect(parseOptionLines(noOption), isEmpty);
    });
  });
}

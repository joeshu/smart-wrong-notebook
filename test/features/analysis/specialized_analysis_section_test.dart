import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/specialized_analysis.dart';
import 'package:smart_wrong_notebook/src/features/analysis/presentation/specialized_analysis_section.dart';

void main() {
  Future<void> pumpSection(
    WidgetTester tester,
    SpecializedAnalysis analysis,
  ) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SpecializedAnalysisSection(analysis: analysis),
          ),
        ),
      ));

  testWidgets('equation workbench shows transformations and verification',
      (tester) async {
    await pumpSection(
      tester,
      const SpecializedAnalysis(
        profile: AnalysisProfile.equationSystem,
        givens: <String>['x+y=5', 'x-y=1'],
        goal: '求 x、y',
        constraints: <String>['x、y 为实数'],
        reasoningSteps: <SpecializedReasoningStep>[
          SpecializedReasoningStep(
            index: 1,
            statement: '两式相加得 2x=6',
          ),
        ],
        verification: <String>['代回：3+2=5，3-2=1'],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('方程组解析'), findsOneWidget);
    expect(find.text('等价变形过程'), findsOneWidget);
    expect(find.text('代回验证'), findsOneWidget);
    expect(find.byKey(const Key('specialized-equation-verification')),
        findsOneWidget);
  });

  testWidgets('geometry workbench exposes entities relations and theorem basis',
      (tester) async {
    await pumpSection(
      tester,
      const SpecializedAnalysis(
        profile: AnalysisProfile.geometry,
        givens: <String>['AB=AC'],
        goal: '求∠B',
        entities: <String>['A', 'B', 'C', '三角形'],
        relations: <String>['AB=AC', '∠B=∠C'],
        reasoningSteps: <SpecializedReasoningStep>[
          SpecializedReasoningStep(
            index: 1,
            statement: '∠B=∠C',
            basis: '等腰三角形底角相等',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('几何解析'), findsOneWidget);
    expect(find.text('图形对象'), findsOneWidget);
    expect(find.text('几何关系'), findsOneWidget);
    expect(find.text('依据：等腰三角形底角相等'), findsOneWidget);
  });

  testWidgets('proof workbench makes missing basis visibly reviewable',
      (tester) async {
    await pumpSection(
      tester,
      const SpecializedAnalysis(
        profile: AnalysisProfile.proofArgument,
        goal: '证明结论成立',
        reasoningSteps: <SpecializedReasoningStep>[
          SpecializedReasoningStep(index: 1, statement: '所以结论成立'),
        ],
        risks: <String>['第 1 步缺少推理依据'],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('证明审查'), findsOneWidget);
    expect(find.text('依据待补充'), findsOneWidget);
    expect(find.text('需要核对'), findsOneWidget);
    expect(find.byKey(const Key('specialized-risk-block')), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/specialized_analysis.dart';

void main() {
  const classifier = AnalysisProfileClassifier();

  test('classifies equation system before generic equation', () {
    expect(
      classifier.classify(r'解方程组：\begin{cases}x+y=5\\x-y=1\end{cases}'),
      AnalysisProfile.equationSystem,
    );
  });

  test('classifies geometry proof as geometry workbench', () {
    expect(
      classifier.classify('在三角形 ABC 中，AB=AC，证明∠B=∠C'),
      AnalysisProfile.geometry,
    );
  });

  test('classifies non-geometric proof separately', () {
    expect(
      classifier.classify('已知 n 为偶数，证明 n² 也是偶数'),
      AnalysisProfile.proofArgument,
    );
  });

  test('enricher creates conservative equation view and flags verification', () {
    final analysis = const SpecializedAnalysisEnricher().enrich(
      questionText: '解方程 x+1=4',
      solutionSteps: const <String>['移项得 x=3'],
    );

    expect(analysis?.profile, AnalysisProfile.algebraEquation);
    expect(analysis?.isModelProvided, isFalse);
    expect(analysis?.reasoningSteps.single.statement, '移项得 x=3');
    expect(analysis?.risks, contains(contains('代回验证')));
  });

  test('model-provided proof keeps basis and survives json roundtrip', () {
    const original = SpecializedAnalysis(
      profile: AnalysisProfile.proofArgument,
      givens: <String>['n=2k'],
      goal: '证明 n² 为偶数',
      reasoningSteps: <SpecializedReasoningStep>[
        SpecializedReasoningStep(
          index: 1,
          statement: 'n²=4k²=2(2k²)',
          basis: '偶数定义',
        ),
      ],
      verification: <String>['结论符合偶数定义'],
    );

    final restored = SpecializedAnalysis.fromJson(original.toJson());

    expect(restored.profile, AnalysisProfile.proofArgument);
    expect(restored.reasoningSteps.single.basis, '偶数定义');
    expect(restored.risks, isEmpty);
  });
}

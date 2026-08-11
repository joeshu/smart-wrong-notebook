import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/domain/services/recognition_confirmation_policy.dart';

QuestionRegion _region({
  double confidence = .95,
  String text = '已识别题干',
  Set<String> confirmed = const <String>{},
}) =>
    QuestionRegion(
      id: 'r1',
      normalizedRect: const Rect.fromLTWH(.1, .1, .8, .3),
      recognizedText: text,
      confidence: confidence,
      source: QuestionRegionSource.layoutModel,
      confirmedFields: confirmed,
    );

void main() {
  const policy = RecognitionConfirmationPolicy();

  test('capture risk classifier uses stable codes', () {
    expect(
      RecognitionRiskClassifier.classify('题目主体存在遮挡，建议重拍'),
      RecognitionRiskCode.captureOcclusion,
    );
    expect(
      RecognitionRiskClassifier.classify('页眉可能包含姓名或学校'),
      RecognitionRiskCode.privacyReview,
    );
    expect(
      RecognitionRiskClassifier.classify('页面有反光和阴影'),
      RecognitionRiskCode.captureLighting,
    );
  });

  test('occlusion and capture cut-off are hard blocks', () {
    expect(
      policy.evaluateQuestion(
        confidence: .99,
        stem: '完整题干',
        options: '',
        studentAnswer: '',
        imageAvailable: true,
        risks: const <String>['题目主体存在遮挡'],
      ).decision,
      RecognitionConfirmationDecision.hardBlock,
    );
    expect(
      policy.evaluateQuestion(
        confidence: .99,
        stem: '完整题干',
        options: '',
        studentAnswer: '',
        imageAvailable: true,
        risks: const <String>['内容截断，题目未拍全'],
      ).decision,
      RecognitionConfirmationDecision.hardBlock,
    );
  });

  test('legacy risk copy maps to stable internal codes', () {
    expect(
      RecognitionRiskClassifier.classify('题框贴近页面边缘，可能被截断'),
      RecognitionRiskCode.spatialEdge,
    );
    expect(
      RecognitionRiskClassifier.classify('公式格式异常'),
      RecognitionRiskCode.formula,
    );
    expect(
      RecognitionRiskClassifier.classify('含公式或表格，建议核对格式'),
      RecognitionRiskCode.formulaAndTable,
    );
  });

  test('auto confirm only accepts high-confidence risk-free question', () {
    expect(policy.canAutoConfirm(_region(), const <String>[]), isTrue);
    expect(policy.canAutoConfirm(_region(confidence: .7), const <String>[]), isFalse);
    expect(policy.canAutoConfirm(_region(), const <String>['公式可能损坏']), isFalse);
    expect(policy.canAutoConfirm(_region(text: ''), const <String>[]), isFalse);
  });

  test('low confidence requires explicit stem confirmation', () {
    final low = _region(confidence: .6);
    expect(policy.canProceed(low, const <String>[]), isFalse);
    expect(
      policy.canProceed(
        _region(
          confidence: .6,
          confirmed: const <String>{RecognitionReviewField.stem},
        ),
        const <String>[],
      ),
      isTrue,
    );
  });

  test('structural fields are confirmed independently', () {
    const risks = <String>['公式可能损坏', '选择题缺少选项'];
    expect(
      policy.fieldsRequiringConfirmation(_region(), risks),
      containsAll(<String>[
        RecognitionReviewField.formulas,
        RecognitionReviewField.options,
      ]),
    );
    expect(
      policy.canProceed(
        _region(confirmed: const <String>{
          RecognitionReviewField.formulas,
          RecognitionReviewField.options,
        }),
        risks,
      ),
      isTrue,
    );
  });

  test('spatial risk cannot be bypassed by field confirmation', () {
    expect(
      policy.canProceed(
        _region(confirmed: RecognitionReviewField.all),
        const <String>['题框贴边'],
      ),
      isFalse,
    );
  });

  test('single-question flow shares confidence and structural-risk rules', () {
    expect(
      policy.fieldsRequiringQuestionConfirmation(
        confidence: .84,
        stem: '题干',
        options: 'A. 选项',
        studentAnswer: 'A',
        risks: const <String>['公式可能损坏'],
      ),
      containsAll(<String>[
        RecognitionReviewField.stem,
        RecognitionReviewField.options,
        RecognitionReviewField.studentAnswer,
        RecognitionReviewField.formulas,
      ]),
    );
    expect(
      policy.canAutoConfirmQuestion(
        confidence: .95,
        stem: '题干',
        imageAvailable: true,
        risks: const <String>['公式可能损坏'],
      ),
      isFalse,
    );
  });

  test('missing confidence is never treated as accurate', () {
    expect(
      policy.fieldsRequiringQuestionConfirmation(
        confidence: null,
        stem: '题干',
        options: '',
        studentAnswer: '',
      ),
      contains(RecognitionReviewField.stem),
    );
  });

  test('incomplete candidate and answer signals require their own fields', () {
    final required = policy.fieldsRequiringQuestionConfirmation(
      confidence: .95,
      stem: '题干',
      options: '',
      studentAnswer: '',
      risks: const <String>['选择题候选不完整', '作答区域可能缺失'],
    );
    expect(required, containsAll(<String>[
      RecognitionReviewField.options,
      RecognitionReviewField.studentAnswer,
    ]));
  });

  test('missing source image never qualifies for automatic confirmation', () {
    expect(
      policy.canAutoConfirmQuestion(
        confidence: .99,
        stem: '题干',
        imageAvailable: false,
      ),
      isFalse,
    );
  });

  test('missing source image blocks continuation after field confirmation', () {
    expect(
      policy.canProceedQuestion(
        confidence: .99,
        stem: '题干',
        options: '',
        studentAnswer: '',
        confirmedFields: RecognitionReviewField.all,
        imageAvailable: false,
      ),
      isFalse,
    );
  });

  test('spatial risk blocks single-question continuation', () {
    expect(
      policy.canProceedQuestion(
        confidence: .95,
        stem: '题干',
        options: '',
        studentAnswer: '',
        confirmedFields: RecognitionReviewField.all,
        risks: const <String>['题框倾斜且贴边'],
      ),
      isFalse,
    );
  });

  test('evaluation exposes the matrix decision and keeps field union', () {
    expect(
      policy.evaluateRegion(_region(), const <String>[]).decision,
      RecognitionConfirmationDecision.autoPass,
    );
    final review = policy.evaluateRegion(
      _region(confidence: .6),
      const <String>['公式可能损坏', '选择题候选不完整'],
    );
    expect(review.decision, RecognitionConfirmationDecision.mustConfirm);
    expect(review.requiredFields, containsAll(<String>[
      RecognitionReviewField.stem,
      RecognitionReviewField.formulas,
      RecognitionReviewField.options,
    ]));
    expect(
      policy.evaluateRegion(_region(), const <String>['题框重叠']).decision,
      RecognitionConfirmationDecision.hardBlock,
    );
  });

  test('single-question evaluation treats missing confidence as confirmation', () {
    final result = policy.evaluateQuestion(
      confidence: null,
      stem: '题干',
      options: '',
      studentAnswer: '',
      imageAvailable: true,
    );
    expect(result.decision, RecognitionConfirmationDecision.mustConfirm);
    expect(result.requiredFields, contains(RecognitionReviewField.stem));
  });

  test('ignore-only quality prompts remain non-blocking but are not auto-pass', () {
    final result = policy.evaluateRegion(
      _region(),
      const <String>['图像质量提示：建议重拍'],
    );
    expect(result.decision, RecognitionConfirmationDecision.ignorePrompt);
    expect(policy.canAutoConfirm(_region(), const <String>['图像质量提示：建议重拍']), isFalse);
  });

  test('missing image requires confirmation even when text is otherwise safe', () {
    final result = policy.evaluateQuestion(
      confidence: .99,
      stem: '题干',
      options: '',
      studentAnswer: '',
      imageAvailable: false,
    );
    expect(result.decision, RecognitionConfirmationDecision.mustConfirm);
    expect(result.requiredFields, isEmpty);
  });

  test('hard block retains field findings for repair after spatial correction', () {
    final result = policy.evaluateRegion(
      _region(),
      const <String>['题框重叠', '公式可能损坏', '选择题候选不完整'],
    );
    expect(result.decision, RecognitionConfirmationDecision.hardBlock);
    expect(result.requiredFields, containsAll(<String>[
      RecognitionReviewField.formulas,
      RecognitionReviewField.options,
    ]));
  });

  test('ignored candidates are hard blocked regardless of confirmation fields', () {
    final result = policy.evaluateRegion(
      _region(confirmed: RecognitionReviewField.all).copyWith(
        reviewStatus: QuestionRegionReviewStatus.ignored,
      ),
      const <String>[],
    );
    expect(result.decision, RecognitionConfirmationDecision.hardBlock);
  });

  test('normal high-quality region auto-passes independently of confidence accuracy', () {
    final result = policy.evaluateRegion(_region(confidence: .86), const <String>[]);

    expect(result.decision, RecognitionConfirmationDecision.autoPass);
    expect(result.requiredFields, isEmpty);
  });

  test('empty stem requires confirmation even when confidence is high', () {
    final result = policy.evaluateQuestion(
      confidence: .99,
      stem: '  ',
      options: '',
      studentAnswer: '',
      imageAvailable: true,
    );

    expect(result.decision, RecognitionConfirmationDecision.mustConfirm);
    expect(result.requiredFields, contains(RecognitionReviewField.stem));
  });

  test('formula and table warnings distinguish complete from damaged structure', () {
    final complete = policy.evaluateRegion(
      _region(),
      const <String>['含公式或表格，建议核对格式'],
    );
    final damaged = policy.evaluateRegion(
      _region(),
      const <String>['公式格式异常', '表格格式异常'],
    );

    expect(complete.decision, RecognitionConfirmationDecision.mustConfirm);
    expect(complete.requiredFields, contains(RecognitionReviewField.formulas));
    expect(damaged.decision, RecognitionConfirmationDecision.mustConfirm);
    expect(damaged.requiredFields, containsAll(<String>[
      RecognitionReviewField.formulas,
      RecognitionReviewField.tables,
    ]));
  });

  test('blur and tilted or cropped risks cannot be silently auto-passed', () {
    final blur = policy.evaluateQuestion(
      confidence: .99,
      stem: '题干',
      options: '',
      studentAnswer: '',
      imageAvailable: true,
      risks: const <String>['图像可能模糊'],
    );
    final spatial = policy.evaluateQuestion(
      confidence: .99,
      stem: '题干',
      options: '',
      studentAnswer: '',
      imageAvailable: true,
      risks: const <String>['题框倾斜且贴边'],
    );

    expect(blur.decision, RecognitionConfirmationDecision.mustConfirm);
    expect(spatial.decision, RecognitionConfirmationDecision.hardBlock);
  });

  test('confirming all required fields enables continuation after recoverable risks', () {
    const risks = <String>['公式格式异常', '选择题候选不完整'];
    final required = policy.fieldsRequiringQuestionConfirmation(
      confidence: .95,
      stem: '题干',
      options: 'A. 选项',
      studentAnswer: '',
      risks: risks,
    );

    expect(required, containsAll(<String>[
      RecognitionReviewField.formulas,
      RecognitionReviewField.options,
    ]));
    expect(policy.canProceedQuestion(
      confidence: .95,
      stem: '题干',
      options: 'A. 选项',
      studentAnswer: '',
      confirmedFields: required,
      risks: risks,
    ), isTrue);
    expect(policy.canProceedQuestion(
      confidence: .95,
      stem: '题干',
      options: 'A. 选项',
      studentAnswer: '',
      confirmedFields: const <String>{RecognitionReviewField.formulas},
      risks: risks,
    ), isFalse);
  });

  test('ignore-only prompt is the only non-blocking warning outcome', () {
    final result = policy.evaluateRegion(
      _region(),
      const <String>['图片质量提示：建议重拍'],
    );

    expect(result.decision, RecognitionConfirmationDecision.ignorePrompt);
    expect(policy.canProceed(_region(), const <String>['图片质量提示：建议重拍']), isTrue);
  });

  test('assembly, author role and specialist block risks require separate confirmation', () {
    const risks = <String>[
      '跨栏内容阅读顺序不确定，请核对内容块顺序',
      '题干、学生作答或教师批改角色不确定，请逐块确认',
      '手写或专用内容尚未完成识别，请查看原图并校对文字',
    ];
    final required = policy.fieldsRequiringConfirmation(_region(), risks);
    expect(required, containsAll(<String>[
      RecognitionReviewField.questionAssembly,
      RecognitionReviewField.authorRoles,
      RecognitionReviewField.specialistBlocks,
    ]));
    expect(policy.canProceed(_region(), risks), isFalse);
    expect(policy.canProceed(
      _region().copyWith(confirmedFields: required),
      risks,
    ), isTrue);
  });
}

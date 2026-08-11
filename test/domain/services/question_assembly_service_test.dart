import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/domain/services/question_assembly_service.dart';

QuestionRegion _region(String id, double x, double y, {String? number,
    List<DocumentBlock> blocks = const <DocumentBlock>[]}) => QuestionRegion(
  id: id,
  normalizedRect: Rect.fromLTWH(x, y, .35, .12),
  detectedNumber: number,
  documentBlocks: blocks,
);

void main() {
  const service = QuestionAssemblyService();

  test('two-column page is ordered down the left then down the right', () {
    final result = service.assemble(<QuestionRegion>[
      _region('r2', .58, .1),
      _region('l2', .05, .5),
      _region('r1', .58, .4),
      _region('l1', .05, .1),
    ]);
    expect(result.columnCount, 2);
    expect(result.regions.map((r) => r.id), <String>['l1', 'l2', 'r2', 'r1']);
    expect(result.regions.map((r) => r.readingOrder), <int>[0, 1, 2, 3]);
  });

  test('sub-question is attached to preceding major question', () {
    final result = service.assemble(<QuestionRegion>[
      _region('major', .1, .1, number: '12'),
      _region('child', .1, .3, number: '（1）'),
    ]);
    expect(result.regions.last.parentRegionId, 'major');
    expect(result.regions.last.assemblyRiskCodes,
        isNot(contains(QuestionAssemblyRiskCode.parentQuestionUncertain)));
  });

  test('orphan sub-question remains visible as confirmation risk', () {
    final result = service.assemble(<QuestionRegion>[
      _region('child', .1, .1, number: '(1)'),
    ]);
    expect(result.regions.single.parentRegionId, isNull);
    expect(result.regions.single.assemblyRiskCodes,
        contains(QuestionAssemblyRiskCode.parentQuestionUncertain));
  });

  test('author confirmation clears uncertainty and retry chooses specialist', () {
    const block = DocumentBlock(
      type: DocumentBlockType.handwriting,
      content: 'x=2',
      riskCodes: <DocumentBlockRiskCode>{DocumentBlockRiskCode.roleUncertain},
      recognitionStatus: DocumentRecognitionStatus.failed,
      sourceCropRef: 'crop://b1',
    );
    final confirmed = service.confirmAuthorRole(block, DocumentAuthorRole.studentAnswer);
    final retry = service.requestSpecialistRetry(confirmed);
    expect(confirmed.authorRole, DocumentAuthorRole.studentAnswer);
    expect(confirmed.riskCodes, isNot(contains(DocumentBlockRiskCode.roleUncertain)));
    expect(retry.recognitionEngine, DocumentRecognitionEngine.handwritingOcr);
    expect(retry.recognitionStatus, DocumentRecognitionStatus.needsSpecialist);
  });
}

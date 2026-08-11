import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/domain/services/recognition_page_router.dart';

QuestionRegion _region(String id, {List<DocumentBlock> blocks = const <DocumentBlock>[]}) =>
    QuestionRegion(
      id: id,
      normalizedRect: const Rect.fromLTWH(.1, .1, .8, .3),
      documentBlocks: blocks,
    );

void main() {
  const router = RecognitionPageRouter();

  test('teacher marks route page to marked worksheet', () {
    final document = router.route(documentId: 'page-1', regions: <QuestionRegion>[
      _region('q1', blocks: const <DocumentBlock>[
        DocumentBlock(
          type: DocumentBlockType.answerMark,
          content: '×',
          authorRole: DocumentAuthorRole.teacherMark,
        ),
      ]),
    ]);

    expect(document.pageType, RecognitionPageType.markedWorksheet);
    expect(document.routingConfidence, .9);
  });

  test('multiple regions route to multi-question page', () {
    final document = router.route(
      documentId: 'page-2',
      regions: <QuestionRegion>[_region('q1'), _region('q2')],
    );
    expect(document.pageType, RecognitionPageType.multiQuestionPage);
  });

  test('explicit screenshot source takes precedence over content heuristics', () {
    final document = router.route(
      documentId: 'shot',
      sourceType: RecognitionSourceType.screenshot,
      regions: <QuestionRegion>[_region('q1'), _region('q2')],
    );
    expect(document.pageType, RecognitionPageType.screenshot);
  });

  test('empty evidence remains unknown instead of inventing a page type', () {
    final document = router.route(documentId: 'empty', regions: const <QuestionRegion>[]);
    expect(document.pageType, RecognitionPageType.unknown);
    expect(document.routingConfidence, lessThan(.5));
  });
}

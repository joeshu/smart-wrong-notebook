import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

void main() {
  QuestionRegion region() => const QuestionRegion(
    id: 'q1',
    normalizedRect: Rect.fromLTWH(.1, .2, .5, .3),
    recognizedText: '原始题干\n\$x+y\$',
    originalRecognizedText: '原始题干\n\$x+y\$',
    questionStem: '校对后的题干',
    formulas: <String>['\$x+y\$'],
    tables: <String>['|A|B|\n|-|-|\n|1|2|'],
    subject: Subject.math,
  );

  test('copyWith keeps structured content while updating review status', () {
    final ignored = region().copyWith(
      reviewStatus: QuestionRegionReviewStatus.ignored,
    );

    expect(ignored.reviewStatus, QuestionRegionReviewStatus.ignored);
    expect(ignored.originalRecognizedText, '原始题干\n\$x+y\$');
    expect(ignored.questionStem, '校对后的题干');
    expect(ignored.formulas, <String>['\$x+y\$']);
    expect(ignored.tables, hasLength(1));
  });

  test('copyWith restores structured draft to original recognition text', () {
    final restored = region().copyWith(
      questionStem: '原始题干\n\$x+y\$',
      formulas: const <String>[],
      tables: const <String>[],
      recognizedText: '原始题干\n\$x+y\$',
      reviewStatus: QuestionRegionReviewStatus.accepted,
    );

    expect(restored.reviewStatus, QuestionRegionReviewStatus.accepted);
    expect(restored.recognizedText, restored.originalRecognizedText);
    expect(restored.formulas, isEmpty);
    expect(restored.tables, isEmpty);
  });

  test('copyWith preserves ordered document blocks', () {
    final ordered = region().copyWith(documentBlocks: const <DocumentBlock>[
      DocumentBlock(type: DocumentBlockType.text, content: '题干第一段'),
      DocumentBlock(type: DocumentBlockType.formula, content: r'$a^2+b^2$'),
      DocumentBlock(type: DocumentBlockType.text, content: '解释文字'),
      DocumentBlock(type: DocumentBlockType.table, content: '|A|B|'),
    ]);

    expect(ordered.documentBlocks.map((block) => block.type), <DocumentBlockType>[
      DocumentBlockType.text,
      DocumentBlockType.formula,
      DocumentBlockType.text,
      DocumentBlockType.table,
    ]);
    expect(ordered.documentBlocks[2].content, '解释文字');
  });

  test('document block preserves spatial evidence and author metadata', () {
    const block = DocumentBlock(
      id: 'b1',
      type: DocumentBlockType.handwriting,
      content: 'x=2',
      polygon: <Offset>[Offset(.1, .2), Offset(.4, .2), Offset(.4, .3)],
      authorRole: DocumentAuthorRole.studentAnswer,
      inkColor: 'blue',
      confidence: .82,
      riskCodes: <DocumentBlockRiskCode>{DocumentBlockRiskCode.roleUncertain},
      sourceCropRef: 'crop://b1',
      parentBlockId: 'question-1',
      contentFormat: DocumentContentFormat.plainText,
      recognitionEngine: DocumentRecognitionEngine.handwritingOcr,
      recognitionStatus: DocumentRecognitionStatus.needsSpecialist,
    );

    final edited = block.copyWith(content: 'x=3');
    expect(edited.content, 'x=3');
    expect(edited.polygon, block.polygon);
    expect(edited.authorRole, DocumentAuthorRole.studentAnswer);
    expect(edited.riskCodes, contains(DocumentBlockRiskCode.roleUncertain));
    expect(edited.recognitionEngine, DocumentRecognitionEngine.handwritingOcr);
    expect(edited.recognitionStatus, DocumentRecognitionStatus.needsSpecialist);
  });

  test('options 默认为空 list，copyWith 可写入', () {
    const r = QuestionRegion(
      id: 'q',
      normalizedRect: Rect.fromLTWH(0, 0, 1, 1),
    );
    expect(r.options, isEmpty);
    expect(r.diagramNote, isNull);

    final withOptions = r.copyWith(
      options: const <String>['A. 红色', 'B. 蓝色'],
      diagramNote: '直角三角形',
    );
    expect(withOptions.options, <String>['A. 红色', 'B. 蓝色']);
    expect(withOptions.diagramNote, '直角三角形');
  });

  test('copyWith options 传空 list 可清空（不会被当作"保留原值"）', () {
    final r = region().copyWith(options: const <String>['A. 选项']);
    expect(r.options, hasLength(1));

    final cleared = r.copyWith(options: const <String>[]);
    expect(cleared.options, isEmpty);
  });

  test('copyWith diagramNote 传空串可清空（与 null 区分）', () {
    final r = region().copyWith(diagramNote: '原图备注');
    expect(r.diagramNote, '原图备注');

    // 传 '' 是显式清空（空串语义）
    final cleared = r.copyWith(diagramNote: '');
    expect(cleared.diagramNote, '');

    // 传 null 是"保留原值"（copyWith 默认行为）
    final kept = r.copyWith();
    expect(kept.diagramNote, '原图备注');
  });

  test('copyWith nullable 字段传 null 可显式清空', () {
    final r = region().copyWith(recognizedText: null, questionStem: null, subject: null);
    expect(r.recognizedText, isNull);
    expect(r.questionStem, isNull);
    expect(r.subject, isNull);
  });
}

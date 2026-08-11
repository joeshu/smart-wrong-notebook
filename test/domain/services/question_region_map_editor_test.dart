import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/domain/services/question_region_map_editor.dart';

void main() {
  const editor = QuestionRegionMapEditor();

  test('merge keeps source content and resets confirmations', () {
    const first = QuestionRegion(
      id: 'q1',
      normalizedRect: Rect.fromLTWH(.1, .1, .8, .2),
      recognizedText: '题干',
      options: <String>['A. 1'],
      documentBlocks: <DocumentBlock>[
        DocumentBlock(type: DocumentBlockType.text, content: '题干'),
      ],
      confirmedFields: <String>{'stem'},
      confidence: .9,
      source: QuestionRegionSource.layoutModel,
    );
    const second = QuestionRegion(
      id: 'q2',
      normalizedRect: Rect.fromLTWH(.1, .3, .8, .25),
      recognizedText: '续题',
      options: <String>['B. 2'],
      documentBlocks: <DocumentBlock>[
        DocumentBlock(type: DocumentBlockType.formula, content: r'x=2'),
      ],
      confidence: .7,
      source: QuestionRegionSource.layoutModel,
    );

    final merged = editor.merge(first, second);

    expect(merged.id, 'q1');
    expect(merged.normalizedRect, const Rect.fromLTRB(.1, .1, .9, .55));
    expect(merged.recognizedText, '题干\n续题');
    expect(merged.options, <String>['A. 1', 'B. 2']);
    expect(merged.documentBlocks, hasLength(2));
    expect(merged.source, QuestionRegionSource.manual);
    expect(merged.confidence, .7);
    expect(merged.confirmedFields, isEmpty);
  });

  test('vertical split preserves first content and makes second reviewable', () {
    const region = QuestionRegion(
      id: 'q1',
      normalizedRect: Rect.fromLTWH(.1, .2, .8, .4),
      recognizedText: '待重新分配的内容',
      analyzeWithAi: false,
      confirmedFields: <String>{'stem', 'options'},
    );

    final split = editor.splitVertically(region, secondId: 'q2');

    expect(split.first.normalizedRect,
        const Rect.fromLTWH(.1, .2, .8, .2));
    expect(split.second.normalizedRect,
        const Rect.fromLTWH(.1, .4, .8, .2));
    expect(split.first.recognizedText, '待重新分配的内容');
    expect(split.first.confirmedFields, isEmpty);
    expect(split.second.id, 'q2');
    expect(split.second.recognizedText, isNull);
    expect(split.second.analyzeWithAi, isFalse);
    expect(split.second.confidence, .5);
  });

  test('rejects unsafe split ratios and short regions', () {
    const normal = QuestionRegion(
      id: 'q1',
      normalizedRect: Rect.fromLTWH(.1, .1, .8, .3),
    );
    const short = QuestionRegion(
      id: 'q2',
      normalizedRect: Rect.fromLTWH(.1, .1, .8, .08),
    );

    expect(
      () => editor.splitVertically(normal, secondId: 'x', ratio: .05),
      throwsArgumentError,
    );
    expect(
      () => editor.splitVertically(short, secondId: 'x'),
      throwsFormatException,
    );
  });
}

import 'dart:math' as math;
import 'dart:ui';

import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';

class QuestionRegionSplit {
  const QuestionRegionSplit({required this.first, required this.second});
  final QuestionRegion first;
  final QuestionRegion second;
}

class QuestionRegionMapEditor {
  const QuestionRegionMapEditor();

  QuestionRegion merge(QuestionRegion selected, QuestionRegion other) {
    final a = selected.normalizedRect;
    final b = other.normalizedRect;
    return selected.copyWith(
      normalizedRect: Rect.fromLTRB(
        math.min(a.left, b.left),
        math.min(a.top, b.top),
        math.max(a.right, b.right),
        math.max(a.bottom, b.bottom),
      ),
      recognizedText: _join(selected.recognizedText, other.recognizedText),
      originalRecognizedText: _join(
        selected.originalRecognizedText,
        other.originalRecognizedText,
      ),
      questionStem: _join(selected.questionStem, other.questionStem),
      formulas: <String>[...selected.formulas, ...other.formulas],
      tables: <String>[...selected.tables, ...other.tables],
      options: <String>[...selected.options, ...other.options],
      documentBlocks: <DocumentBlock>[
        ...selected.documentBlocks,
        ...other.documentBlocks,
      ],
      recognizedBlockTypes: <String>{
        ...selected.recognizedBlockTypes,
        ...other.recognizedBlockTypes,
      }.toList(growable: false),
      studentAnswer: _join(selected.studentAnswer, other.studentAnswer),
      source: QuestionRegionSource.manual,
      confidence: math.min(selected.confidence, other.confidence),
      confirmedFields: const <String>{},
    );
  }

  QuestionRegionSplit splitVertically(
    QuestionRegion selected, {
    required String secondId,
    double ratio = .5,
  }) {
    if (ratio <= .15 || ratio >= .85) {
      throw ArgumentError.value(ratio, 'ratio', '拆分比例必须位于 0.15 到 0.85');
    }
    final rect = selected.normalizedRect;
    if (rect.height < .12) {
      throw const FormatException('当前题框过矮，请先拉高后再拆分');
    }
    final firstHeight = rect.height * ratio;
    final first = selected.copyWith(
      normalizedRect: Rect.fromLTWH(
        rect.left,
        rect.top,
        rect.width,
        firstHeight,
      ),
      source: QuestionRegionSource.manual,
      confidence: .5,
      confirmedFields: const <String>{},
    );
    final second = QuestionRegion(
      id: secondId,
      normalizedRect: Rect.fromLTWH(
        rect.left,
        rect.top + firstHeight,
        rect.width,
        rect.height - firstHeight,
      ),
      subject: selected.subject,
      source: QuestionRegionSource.manual,
      confidence: .5,
      analyzeWithAi: selected.analyzeWithAi,
      reviewStatus: selected.reviewStatus,
    );
    return QuestionRegionSplit(first: first, second: second);
  }

  String? _join(String? first, String? second) {
    final values = <String>{
      if (first?.trim().isNotEmpty == true) first!.trim(),
      if (second?.trim().isNotEmpty == true) second!.trim(),
    };
    return values.isEmpty ? null : values.join('\n');
  }
}

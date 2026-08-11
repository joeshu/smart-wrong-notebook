import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/shared/models/question_display_status.dart';

QuestionRecord _record({
  ContentStatus status = ContentStatus.ready,
  AnalysisResult? analysisResult,
}) {
  final now = DateTime(2026, 7, 21);
  return QuestionRecord(
    id: 'q1',
    imagePath: '/img.jpg',
    subject: Subject.math,
    extractedQuestionText: '题干',
    normalizedQuestionText: '题干',
    contentFormat: QuestionContentFormat.plain,
    tags: const <String>[],
    createdAt: now,
    updatedAt: now,
    lastReviewedAt: null,
    reviewCount: 0,
    isFavorite: false,
    contentStatus: status,
    masteryLevel: MasteryLevel.newQuestion,
    analysisResult: analysisResult,
  );
}

AnalysisResult get _analysis => const AnalysisResult(
      finalAnswer: '答案',
      steps: <String>['步骤'],
      aiTags: <String>[],
      knowledgePoints: <String>[],
      mistakeReason: '错因',
      studyAdvice: '建议',
    );

void main() {
  group('inferQuestionDisplayStatus', () {
    test('processing → recognizing', () {
      expect(
        inferQuestionDisplayStatus(_record(status: ContentStatus.processing)),
        QuestionDisplayStatus.recognizing,
      );
    });

    test('analyzing → analyzing', () {
      expect(
        inferQuestionDisplayStatus(_record(status: ContentStatus.analyzing)),
        QuestionDisplayStatus.analyzing,
      );
    });

    test('needsConfirmation → needsConfirmation', () {
      expect(
        inferQuestionDisplayStatus(
          _record(
            status: ContentStatus.needsConfirmation,
            analysisResult: _analysis,
          ),
        ),
        QuestionDisplayStatus.needsConfirmation,
      );
    });

    test('ready + analysisResult null → recognized（OCR 草稿）', () {
      expect(
        inferQuestionDisplayStatus(
            _record(status: ContentStatus.ready, analysisResult: null)),
        QuestionDisplayStatus.recognized,
      );
    });

    test('ready + analysisResult 非空 → analyzed', () {
      expect(
        inferQuestionDisplayStatus(
            _record(status: ContentStatus.ready, analysisResult: _analysis)),
        QuestionDisplayStatus.analyzed,
      );
    });

    test('failed → recognitionFailed', () {
      expect(
        inferQuestionDisplayStatus(_record(status: ContentStatus.failed)),
        QuestionDisplayStatus.recognitionFailed,
      );
    });

    test('analysisFailed → analysisFailed', () {
      expect(
        inferQuestionDisplayStatus(
            _record(status: ContentStatus.analysisFailed)),
        QuestionDisplayStatus.analysisFailed,
      );
    });

    test('老数据 failed（无法区分）一律视为 recognitionFailed', () {
      // 老数据没有 analysisFailed，failed 一律是识别失败
      expect(
        inferQuestionDisplayStatus(_record(status: ContentStatus.failed)),
        QuestionDisplayStatus.recognitionFailed,
      );
    });
  });

  group('QuestionDisplayStatusX 文案与配色', () {
    test('label 每个状态各不相同', () {
      final labels = QuestionDisplayStatus.values.map((s) => s.label).toSet();
      expect(labels.length, QuestionDisplayStatus.values.length,
          reason: '文案应各状态互不相同');
    });

    test('foregroundColor 状态分组正确', () {
      // 进行中两态同色（info），失败两态同色（danger）
      expect(QuestionDisplayStatus.recognizing.foregroundColor,
          QuestionDisplayStatus.analyzing.foregroundColor);
      expect(QuestionDisplayStatus.recognitionFailed.foregroundColor,
          QuestionDisplayStatus.analysisFailed.foregroundColor);
      // 三态各不相同
      final uniqueColors = <Color>{
        QuestionDisplayStatus.recognized.foregroundColor,
        QuestionDisplayStatus.analyzed.foregroundColor,
        QuestionDisplayStatus.recognitionFailed.foregroundColor,
      };
      expect(uniqueColors.length, 3);
    });

    test('backgroundColor 浅色/深色都有合理值', () {
      for (final status in QuestionDisplayStatus.values) {
        final light = status.backgroundColor(Brightness.light);
        final dark = status.backgroundColor(Brightness.dark);
        // 浅色用 ContainerLight 系列（不透明），深色用半透明前景色叠
        expect(light, isNot(equals(Colors.transparent)),
            reason: '${status.label} 浅色背景不应透明');
        expect(dark, isNot(equals(Colors.transparent)),
            reason: '${status.label} 深色背景不应透明');
      }
    });

    test('isFailed / isInProgress', () {
      expect(QuestionDisplayStatus.recognitionFailed.isFailed, isTrue);
      expect(QuestionDisplayStatus.analysisFailed.isFailed, isTrue);
      expect(QuestionDisplayStatus.recognized.isFailed, isFalse);

      expect(QuestionDisplayStatus.recognizing.isInProgress, isTrue);
      expect(QuestionDisplayStatus.analyzing.isInProgress, isTrue);
      expect(QuestionDisplayStatus.analyzed.isInProgress, isFalse);
    });
  });
}

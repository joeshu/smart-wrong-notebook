import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/shared/utils/json_export_service.dart';

void main() {
  late JsonExportService service;

  setUp(() {
    service = JsonExportService();
  });

  List<QuestionRecord> _sampleQuestions() => <QuestionRecord>[
        QuestionRecord.draft(
          id: 'q-1',
          imagePath: '/tmp/q-1.png',
          subject: Subject.math,
          recognizedText: '2x+1=5',
        ).copyWith(
          analysisResult: const AnalysisResult(
            finalAnswer: 'x=2',
            steps: <String>['移项得 2x=4'],
            aiTags: <String>['方程'],
            knowledgePoints: <String>['代数'],
            mistakeReason: '审题不清',
            studyAdvice: '多复习',
          ),
        ),
        QuestionRecord.draft(
          id: 'q-2',
          imagePath: '',
          subject: Subject.english,
          recognizedText: 'Hello',
        ),
      ];

  test('generateJson returns valid parseable JSON with metadata', () async {
    final jsonStr = await service.generateJson(questions: _sampleQuestions());

    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;

    expect(decoded['appVersion'], JsonExportService.appVersion);
    expect(decoded['exportedAt'], isA<String>());
    expect(decoded['questionCount'], 2);
    expect(decoded['questions'], isA<List>());
    expect((decoded['questions'] as List).length, 2);
  });

  test('generateJson serializes each question via toJson', () async {
    final jsonStr = await service.generateJson(questions: _sampleQuestions());

    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    final questions = (decoded['questions'] as List).cast<Map<String, dynamic>>();

    expect(questions.first['id'], 'q-1');
    expect(questions.first['subject'], 'math');
    expect(questions.first['extractedQuestionText'], '2x+1=5');
    expect(
      (questions.first['analysisResult'] as Map<String, dynamic>)['finalAnswer'],
      'x=2',
    );
    expect(questions.last['id'], 'q-2');
    expect(questions.last['subject'], 'english');
  });

  test('generateJson omits review logs by default but supports inclusion',
      () async {
    final withoutLogs = await service.generateJson(questions: _sampleQuestions());
    expect((jsonDecode(withoutLogs) as Map<String, dynamic>)['reviewLogs'],
        isEmpty);

    final reviewLogs = <ReviewLog>[
      ReviewLog(
        id: 'r-1',
        questionRecordId: 'q-1',
        reviewedAt: DateTime(2026, 1, 2),
        result: 'remembered',
        masteryAfter: MasteryLevel.reviewing,
      ),
    ];
    final withLogs = await service.generateJson(
      questions: _sampleQuestions(),
      includeReviewLogs: true,
      reviewLogs: reviewLogs,
    );
    final decoded = jsonDecode(withLogs) as Map<String, dynamic>;
    final logs = (decoded['reviewLogs'] as List).cast<Map<String, dynamic>>();
    expect(logs, hasLength(1));
    expect(logs.first['id'], 'r-1');
    expect(logs.first['questionRecordId'], 'q-1');
    expect(logs.first['masteryAfter'], 'reviewing');
  });
}

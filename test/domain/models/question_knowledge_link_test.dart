import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_knowledge_link.dart';

void main() {
  group('QuestionKnowledgeLink', () {
    test('toJson / fromJson round-trip preserves all fields', () {
      final link = QuestionKnowledgeLink(
        questionId: 'q_1',
        knowledgePointId: 'kp_math_functions_quadratic',
        source: LinkSource.ai,
        confidence: 0.92,
        evidence: 'AI 识别到二次函数关键词',
        createdAt: DateTime(2026, 7, 21, 10, 30),
      );

      final json = link.toJson();
      final restored = QuestionKnowledgeLink.fromJson(json);

      expect(restored.questionId, link.questionId);
      expect(restored.knowledgePointId, link.knowledgePointId);
      expect(restored.source, LinkSource.ai);
      expect(restored.confidence, closeTo(0.92, 0.001));
      expect(restored.evidence, link.evidence);
      expect(restored.createdAt, link.createdAt);
    });

    test('manual link has null confidence', () {
      final link = QuestionKnowledgeLink(
        questionId: 'q_1',
        knowledgePointId: 'kp_1',
        source: LinkSource.manual,
        createdAt: DateTime(2026),
      );
      expect(link.confidence, isNull);
    });

    test('fromJson handles missing optional fields', () {
      final json = <String, dynamic>{
        'questionId': 'q_1',
        'knowledgePointId': 'kp_1',
        'source': 'migrated',
        'createdAt': '2026-07-21T00:00:00.000',
      };
      final link = QuestionKnowledgeLink.fromJson(json);

      expect(link.source, LinkSource.migrated);
      expect(link.confidence, isNull);
      expect(link.evidence, isNull);
    });

    test('fromJson handles unknown source gracefully', () {
      final json = <String, dynamic>{
        'questionId': 'q_1',
        'knowledgePointId': 'kp_1',
        'source': 'unknown_source',
        'createdAt': '2026-07-21T00:00:00.000',
      };
      final link = QuestionKnowledgeLink.fromJson(json);
      // Falls back to LinkSource.ai
      expect(link.source, LinkSource.ai);
    });

    test('equality based on questionId + knowledgePointId', () {
      final a = QuestionKnowledgeLink(
        questionId: 'q_1',
        knowledgePointId: 'kp_1',
        source: LinkSource.ai,
        createdAt: DateTime(2026),
      );
      final b = QuestionKnowledgeLink(
        questionId: 'q_1',
        knowledgePointId: 'kp_1',
        source: LinkSource.manual,
        createdAt: DateTime(2026),
      );
      final c = QuestionKnowledgeLink(
        questionId: 'q_2',
        knowledgePointId: 'kp_1',
        source: LinkSource.ai,
        createdAt: DateTime(2026),
      );

      expect(a == b, isTrue);
      expect(a == c, isFalse);
    });

    test('isPrimary defaults to false and round-trips', () {
      final link = QuestionKnowledgeLink(
        questionId: 'q_1',
        knowledgePointId: 'kp_1',
        source: LinkSource.manual,
        createdAt: DateTime(2026),
        isPrimary: true,
      );
      expect(link.isPrimary, isTrue);

      final restored = QuestionKnowledgeLink.fromJson(link.toJson());
      expect(restored.isPrimary, isTrue);
    });

    test('fromJson treats missing isPrimary as false (legacy data)', () {
      final json = <String, dynamic>{
        'questionId': 'q_1',
        'knowledgePointId': 'kp_1',
        'source': 'ai',
        'createdAt': '2026-07-21T00:00:00.000',
      };
      final link = QuestionKnowledgeLink.fromJson(json);
      expect(link.isPrimary, isFalse);
    });
  });
}

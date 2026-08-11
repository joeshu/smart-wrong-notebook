import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/data/repositories/pending_knowledge_point_mapping_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_knowledge_link_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/pending_knowledge_point_mapping.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_knowledge_link.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import '../support/question_backup_restore_harness.dart';

void main() {
  test('restoring the same snapshot twice is idempotent across core records', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final links = QuestionKnowledgeLinkRepository();
    final pending = PendingKnowledgePointMappingRepository();
    final source = QuestionBackupRestoreHarness(
      questions: InMemoryQuestionRepository(),
      links: links,
      pendingMappings: pending,
    );
    final question = QuestionRecord(
      id: 'q-restore-1',
      imagePath: '',
      subject: Subject.math,
      extractedQuestionText: 'x+1=2',
      normalizedQuestionText: 'x + 1 = 2',
      contentFormat: QuestionContentFormat.plain,
      tags: const <String>[],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      lastReviewedAt: null,
      reviewCount: 0,
      isFavorite: false,
      contentStatus: ContentStatus.ready,
      masteryLevel: MasteryLevel.newQuestion,
      analysisResult: null,
    );
    await source.questions.saveDraft(question);
    await links.addLink(QuestionKnowledgeLink(
      questionId: question.id,
      knowledgePointId: 'kp-linear',
      source: LinkSource.ai,
      confidence: .9,
      createdAt: DateTime(2026),
      isPrimary: true,
    ));
    await pending.add(PendingKnowledgePointMapping(
      id: 'pending-1',
      questionId: question.id,
      originalText: '一次方程',
      createdAt: DateTime(2026),
    ));

    final snapshot = await source.exportSnapshot();

    // Simulate restoring into a fresh/empty local store rather than reusing
    // the source repositories' SharedPreferences-backed cache.
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    links.resetForTest();
    pending.resetForTest();

    final restoredQuestions = InMemoryQuestionRepository();
    final restoredLinks = QuestionKnowledgeLinkRepository();
    final restoredPending = PendingKnowledgePointMappingRepository();
    final target = QuestionBackupRestoreHarness(
      questions: restoredQuestions,
      links: restoredLinks,
      pendingMappings: restoredPending,
    );

    await target.restoreSnapshot(snapshot);
    await target.restoreSnapshot(snapshot);

    expect(await restoredQuestions.listAll(), hasLength(1));
    expect((await restoredLinks.allLinks()), hasLength(1));
    expect((await restoredLinks.linksForQuestion(question.id)).single.isPrimary,
        isTrue);
    expect(await restoredPending.allPending(), hasLength(1));
    expect((await restoredPending.allPending()).single.id, 'pending-1');
  });
}

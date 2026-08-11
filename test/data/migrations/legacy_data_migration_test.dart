import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/data/migrations/legacy_data_migration.dart';
import 'package:smart_wrong_notebook/src/data/repositories/knowledge_point_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_knowledge_link_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/repositories/review_log_repository.dart';

QuestionRecord _question(String id, {List<String> aiKnowledgePoints = const []}) {
  final now = DateTime(2026);
  return QuestionRecord(
    id: id,
    imagePath: '',
    subject: Subject.math,
    extractedQuestionText: '题目',
    normalizedQuestionText: '题目',
    contentFormat: QuestionContentFormat.plain,
    tags: const <String>[],
    createdAt: now,
    updatedAt: now,
    lastReviewedAt: null,
    reviewCount: 0,
    isFavorite: false,
    contentStatus: ContentStatus.ready,
    masteryLevel: MasteryLevel.newQuestion,
    analysisResult: null,
    aiKnowledgePoints: aiKnowledgePoints,
  );
}

ReviewLog _log(String id, String questionId) => ReviewLog(
      id: id,
      questionRecordId: questionId,
      reviewedAt: DateTime(2026),
      result: 'reviewing',
      masteryAfter: MasteryLevel.reviewing,
    );

class _FailOnceQuestionRepository extends InMemoryQuestionRepository {
  var shouldFail = true;
  @override
  Future<void> saveDrafts(List<QuestionRecord> records) async {
    if (shouldFail) {
      shouldFail = false;
      throw StateError('temporary write failure');
    }
    await super.saveDrafts(records);
  }
}

void main() {
  LegacyDataMigration migration({
    required SettingsRepository settings,
    required QuestionRepository questions,
    required QuestionRepository legacyQuestions,
    required ReviewLogRepository reviewLogs,
    required ReviewLogRepository legacyReviewLogs,
    KnowledgePointRepository? knowledgePointRepo,
    QuestionKnowledgeLinkRepository? questionKnowledgeLinkRepo,
  }) => LegacyDataMigration(
        settings: settings,
        questions: questions,
        legacyQuestions: legacyQuestions,
        reviewLogs: reviewLogs,
        legacyReviewLogs: legacyReviewLogs,
        knowledgePointRepo: knowledgePointRepo,
        questionKnowledgeLinkRepo: questionKnowledgeLinkRepo,
      );

  test('imports legacy questions and review logs once', () async {
    final settings = InMemorySettingsRepository();
    final legacyQuestions = InMemoryQuestionRepository();
    final legacyLogs = InMemoryReviewLogRepository();
    final questions = InMemoryQuestionRepository();
    final logs = InMemoryReviewLogRepository();
    await legacyQuestions.saveDraft(_question('legacy-question'));
    await legacyLogs.insert(_log('legacy-log', 'legacy-question'));

    await migration(settings: settings, questions: questions, legacyQuestions: legacyQuestions, reviewLogs: logs, legacyReviewLogs: legacyLogs).migrateIfNeeded();

    expect((await questions.listAll()).single.id, 'legacy-question');
    expect((await logs.listAll()).single.id, 'legacy-log');
    expect(await settings.getString(LegacyDataMigration.questionMigrationKey), 'done');
    expect(await settings.getString(LegacyDataMigration.reviewLogMigrationKey), 'done');

    await migration(settings: settings, questions: questions, legacyQuestions: legacyQuestions, reviewLogs: logs, legacyReviewLogs: legacyLogs).migrateIfNeeded();
    expect(await questions.listAll(), hasLength(1));
    expect(await logs.listAll(), hasLength(1));
  });

  test('does not overwrite populated Drift stores', () async {
    final settings = InMemorySettingsRepository();
    final questions = InMemoryQuestionRepository();
    final logs = InMemoryReviewLogRepository();
    await questions.saveDraft(_question('new-question'));
    await logs.insert(_log('new-log', 'new-question'));
    final legacyQuestions = InMemoryQuestionRepository();
    final legacyLogs = InMemoryReviewLogRepository();
    await legacyQuestions.saveDraft(_question('old-question'));
    await legacyLogs.insert(_log('old-log', 'old-question'));

    await migration(settings: settings, questions: questions, legacyQuestions: legacyQuestions, reviewLogs: logs, legacyReviewLogs: legacyLogs).migrateIfNeeded();

    expect((await questions.listAll()).single.id, 'new-question');
    expect((await logs.listAll()).single.id, 'new-log');
  });

  test('failed migration keeps completion marker unset for retry', () async {
    final settings = InMemorySettingsRepository();
    final questions = _FailOnceQuestionRepository();
    final legacyQuestions = InMemoryQuestionRepository();
    await legacyQuestions.saveDraft(_question('legacy-question'));
    final logs = InMemoryReviewLogRepository();

    final job = migration(settings: settings, questions: questions, legacyQuestions: legacyQuestions, reviewLogs: logs, legacyReviewLogs: InMemoryReviewLogRepository());
    await job.migrateIfNeeded();
    expect(await settings.getString(LegacyDataMigration.questionMigrationKey), isNull);

    await job.migrateIfNeeded();
    expect((await questions.listAll()).single.id, 'legacy-question');
    expect(await settings.getString(LegacyDataMigration.questionMigrationKey), 'done');
  });

  test('records retryable migration status and clears error after retry', () async {
    final settings = InMemorySettingsRepository();
    final questions = _FailOnceQuestionRepository();
    final legacyQuestions = InMemoryQuestionRepository();
    await legacyQuestions.saveDraft(_question('legacy-question'));
    final job = migration(
      settings: settings,
      questions: questions,
      legacyQuestions: legacyQuestions,
      reviewLogs: InMemoryReviewLogRepository(),
      legacyReviewLogs: InMemoryReviewLogRepository(),
    );

    await job.migrateIfNeeded();
    expect(await settings.getString(LegacyDataMigration.statusKey), 'retryable');
    expect(
      await settings.getString(LegacyDataMigration.lastErrorKey),
      contains('temporary write failure'),
    );

    await job.migrateIfNeeded();
    expect(await settings.getString(LegacyDataMigration.statusKey), 'done');
    expect(await settings.getString(LegacyDataMigration.lastErrorKey), '');
  });

  group('knowledge point links migration', () {
    setUp(() {
      // 知识点仓库和关联仓库都用 SharedPreferences，需要干净的 mock。
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('seeds builtin tree and links aiKnowledgePoints to controlled nodes',
        () async {
      final settings = InMemorySettingsRepository();
      final questions = InMemoryQuestionRepository();
      // 题目带「二次函数」，对应内置知识点 kp_math_functions_quadratic
      await questions.saveDraft(_question(
        'q-1',
        aiKnowledgePoints: const <String>['二次函数'],
      ));
      final kpRepo = KnowledgePointRepository();
      final linkRepo = QuestionKnowledgeLinkRepository();

      await migration(
        settings: settings,
        questions: questions,
        legacyQuestions: InMemoryQuestionRepository(),
        reviewLogs: InMemoryReviewLogRepository(),
        legacyReviewLogs: InMemoryReviewLogRepository(),
        knowledgePointRepo: kpRepo,
        questionKnowledgeLinkRepo: linkRepo,
      ).migrateIfNeeded();

      // 内置知识点树已播种
      expect((await kpRepo.loadAll()), isNotEmpty);
      // 关联已创建并指向受控节点
      final links = await linkRepo.linksForQuestion('q-1');
      expect(links, hasLength(1));
      expect(links.first.knowledgePointId, 'kp_math_functions_quadratic');
      expect(links.first.source.name, 'migrated');
      // 迁移标记已写入
      expect(
        await settings.getString(LegacyDataMigration.knowledgePointMigrationKey),
        'done',
      );
    });

    test('skips knowledge point migration when repos not injected', () async {
      final settings = InMemorySettingsRepository();
      final questions = InMemoryQuestionRepository();
      await questions.saveDraft(_question(
        'q-1',
        aiKnowledgePoints: const <String>['二次函数'],
      ));

      await migration(
        settings: settings,
        questions: questions,
        legacyQuestions: InMemoryQuestionRepository(),
        reviewLogs: InMemoryReviewLogRepository(),
        legacyReviewLogs: InMemoryReviewLogRepository(),
        // 不注入 knowledgePointRepo / questionKnowledgeLinkRepo
      ).migrateIfNeeded();

      // 未注入时不应写迁移标记
      expect(
        await settings.getString(LegacyDataMigration.knowledgePointMigrationKey),
        isNull,
      );
    });

    test('idempotent: second run does not duplicate links', () async {
      final settings = InMemorySettingsRepository();
      final questions = InMemoryQuestionRepository();
      await questions.saveDraft(_question(
        'q-1',
        aiKnowledgePoints: const <String>['二次函数'],
      ));
      final kpRepo = KnowledgePointRepository();
      final linkRepo = QuestionKnowledgeLinkRepository();

      final job = migration(
        settings: settings,
        questions: questions,
        legacyQuestions: InMemoryQuestionRepository(),
        reviewLogs: InMemoryReviewLogRepository(),
        legacyReviewLogs: InMemoryReviewLogRepository(),
        knowledgePointRepo: kpRepo,
        questionKnowledgeLinkRepo: linkRepo,
      );
      await job.migrateIfNeeded();
      await job.migrateIfNeeded();

      // 重复运行仍只有一条关联（replaceLinksForQuestion 覆盖）
      final links = await linkRepo.linksForQuestion('q-1');
      expect(links, hasLength(1));
    });

    test('skips questions without aiKnowledgePoints', () async {
      final settings = InMemorySettingsRepository();
      final questions = InMemoryQuestionRepository();
      await questions.saveDraft(_question('q-empty'));
      final kpRepo = KnowledgePointRepository();
      final linkRepo = QuestionKnowledgeLinkRepository();

      await migration(
        settings: settings,
        questions: questions,
        legacyQuestions: InMemoryQuestionRepository(),
        reviewLogs: InMemoryReviewLogRepository(),
        legacyReviewLogs: InMemoryReviewLogRepository(),
        knowledgePointRepo: kpRepo,
        questionKnowledgeLinkRepo: linkRepo,
      ).migrateIfNeeded();

      // 无 aiKnowledgePoints 的题目不应产生关联
      final links = await linkRepo.linksForQuestion('q-empty');
      expect(links, isEmpty);
      // 但迁移标记仍应写入
      expect(
        await settings.getString(LegacyDataMigration.knowledgePointMigrationKey),
        'done',
      );
    });
  });
}

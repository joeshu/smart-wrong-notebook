import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/local/app_database.dart' hide ReviewLog;
import 'package:smart_wrong_notebook/src/data/repositories/drift_review_log_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';

void main() {
  late AppDatabase database;
  late DriftReviewLogRepository repository;

  setUp(() {
    database = AppDatabase.memory();
    repository = DriftReviewLogRepository(database);
  });

  tearDown(() => database.close());

  test('round-trips review results and stable external IDs', () async {
    final log = ReviewLog(
      id: 'legacy-uuid-1',
      questionRecordId: 'question-1',
      reviewedAt: DateTime(2026, 7, 18, 12),
      result: 'forgot',
      masteryAfter: MasteryLevel.reviewing,
    );

    await repository.insert(log);

    final loaded = (await repository.getByQuestionId('question-1')).single;
    expect(loaded.id, 'legacy-uuid-1');
    expect(loaded.result, 'forgot');
    expect(loaded.masteryAfter, MasteryLevel.reviewing);
    expect((await repository.listAll()).single.id, 'legacy-uuid-1');
  });

  test('clear removes all persisted logs', () async {
    await repository.insert(ReviewLog(
      id: 'log-1',
      questionRecordId: 'question-1',
      reviewedAt: DateTime(2026),
      result: 'mastered',
      masteryAfter: MasteryLevel.mastered,
    ));

    await repository.clear();

    expect(await repository.listAll(), isEmpty);
  });
}

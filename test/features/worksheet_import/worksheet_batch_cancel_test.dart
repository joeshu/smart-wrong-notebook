import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_import_session.dart';
import 'package:smart_wrong_notebook/src/features/worksheet_import/presentation/worksheet_import_screen.dart';

QuestionRecord _record(String id, {ContentStatus status = ContentStatus.processing}) {
  final now = DateTime(2026);
  return QuestionRecord(
    id: id,
    imagePath: '', subject: Subject.math,
    extractedQuestionText: '', normalizedQuestionText: '',
    contentFormat: QuestionContentFormat.plain, tags: const <String>[],
    createdAt: now, updatedAt: now, lastReviewedAt: null, reviewCount: 0,
    isFavorite: false, contentStatus: status,
    masteryLevel: MasteryLevel.newQuestion, analysisResult: null,
  );
}

void main() {
  testWidgets('shows a cancellable batch action for generated question drafts', (tester) async {
    final page = _record('page');
    final draft = _record('draft');
    final container = ProviderContainer(overrides: <Override>[
      questionRepositoryProvider.overrideWithValue(InMemoryQuestionRepository()),
    ]);
    addTearDown(container.dispose);
    container.read(currentWorksheetImportProvider.notifier).state = WorksheetImportSession(
      id: 'batch', pages: <QuestionRecord>[page, draft],
      sourcePageIds: <String>{page.id}, createdAt: DateTime(2026),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: WorksheetImportScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('取消批次'), findsOneWidget);

    await tester.tap(find.text('取消批次'));
    await tester.pumpAndSettle();
    expect(find.text('取消本次试卷导入？'), findsOneWidget);
    expect(find.text('取消并清理'), findsOneWidget);
  });
}

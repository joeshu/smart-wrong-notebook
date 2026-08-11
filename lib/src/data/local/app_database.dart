import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

import 'package:smart_wrong_notebook/src/data/local/tables/question_records.dart';
import 'package:smart_wrong_notebook/src/data/local/tables/generated_exercises.dart';
import 'package:smart_wrong_notebook/src/data/local/tables/review_logs.dart';
import 'package:smart_wrong_notebook/src/data/local/tables/settings_entries.dart';

part 'app_database.g.dart';

@DriftDatabase(
    tables: [QuestionRecords, GeneratedExercises, ReviewLogs, SettingsEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase._internal(super.e);

  static AppDatabase? _instance;

  factory AppDatabase() {
    _instance ??= AppDatabase._internal(_openConnection());
    return _instance!;
  }

  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            await migrator.deleteTable('generated_exercises');
            await migrator.createTable(generatedExercises);
          }
          if (from < 3) {
            await migrator.addColumn(
                questionRecords, questionRecords.parentQuestionId);
            await migrator.addColumn(
                questionRecords, questionRecords.rootQuestionId);
            await migrator.addColumn(
                questionRecords, questionRecords.splitOrder);
          }
          if (from < 4) {
            await migrator.addColumn(
                generatedExercises, generatedExercises.roundIndex);
            await migrator.addColumn(
                generatedExercises, generatedExercises.roundTotal);
            await migrator.addColumn(
                generatedExercises, generatedExercises.roundGroupId);
            await migrator.addColumn(
                generatedExercises, generatedExercises.sourceExerciseId);
          }
          if (from < 5) {
            await migrator.addColumn(
                generatedExercises, generatedExercises.diagramDataJson);
          }
          if (from < 6) {
            await migrator.addColumn(
                questionRecords, questionRecords.reflectionNote);
          }
          if (from < 7) {
            await migrator.addColumn(
                questionRecords, questionRecords.archivedAt);
          }
          if (from < 8) {
            await migrator.addColumn(
                questionRecords, questionRecords.ocrConfidence);
          }
          if (from < 9) {
            await migrator.addColumn(
                questionRecords, questionRecords.studentAnswer);
          }
          if (from < 10) {
            await migrator.addColumn(
                questionRecords, questionRecords.expectedAnswer);
            await migrator.addColumn(
                questionRecords, questionRecords.isCorrect);
          }
          if (from < 11) {
            await migrator.addColumn(
                questionRecords, questionRecords.questionType);
          }
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory()
        .timeout(const Duration(seconds: 10));
    final file = File(p.join(dbFolder.path, 'smart_wrong_notebook.db'));
    return NativeDatabase.createInBackground(file);
  });
}

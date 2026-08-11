import 'package:drift/drift.dart';

class QuestionRecords extends Table {
  TextColumn get id => text()();
  TextColumn get subject => text()();
  TextColumn get originalImagePath => text().nullable()();
  TextColumn get originalText => text()();
  TextColumn get correctedText => text()();
  TextColumn get masteryLevel => text()();
  TextColumn get contentStatus => text()();
  IntColumn get reviewCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextReviewAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get aiAnalysisJson => text().nullable()();
  TextColumn get tags => text().withDefault(const Constant(''))();
  TextColumn get aiTags => text().withDefault(const Constant(''))();
  TextColumn get aiKnowledgePoints => text().withDefault(const Constant(''))();
  TextColumn get customTags => text().withDefault(const Constant(''))();
  TextColumn get parentQuestionId => text().nullable()();
  TextColumn get rootQuestionId => text().nullable()();
  IntColumn get splitOrder => integer().nullable()();
  TextColumn get reflectionNote => text().nullable()();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  RealColumn get ocrConfidence => real().nullable()();
  TextColumn get studentAnswer => text().nullable()();
  TextColumn get expectedAnswer => text().nullable()();
  BoolColumn get isCorrect => boolean().nullable()();
  TextColumn get questionType => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
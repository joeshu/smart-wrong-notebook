import 'package:drift/drift.dart';
import 'package:smart_wrong_notebook/src/data/local/app_database.dart' as db;
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart'
    as domain;
import 'package:smart_wrong_notebook/src/domain/models/question_type.dart'
    as domain;
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/generated_exercise.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_split_result.dart'
    as split;
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'dart:convert';

class DriftQuestionRepository implements QuestionRepository {
  DriftQuestionRepository(this._db);
  final db.AppDatabase _db;

  @override
  Future<List<domain.QuestionRecord>> listAll() async {
    // 一次查询拿全部题目，再一次性拿全部练习题，按 questionId 分组组装，
    // 消除 N+1 查询（原先每道题单独查一次 exercises）。
    final rows = await _db.select(_db.questionRecords).get();
    if (rows.isEmpty) return const <domain.QuestionRecord>[];

    final exerciseRows = await (_db.select(_db.generatedExercises)
          ..orderBy([
            (t) => OrderingTerm.asc(t.questionId),
            (t) => OrderingTerm.asc(t.roundIndex),
            (t) => OrderingTerm.asc(t.orderIndex),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .get();
    final exercisesByQuestion =
        <String, List<db.GeneratedExercise>>{};
    for (final er in exerciseRows) {
      (exercisesByQuestion[er.questionId] ??= <db.GeneratedExercise>[])
          .add(er);
    }
    return rows
        .map((row) => _toModel(row,
            exerciseRows: exercisesByQuestion[row.id] ?? const []))
        .toList();
  }

  @override
  Future<domain.QuestionRecord?> getById(String id) async {
    final row = await (_db.select(_db.questionRecords)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    final exerciseRows = await (_db.select(_db.generatedExercises)
          ..where((t) => t.questionId.equals(id))
          ..orderBy([
            (t) => OrderingTerm.asc(t.roundIndex),
            (t) => OrderingTerm.asc(t.orderIndex),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .get();
    return _toModel(row, exerciseRows: exerciseRows);
  }

  @override
  Future<void> saveDraft(domain.QuestionRecord record) async {
    // 三步操作（写题→删旧练习→写新练习）用事务包裹，避免中途崩溃留下不一致状态。
    await _db.transaction(() async {
      await _db.into(_db.questionRecords).insertOnConflictUpdate(
            db.QuestionRecordsCompanion(
              id: Value(record.id),
              subject: Value(record.subject.name),
              originalImagePath: Value(record.imagePath),
              originalText: Value(record.extractedQuestionText),
              correctedText: Value(record.normalizedQuestionText),
              masteryLevel: Value(record.masteryLevel.name),
              contentStatus:
                  Value(record.contentStatus.toString().split('.').last),
              reviewCount: Value(record.reviewCount),
              nextReviewAt: Value(record.nextReviewAt),
              createdAt: Value(record.createdAt),
              updatedAt: Value(record.updatedAt),
              aiAnalysisJson: Value(record.analysisResult != null ||
                      record.splitResult != null ||
                      record.candidateAnalyses.isNotEmpty ||
                      record.lastAnalysisError != null
                  ? jsonEncode(<String, dynamic>{
                      'analysisResult': record.analysisResult?.toJson(),
                      'splitResult': record.splitResult?.toJson(),
                      'candidateAnalyses': record.candidateAnalyses
                          .map((candidate) => candidate.toJson())
                          .toList(),
                      'lastAnalysisError': record.lastAnalysisError,
                    })
                  : null),
              tags: Value(record.persistentTags.join(',')),
              aiTags: Value(record.aiTags.join(',')),
              aiKnowledgePoints: Value(record.aiKnowledgePoints.join(',')),
              customTags: Value(record.customTags.join(',')),
              parentQuestionId: Value(record.parentQuestionId),
              rootQuestionId: Value(record.rootQuestionId),
              splitOrder: Value(record.splitOrder),
              reflectionNote: Value(record.reflectionNote),
              archivedAt: Value(record.archivedAt),
              ocrConfidence: Value(record.ocrConfidence),
              studentAnswer: Value(record.studentAnswer),
              expectedAnswer: Value(record.expectedAnswer),
              isCorrect: Value(record.isCorrect),
              questionType: Value(record.questionType?.name),
            ),
          );

      await (_db.delete(_db.generatedExercises)
            ..where((t) => t.questionId.equals(record.id)))
          .go();
      if (record.savedExercises.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAll(
            _db.generatedExercises,
            record.savedExercises.map((exercise) {
              final roundIndex = exercise.roundIndex ?? 1;
              final normalized = exercise.copyWith(
                id:
                    '${record.id}-round-$roundIndex-exercise-${(exercise.order ?? 0) + 1}',
                questionId: record.id,
              );
              return db.GeneratedExercisesCompanion.insert(
                id: normalized.id,
                questionId: normalized.questionId,
                generationMode: Value(normalized.generationMode.name),
                orderIndex: Value(normalized.order),
                difficulty: normalized.difficulty,
                question: normalized.question,
                answer: normalized.answer,
                explanation: Value(normalized.explanation),
                optionsJson: Value(normalized.options == null
                    ? null
                    : jsonEncode(normalized.options)),
                userAnswer: Value(normalized.userAnswer),
                isCorrect: Value(normalized.isCorrect),
                roundIndex: Value(normalized.roundIndex),
                roundTotal: Value(normalized.roundTotal),
                roundGroupId: Value(normalized.roundGroupId),
                sourceExerciseId: Value(normalized.sourceExerciseId),
                diagramDataJson: Value(normalized.diagramData == null
                    ? null
                    : jsonEncode(normalized.diagramData)),
                createdAt: normalized.createdAt,
              );
            }).toList(),
          );
        });
      }
    });
  }

  @override
  Future<void> saveDrafts(List<domain.QuestionRecord> records) async {
    if (records.isEmpty) return;
    // 整批用单次事务包裹，任一条失败整体回滚，避免半保存状态。
    await _db.transaction(() async {
      for (final record in records) {
        await saveDraft(record);
      }
    });
  }

  @override
  Future<void> delete(String id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.generatedExercises)
            ..where((t) => t.questionId.equals(id)))
          .go();
      await (_db.delete(_db.questionRecords)..where((t) => t.id.equals(id)))
          .go();
    });
  }

  @override
  Future<void> update(domain.QuestionRecord record) => saveDraft(record);

  /// 响应式订阅：题目表或练习题表任一变更都自动推送新快照。
  /// 内部用一次 `watch` 拿题目行，再 `get` 一次性拿全部练习题组装，
  /// 避免每道题单独订阅造成的 stream 组合爆炸。
  @override
  Stream<List<domain.QuestionRecord>> watchAll() {
    return _db
        .select(_db.questionRecords)
        .watch()
        .asyncMap((rows) async {
      if (rows.isEmpty) return const <domain.QuestionRecord>[];
      final exerciseRows = await (_db.select(_db.generatedExercises)
            ..orderBy([
              (t) => OrderingTerm.asc(t.questionId),
              (t) => OrderingTerm.asc(t.roundIndex),
              (t) => OrderingTerm.asc(t.orderIndex),
              (t) => OrderingTerm.asc(t.createdAt),
            ]))
          .get();
      final exercisesByQuestion = <String, List<db.GeneratedExercise>>{};
      for (final er in exerciseRows) {
        (exercisesByQuestion[er.questionId] ??= <db.GeneratedExercise>[])
            .add(er);
      }
      return rows
          .map((row) => _toModel(row,
              exerciseRows: exercisesByQuestion[row.id] ?? const []))
          .toList();
    });
  }

  domain.QuestionRecord _toModel(
    db.QuestionRecord row, {
    List<db.GeneratedExercise> exerciseRows = const [],
  }) {
    AnalysisResult? analysisResult;
    List<GeneratedExercise> legacyExercises = <GeneratedExercise>[];

    if (row.aiAnalysisJson != null && row.aiAnalysisJson!.isNotEmpty) {
      try {
        final decoded = jsonDecode(row.aiAnalysisJson!) as Map<String, dynamic>;
        final analysisJson = decoded['analysisResult'] is Map<String, dynamic>
            ? decoded['analysisResult'] as Map<String, dynamic>
            : decoded;
        analysisResult = AnalysisResult.fromJson(analysisJson);
        legacyExercises = ((analysisJson['generatedExercises'] as List?) ?? const [])
            .map((e) => GeneratedExercise.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        analysisResult = null;
      }
    }

    final savedExercises = exerciseRows.isNotEmpty
        ? exerciseRows.map(_toExerciseModel).toList()
        : legacyExercises
            .asMap()
            .entries
            .map((entry) => entry.value.copyWith(
                  questionId: row.id,
                  order: entry.value.order ?? entry.key,
                ))
            .toList();

    final tags = row.tags.isNotEmpty ? row.tags.split(',') : <String>[];
    split.QuestionSplitResult? splitResult;
    List<domain.CandidateAnalysisSnapshot> candidateAnalyses =
        const <domain.CandidateAnalysisSnapshot>[];
    String? lastAnalysisError;
    try {
      final decoded = jsonDecode(row.aiAnalysisJson ?? '') as Map<String, dynamic>;
      final splitJson = decoded['splitResult'] as Map<String, dynamic>?;
      splitResult = splitJson == null
          ? null
          : split.QuestionSplitResult.fromJson(splitJson);
      candidateAnalyses = (decoded['candidateAnalyses'] as List? ?? const [])
          .map((item) => domain.CandidateAnalysisSnapshot.fromJson(
              item as Map<String, dynamic>))
          .toList();
      lastAnalysisError = decoded['lastAnalysisError'] as String?;
    } catch (_) {
      // Legacy rows contain the bare AnalysisResult JSON.
    }

    return domain.QuestionRecord(
      id: row.id,
      imagePath: row.originalImagePath ?? '',
      subject: Subject.values
          .firstWhere((s) => s.name == row.subject, orElse: () => Subject.math),
      extractedQuestionText: row.originalText,
      normalizedQuestionText: row.correctedText,
      contentFormat: domain.QuestionContentFormat.plain,
      tags: tags,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      lastReviewedAt: domain.QuestionRecord.lastReviewedAtFromTags(tags),
      nextReviewAt: row.nextReviewAt,
      reviewCount: row.reviewCount,
      isFavorite: tags.contains(domain.QuestionRecord.favoriteTag),
      contentStatus: ContentStatus.values.firstWhere(
          (c) => c.name == row.contentStatus,
          orElse: () => ContentStatus.processing),
      masteryLevel: MasteryLevel.values.firstWhere(
          (m) => m.name == row.masteryLevel,
          orElse: () => MasteryLevel.newQuestion),
      analysisResult: analysisResult,
      savedExercises: savedExercises,
      aiTags: row.aiTags.isNotEmpty ? row.aiTags.split(',') : <String>[],
      aiKnowledgePoints: row.aiKnowledgePoints.isNotEmpty
          ? row.aiKnowledgePoints.split(',')
          : <String>[],
      customTags:
          row.customTags.isNotEmpty ? row.customTags.split(',') : <String>[],
      parentQuestionId: row.parentQuestionId,
      rootQuestionId: row.rootQuestionId,
      splitOrder: row.splitOrder,
      splitResult: splitResult,
      candidateAnalyses: candidateAnalyses,
      reflectionNote: row.reflectionNote,
      archivedAt: row.archivedAt,
      ocrConfidence: row.ocrConfidence,
      studentAnswer: row.studentAnswer,
      expectedAnswer: row.expectedAnswer,
      isCorrect: row.isCorrect,
      questionType: row.questionType == null
          ? null
          : domain.QuestionType.values.firstWhere(
              (t) => t.name == row.questionType,
              orElse: () => domain.QuestionType.other,
            ),
      lastAnalysisError: lastAnalysisError,
    );
  }

  GeneratedExercise _toExerciseModel(db.GeneratedExercise row) {
    final options = row.optionsJson == null || row.optionsJson!.isEmpty
        ? null
        : List<String>.from(jsonDecode(row.optionsJson!) as List);

    Map<String, dynamic>? diagramData;
    if (row.diagramDataJson != null && row.diagramDataJson!.isNotEmpty) {
      try {
        diagramData = jsonDecode(row.diagramDataJson!) as Map<String, dynamic>;
      } catch (_) {
        diagramData = null;
      }
    }

    return GeneratedExercise(
      id: row.id,
      questionId: row.questionId,
      generationMode: ExerciseGenerationMode.values.firstWhere(
        (mode) => mode.name == row.generationMode,
        orElse: () => ExerciseGenerationMode.practice,
      ),
      difficulty: row.difficulty,
      question: row.question,
      answer: row.answer,
      explanation: row.explanation ?? '',
      createdAt: row.createdAt,
      order: row.orderIndex,
      isCorrect: row.isCorrect,
      options: options,
      userAnswer: row.userAnswer,
      roundIndex: row.roundIndex,
      roundTotal: row.roundTotal,
      roundGroupId: row.roundGroupId,
      sourceExerciseId: row.sourceExerciseId,
      diagramData: diagramData,
    );
  }
}

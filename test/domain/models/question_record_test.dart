import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

void main() {
  test('copyWith replaces image path while retaining question data', () {
    final now = DateTime(2026, 7, 18);
    final source = QuestionRecord(
      id: 'q-1',
      imagePath: '/old/image.jpg',
      subject: Subject.math,
      extractedQuestionText: '题目',
      normalizedQuestionText: '题目',
      contentFormat: QuestionContentFormat.plain,
      tags: const <String>['tag'],
      createdAt: now,
      updatedAt: now,
      lastReviewedAt: null,
      reviewCount: 2,
      isFavorite: false,
      contentStatus: ContentStatus.ready,
      masteryLevel: MasteryLevel.reviewing,
      analysisResult: null,
    );

    final restored = source.copyWith(imagePath: '/new/imported-image.jpg');

    expect(restored.imagePath, '/new/imported-image.jpg');
    expect(restored.id, source.id);
    expect(restored.reviewCount, source.reviewCount);
    expect(restored.normalizedQuestionText, source.normalizedQuestionText);
  });

  test('favorite uses a durable system tag and survives JSON restore', () {
    final now = DateTime(2026, 7, 18);
    final source = QuestionRecord(
      id: 'q-favorite',
      imagePath: '',
      subject: Subject.math,
      extractedQuestionText: '题目',
      normalizedQuestionText: '题目',
      contentFormat: QuestionContentFormat.plain,
      tags: const <String>['tag'],
      createdAt: now,
      updatedAt: now,
      lastReviewedAt: null,
      reviewCount: 0,
      isFavorite: false,
      contentStatus: ContentStatus.ready,
      masteryLevel: MasteryLevel.newQuestion,
      analysisResult: null,
    );

    final favorite = source.withFavorite(true);
    final restored = QuestionRecord.fromJson(favorite.toJson());

    expect(favorite.isFavorite, isTrue);
    expect(favorite.persistentTags, contains(QuestionRecord.favoriteTag));
    expect(restored.isFavorite, isTrue);
    expect(restored.withFavorite(false).persistentTags,
        isNot(contains(QuestionRecord.favoriteTag)));
  });
  test('learning context persists through tags and JSON backup', () {
    final now = DateTime(2026, 7, 18);
    final question = QuestionRecord(
      id: 'q-context',
      imagePath: '',
      subject: Subject.math,
      extractedQuestionText: '题目',
      normalizedQuestionText: '题目',
      contentFormat: QuestionContentFormat.plain,
      tags: const <String>['代数'],
      createdAt: now,
      updatedAt: now,
      lastReviewedAt: null,
      reviewCount: 0,
      isFavorite: false,
      contentStatus: ContentStatus.ready,
      masteryLevel: MasteryLevel.newQuestion,
      analysisResult: null,
    ).withLearningContext(
      learningStage: '七年级上',
      difficulty: QuestionDifficulty.foundation,
      attemptStatus: AttemptStatus.wrongAttempt,
      studentWork: '通分时漏写分母',
    );

    final restored = QuestionRecord.fromJson(question.toJson());

    expect(restored.learningStage, '七年级上');
    expect(restored.difficulty, QuestionDifficulty.foundation);
    expect(restored.attemptStatus, AttemptStatus.wrongAttempt);
    expect(restored.studentWork, '通分时漏写分母');
    expect(restored.tags, contains('代数'));
    expect(restored.allTags.any((tag) => tag.startsWith('__system_')), isFalse);
  });

  test('reflection note survives JSON round-trip', () {
    final now = DateTime(2026, 7, 18);
    final question = QuestionRecord(
      id: 'q-reflection',
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
      reflectionNote: '符号判断要谨慎，分式方程要检验增根。',
    );

    final restored = QuestionRecord.fromJson(question.toJson());

    expect(restored.reflectionNote, '符号判断要谨慎，分式方程要检验增根。');
  });

  test('reflection note defaults to null and copyWith updates it', () {
    final now = DateTime(2026, 7, 18);
    final question = QuestionRecord(
      id: 'q-reflection-copy',
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
    );

    expect(question.reflectionNote, isNull);

    final updated = question.copyWith(reflectionNote: '新增的反思内容');
    expect(updated.reflectionNote, '新增的反思内容');
    expect(question.reflectionNote, isNull,
        reason: 'copyWith must not mutate the source');

    final restored = QuestionRecord.fromJson(updated.toJson());
    expect(restored.reflectionNote, '新增的反思内容');
  });

  test('archivedAt survives JSON round-trip', () {
    final now = DateTime(2026, 7, 18);
    final archivedAt = DateTime(2026, 6, 30, 10, 30);
    final question = QuestionRecord(
      id: 'q-archived',
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
      archivedAt: archivedAt,
    );

    final restored = QuestionRecord.fromJson(question.toJson());

    expect(restored.archivedAt, archivedAt);
    expect(restored.isArchived, isTrue);
  });

  test('archive/unarchive methods work', () {
    final now = DateTime(2026, 7, 18);
    final question = QuestionRecord(
      id: 'q-archive-toggle',
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
    );

    expect(question.archivedAt, isNull);
    expect(question.isArchived, isFalse);

    final archived = question.archive();
    expect(archived.archivedAt, isNotNull);
    expect(archived.isArchived, isTrue);
    expect(question.isArchived, isFalse,
        reason: 'archive must not mutate the source');

    final unarchived = archived.unarchive();
    expect(unarchived.archivedAt, isNull);
    expect(unarchived.isArchived, isFalse);
    expect(archived.isArchived, isTrue,
        reason: 'unarchive must not mutate the source');
  });

  group('Phase 2 schema 扩展字段', () {
    QuestionRecord _base() {
      final now = DateTime(2026, 7, 21);
      return QuestionRecord(
        id: 'q-schema',
        imagePath: '/img.jpg',
        subject: Subject.math,
        extractedQuestionText: 'OCR 原文',
        normalizedQuestionText: '用户校对',
        contentFormat: QuestionContentFormat.plain,
        tags: const <String>[],
        createdAt: now,
        updatedAt: now,
        lastReviewedAt: null,
        reviewCount: 0,
        isFavorite: false,
        contentStatus: ContentStatus.analysisFailed,
        masteryLevel: MasteryLevel.newQuestion,
        analysisResult: null,
        lastAnalysisError: 'AI 超时',
        originalImageFilename: 'photo.jpg',
        aiReconstructedText: 'AI 重构题干',
      );
    }

    test('新字段 round-trip', () {
      final restored = QuestionRecord.fromJson(_base().toJson());
      expect(restored.lastAnalysisError, 'AI 超时');
      expect(restored.originalImageFilename, 'photo.jpg');
      expect(restored.aiReconstructedText, 'AI 重构题干');
      expect(restored.contentStatus, ContentStatus.analysisFailed);
    });

    test('老草稿（缺新字段）回落 null/false', () {
      final now = DateTime(2026, 7, 21);
      final legacy = QuestionRecord(
        id: 'q-legacy',
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
        contentStatus: ContentStatus.ready,
        masteryLevel: MasteryLevel.newQuestion,
        analysisResult: null,
      );
      final json = legacy.toJson();
      // 老草稿序列化仍包含新字段（值为 null）
      expect(json['lastAnalysisError'], isNull);
      expect(json['originalImageFilename'], isNull);
      expect(json['aiReconstructedText'], isNull);
      // 回读后字段为 null
      final restored = QuestionRecord.fromJson(json);
      expect(restored.lastAnalysisError, isNull);
      expect(restored.originalImageFilename, isNull);
      expect(restored.aiReconstructedText, isNull);
    });

    test('copyWith 保留 lastAnalysisError，withLastAnalysisError 可清空', () {
      final base = _base();
      // copyWith 不传 lastAnalysisError → 保留
      final kept = base.copyWith(contentStatus: ContentStatus.ready);
      expect(kept.lastAnalysisError, 'AI 超时',
          reason: 'copyWith 不传应保留旧值');
      // copyWith 传 null → 仍保留（?? 语义）
      final stillKept =
          base.copyWith(contentStatus: ContentStatus.ready);
      expect(stillKept.lastAnalysisError, 'AI 超时');
      // withLastAnalysisError(null) → 清空
      final cleared = base.withLastAnalysisError(null);
      expect(cleared.lastAnalysisError, isNull,
          reason: 'withLastAnalysisError(null) 必须能清空');
      // withLastAnalysisError 覆盖
      final updated = base.withLastAnalysisError('新错误');
      expect(updated.lastAnalysisError, '新错误');
    });

    test('copyWith 覆盖 aiReconstructedText / originalImageFilename', () {
      final base = _base();
      final updated = base.copyWith(
        aiReconstructedText: '新 AI 文本',
        originalImageFilename: 'new.jpg',
      );
      expect(updated.aiReconstructedText, '新 AI 文本');
      expect(updated.originalImageFilename, 'new.jpg');
      // 不传时保留
      final kept = base.copyWith(contentStatus: ContentStatus.ready);
      expect(kept.aiReconstructedText, 'AI 重构题干');
      expect(kept.originalImageFilename, 'photo.jpg');
    });

    test('ContentStatus values round-trip', () {
      for (final status in ContentStatus.values) {
        final record = _base().copyWith(contentStatus: status);
        final restored = QuestionRecord.fromJson(record.toJson());
        expect(restored.contentStatus, status,
            reason: '${status.name} 应能 round-trip');
      }
    });
  });
}

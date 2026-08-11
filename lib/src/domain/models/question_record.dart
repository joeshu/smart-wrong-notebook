import 'analysis_result.dart';
import 'content_status.dart';
import 'generated_exercise.dart';
import 'learning_context.dart';
import 'mastery_level.dart';
import 'mistake_category.dart';
import 'question_split_result.dart';
import 'question_source.dart';
import 'question_type.dart';
import 'subject.dart';

enum QuestionContentFormat { plain, latexMixed }

enum CandidateAnalysisStatus { success, failed }

class CandidateAnalysisSnapshot {
  const CandidateAnalysisSnapshot({
    required this.candidateId,
    required this.order,
    required this.questionText,
    this.analysisResult,
    this.savedExercises = const [],
    this.subject,
    this.aiTags = const [],
    this.aiKnowledgePoints = const [],
    this.status = CandidateAnalysisStatus.success,
    this.errorMessage,
  });

  factory CandidateAnalysisSnapshot.fromJson(Map<String, dynamic> json) {
    final analysisJson = json['analysisResult'] as Map<String, dynamic>?;
    final exercisesJson = json['savedExercises'] as List? ?? const <Object>[];
    final analysisResult =
        analysisJson != null ? AnalysisResult.fromJson(analysisJson) : null;
    return CandidateAnalysisSnapshot(
      candidateId: json['candidateId'] as String? ?? '',
      order: json['order'] as int? ?? 0,
      questionText: json['questionText'] as String? ?? '',
      analysisResult: analysisResult,
      savedExercises: exercisesJson
          .map((item) =>
              GeneratedExercise.fromJson(item as Map<String, dynamic>))
          .toList(),
      subject: _parseSubjectFromJson(json['subject'] as String?),
      aiTags: List<String>.from(json['aiTags'] as List? ?? const <String>[]),
      aiKnowledgePoints: List<String>.from(
          json['aiKnowledgePoints'] as List? ?? const <String>[]),
      status: _parseCandidateAnalysisStatus(
        json['status'] as String?,
        analysisResult: analysisResult,
      ),
      errorMessage: _nullableString(json['errorMessage']),
    );
  }

  final String candidateId;
  final int order;
  final String questionText;
  final AnalysisResult? analysisResult;
  final List<GeneratedExercise> savedExercises;
  final Subject? subject;
  final List<String> aiTags;
  final List<String> aiKnowledgePoints;
  final CandidateAnalysisStatus status;
  final String? errorMessage;

  bool get isSuccessful =>
      status == CandidateAnalysisStatus.success && analysisResult != null;

  CandidateAnalysisSnapshot copyWith({
    String? candidateId,
    int? order,
    String? questionText,
    AnalysisResult? analysisResult,
    List<GeneratedExercise>? savedExercises,
    Subject? subject,
    List<String>? aiTags,
    List<String>? aiKnowledgePoints,
    CandidateAnalysisStatus? status,
    String? errorMessage,
  }) {
    return CandidateAnalysisSnapshot(
      candidateId: candidateId ?? this.candidateId,
      order: order ?? this.order,
      questionText: questionText ?? this.questionText,
      analysisResult: analysisResult ?? this.analysisResult,
      savedExercises: savedExercises ?? this.savedExercises,
      subject: subject ?? this.subject,
      aiTags: aiTags ?? this.aiTags,
      aiKnowledgePoints: aiKnowledgePoints ?? this.aiKnowledgePoints,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'candidateId': candidateId,
      'order': order,
      'questionText': questionText,
      'analysisResult': analysisResult?.toJson(),
      'savedExercises':
          savedExercises.map((exercise) => exercise.toJson()).toList(),
      'subject': subject?.name,
      'aiTags': aiTags,
      'aiKnowledgePoints': aiKnowledgePoints,
      'status': status.name,
      'errorMessage': errorMessage,
    };
  }
}

CandidateAnalysisStatus _parseCandidateAnalysisStatus(
  String? value, {
  required AnalysisResult? analysisResult,
}) {
  for (final status in CandidateAnalysisStatus.values) {
    if (status.name == value) return status;
  }
  return analysisResult != null
      ? CandidateAnalysisStatus.success
      : CandidateAnalysisStatus.failed;
}

Subject? _parseSubjectFromJson(String? value) {
  if (value == null || value.isEmpty) return null;
  for (final subject in Subject.values) {
    if (subject.name == value || subject.label == value) return subject;
  }
  return null;
}

String? _nullableString(Object? value) {
  final text = value as String?;
  return text == null || text.isEmpty ? null : text;
}

int? _nullableInt(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

class QuestionRecord {
  const QuestionRecord({
    required this.id,
    required this.imagePath,
    required this.subject,
    required this.extractedQuestionText,
    required this.normalizedQuestionText,
    required this.contentFormat,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    required this.lastReviewedAt,
    required this.reviewCount,
    required this.isFavorite,
    required this.contentStatus,
    required this.masteryLevel,
    required this.analysisResult,
    this.nextReviewAt,
    this.savedExercises = const [],
    this.aiTags = const [],
    this.aiKnowledgePoints = const [],
    this.customTags = const [],
    this.splitResult,
    this.candidateAnalyses = const [],
    this.parentQuestionId,
    this.rootQuestionId,
    this.splitOrder,
    this.studentAnswer,
    this.expectedAnswer,
    this.isCorrect,
    this.reflectionNote,
    this.ocrConfidence,
    this.archivedAt,
    this.questionType,
    this.lastAnalysisError,
    this.originalImageFilename,
    this.aiReconstructedText,
  });

  static const favoriteTag = '__system_favorite';
  static const _lastReviewedAtPrefix = '__system_last_reviewed_at:';

  static DateTime? lastReviewedAtFromTags(Iterable<String> tags) {
    for (final tag in tags) {
      if (tag.startsWith(_lastReviewedAtPrefix)) {
        return DateTime.tryParse(tag.substring(_lastReviewedAtPrefix.length));
      }
    }
    return null;
  }

  factory QuestionRecord.draft({
    required String id,
    required String imagePath,
    required Subject subject,
    required String recognizedText,
    QuestionContentFormat contentFormat = QuestionContentFormat.plain,
  }) {
    final now = DateTime.now();
    return QuestionRecord(
      id: id,
      imagePath: imagePath,
      subject: subject,
      extractedQuestionText: recognizedText,
      normalizedQuestionText: recognizedText,
      contentFormat: contentFormat,
      tags: const <String>[],
      createdAt: now,
      updatedAt: now,
      lastReviewedAt: null,
      nextReviewAt: now,
      reviewCount: 0,
      isFavorite: false,
      contentStatus: ContentStatus.processing,
      masteryLevel: MasteryLevel.newQuestion,
      analysisResult: null,
      savedExercises: const [],
      aiTags: const [],
      aiKnowledgePoints: const [],
      customTags: const [],
      parentQuestionId: null,
      rootQuestionId: null,
      splitOrder: null,
    );
  }

  factory QuestionRecord.fromJson(Map<String, dynamic> json) {
    final analysisResult = json['analysisResult'] != null
        ? AnalysisResult.fromJson(
            json['analysisResult'] as Map<String, dynamic>)
        : null;

    final savedExercisesJson = json['savedExercises'] as List?;
    final legacyExercisesJson = (json['analysisResult']
        as Map<String, dynamic>?)?['generatedExercises'] as List?;
    final extractedQuestionText = json['extractedQuestionText'] as String? ??
        json['recognizedText'] as String? ??
        '';
    final normalizedQuestionText = json['normalizedQuestionText'] as String? ??
        json['correctedText'] as String? ??
        extractedQuestionText;
    final formatName = json['contentFormat'] as String?;
    final splitResultJson = json['splitResult'] as Map<String, dynamic>?;
    final candidateAnalysesJson =
        json['candidateAnalyses'] as List? ?? const <Object>[];

    final savedExercises =
        (savedExercisesJson ?? legacyExercisesJson ?? const [])
            .map((e) => GeneratedExercise.fromJson(e as Map<String, dynamic>))
            .toList();

    final id = json['id'] as String? ?? '';
    final rawTags = List<String>.from(json['tags'] as List? ?? []);
    final isFavorite = (json['isFavorite'] as bool? ?? false) ||
        rawTags.contains(favoriteTag);

    return QuestionRecord(
      id: id,
      imagePath: json['imagePath'] as String? ?? '',
      subject: Subject.values.firstWhere(
        (s) => s.name == json['subject'],
        orElse: () => Subject.math,
      ),
      extractedQuestionText: extractedQuestionText,
      normalizedQuestionText: normalizedQuestionText,
      contentFormat: QuestionContentFormat.values.firstWhere(
        (format) => format.name == formatName,
        orElse: () => QuestionContentFormat.plain,
      ),
      tags: rawTags,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      lastReviewedAt: json['lastReviewedAt'] != null
          ? DateTime.tryParse(json['lastReviewedAt'] as String)
          : lastReviewedAtFromTags(rawTags),
      // Old scheduled records did not exist. Keep legacy mastered questions
      // complete, while all other legacy questions enter the queue immediately.
      nextReviewAt: json['nextReviewAt'] != null
          ? DateTime.tryParse(json['nextReviewAt'] as String)
          : (json['masteryLevel'] == MasteryLevel.mastered.name
              ? null
              : DateTime.tryParse(json['createdAt'] as String? ?? '')),
      reviewCount: json['reviewCount'] as int? ?? 0,
      isFavorite: isFavorite,
      contentStatus: ContentStatus.values.firstWhere(
        (s) => s.name == json['contentStatus'],
        orElse: () => ContentStatus.processing,
      ),
      masteryLevel: MasteryLevel.values.firstWhere(
        (m) => m.name == json['masteryLevel'],
        orElse: () => MasteryLevel.newQuestion,
      ),
      analysisResult: analysisResult,
      savedExercises: savedExercises
          .asMap()
          .entries
          .map((entry) => entry.value.copyWith(
                questionId: entry.value.questionId.isEmpty
                    ? id
                    : entry.value.questionId,
                order: entry.value.order ?? entry.key,
              ))
          .toList(),
      aiTags: List<String>.from(json['aiTags'] as List? ?? []),
      aiKnowledgePoints:
          List<String>.from(json['aiKnowledgePoints'] as List? ?? []),
      customTags: List<String>.from(json['customTags'] as List? ?? []),
      splitResult: splitResultJson != null
          ? QuestionSplitResult.fromJson(splitResultJson)
          : null,
      candidateAnalyses: candidateAnalysesJson
          .map((item) =>
              CandidateAnalysisSnapshot.fromJson(item as Map<String, dynamic>))
          .toList(),
      parentQuestionId: _nullableString(json['parentQuestionId']),
      rootQuestionId: _nullableString(json['rootQuestionId']),
      splitOrder: _nullableInt(json['splitOrder']),
      studentAnswer: _nullableString(json['studentAnswer']),
      expectedAnswer: json['expectedAnswer'] as String?,
      isCorrect: json['isCorrect'] as bool?,
      reflectionNote: json['reflectionNote'] as String?,
      ocrConfidence: (json['ocrConfidence'] as num?)?.toDouble(),
      archivedAt: json['archivedAt'] != null
          ? DateTime.parse(json['archivedAt'] as String)
          : null,
      questionType: json['questionType'] != null
          ? QuestionType.values.firstWhere(
              (t) => t.name == json['questionType'],
              orElse: () => QuestionType.other,
            )
          : null,
      lastAnalysisError: _nullableString(json['lastAnalysisError']),
      originalImageFilename: _nullableString(json['originalImageFilename']),
      aiReconstructedText: _nullableString(json['aiReconstructedText']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imagePath': imagePath,
      'subject': subject.name,
      'extractedQuestionText': extractedQuestionText,
      'normalizedQuestionText': normalizedQuestionText,
      'recognizedText': extractedQuestionText,
      'correctedText': normalizedQuestionText,
      'contentFormat': contentFormat.name,
      'tags': persistentTags,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastReviewedAt': lastReviewedAt?.toIso8601String(),
      'nextReviewAt': nextReviewAt?.toIso8601String(),
      'reviewCount': reviewCount,
      'isFavorite': isFavorite,
      'contentStatus': contentStatus.toString().split('.').last,
      'masteryLevel': masteryLevel.name,
      'analysisResult': analysisResult?.toJson(),
      'savedExercises':
          savedExercises.map((exercise) => exercise.toJson()).toList(),
      'aiTags': aiTags,
      'aiKnowledgePoints': aiKnowledgePoints,
      'customTags': customTags,
      'splitResult': splitResult?.toJson(),
      'candidateAnalyses':
          candidateAnalyses.map((candidate) => candidate.toJson()).toList(),
      'parentQuestionId': parentQuestionId,
      'rootQuestionId': rootQuestionId,
      'splitOrder': splitOrder,
      'studentAnswer': studentAnswer,
      'expectedAnswer': expectedAnswer,
      'isCorrect': isCorrect,
      'reflectionNote': reflectionNote,
      'ocrConfidence': ocrConfidence,
      'archivedAt': archivedAt?.toIso8601String(),
      'questionType': questionType?.name,
      'lastAnalysisError': lastAnalysisError,
      'originalImageFilename': originalImageFilename,
      'aiReconstructedText': aiReconstructedText,
    };
  }

  final String id;
  final String imagePath;
  final Subject subject;
  final String extractedQuestionText;
  final String normalizedQuestionText;
  final QuestionContentFormat contentFormat;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastReviewedAt;
  final DateTime? nextReviewAt;
  final int reviewCount;
  final bool isFavorite;
  final ContentStatus contentStatus;
  final MasteryLevel masteryLevel;
  final AnalysisResult? analysisResult;
  final List<GeneratedExercise> savedExercises;
  final List<String> aiTags;
  final List<String> aiKnowledgePoints;
  final List<String> customTags;
  final QuestionSplitResult? splitResult;
  final List<CandidateAnalysisSnapshot> candidateAnalyses;
  final String? parentQuestionId;
  final String? rootQuestionId;
  final int? splitOrder;
  final String? studentAnswer;
  final String? expectedAnswer;
  final bool? isCorrect;
  final String? reflectionNote;
  final double? ocrConfidence;
  final DateTime? archivedAt;
  final QuestionType? questionType;

  /// 最近一次 AI 分析失败的原因（friendlyAiErrorMessage 输出）。
  ///
  /// 仅在 [ContentStatus.analysisFailed] 或 [ContentStatus.failed] 时有值；
  /// 分析成功后由 [withLastAnalysisError] 清空。详情页据此展示失败原因，
  /// 而非仅显示"识别失败"通用文案。
  final String? lastAnalysisError;

  /// 原图原始文件名（用户选择图片时的文件名）。
  ///
  /// [ImageStorageService] 落盘时改用 UUID 命名，原始文件名丢失。此字段
  /// 在选图/导入时记录，详情页据此展示文件名，便于用户辨认题目来源。
  final String? originalImageFilename;

  /// AI 重构的题干文本。
  ///
  /// AI 分析可能返回 `AnalysisResult.reconstructedQuestionText`。之前实现
  /// 直接覆盖 `normalizedQuestionText`（用户校对文本），导致 OCR vs 校对
  /// 对照失效。现在 AI 重构文本独立存此字段，`normalizedQuestionText`
  /// 始终保留用户校对结果，详情页展示三段对照：
  /// OCR 原文 / 用户校对 / AI 重构。
  final String? aiReconstructedText;

  String get recognizedText => extractedQuestionText;
  String get correctedText => normalizedQuestionText;

  bool get isArchived => archivedAt != null;

  List<String> get allTags => [...aiTags, ...customTags];

  List<String> get persistentTags {
    final result = tags
        .where((tag) =>
            tag != favoriteTag && !tag.startsWith(_lastReviewedAtPrefix))
        .toList();
    if (isFavorite) result.add(favoriteTag);
    if (lastReviewedAt != null) {
      result.add('$_lastReviewedAtPrefix${lastReviewedAt!.toIso8601String()}');
    }
    return result;
  }

  QuestionRecord withFavorite(bool value) => copyWith(
        isFavorite: value,
        tags: (tags.where((tag) => tag != favoriteTag).toList()
          ..addAll(value ? <String>[favoriteTag] : const <String>[])),
      );

  String? get source => QuestionSourceCodec.read(tags);

  QuestionRecord withSource(String? value) => copyWith(
        tags: QuestionSourceCodec.write(tags, value),
      );

  MistakeCategory? get mistakeCategory => MistakeCategoryCodec.read(tags);

  String? get learningStage => LearningContextCodec.learningStage(tags);

  QuestionDifficulty? get difficulty => LearningContextCodec.difficulty(tags);

  AttemptStatus? get attemptStatus => LearningContextCodec.attemptStatus(tags);

  String? get studentWork => LearningContextCodec.studentWork(tags);

  QuestionRecord withLearningContext({
    String? learningStage,
    QuestionDifficulty? difficulty,
    AttemptStatus? attemptStatus,
    String? studentWork,
  }) => copyWith(
        tags: LearningContextCodec.write(
          tags: tags,
          learningStage: learningStage ?? this.learningStage,
          difficulty: difficulty ?? this.difficulty,
          attemptStatus: attemptStatus ?? this.attemptStatus,
          studentWork: studentWork ?? this.studentWork,
        ),
      );

  QuestionRecord withMistakeCategory(MistakeCategory? category) => copyWith(
        tags: MistakeCategoryCodec.write(tags, category),
      );

  QuestionRecord copyWith({
    String? extractedQuestionText,
    String? normalizedQuestionText,
    String? imagePath,
    QuestionContentFormat? contentFormat,
    Subject? subject,
    ContentStatus? contentStatus,
    AnalysisResult? analysisResult,
    List<GeneratedExercise>? savedExercises,
    MasteryLevel? masteryLevel,
    int? reviewCount,
    DateTime? lastReviewedAt,
    DateTime? nextReviewAt,
    List<String>? tags,
    bool? isFavorite,
    List<String>? aiTags,
    List<String>? aiKnowledgePoints,
    List<String>? customTags,
    QuestionSplitResult? splitResult,
    List<CandidateAnalysisSnapshot>? candidateAnalyses,
    String? parentQuestionId,
    String? rootQuestionId,
    int? splitOrder,
    String? studentAnswer,
    String? expectedAnswer,
    bool? isCorrect,
    String? reflectionNote,
    double? ocrConfidence,
    DateTime? archivedAt,
    QuestionType? questionType,
    String? lastAnalysisError,
    String? originalImageFilename,
    String? aiReconstructedText,
  }) {
    return QuestionRecord(
      id: id,
      imagePath: imagePath ?? this.imagePath,
      subject: subject ?? this.subject,
      extractedQuestionText:
          extractedQuestionText ?? this.extractedQuestionText,
      normalizedQuestionText:
          normalizedQuestionText ?? this.normalizedQuestionText,
      contentFormat: contentFormat ?? this.contentFormat,
      tags: tags ?? this.tags,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      nextReviewAt: nextReviewAt ?? this.nextReviewAt,
      reviewCount: reviewCount ?? this.reviewCount,
      isFavorite: isFavorite ?? this.isFavorite,
      contentStatus: contentStatus ?? this.contentStatus,
      masteryLevel: masteryLevel ?? this.masteryLevel,
      analysisResult: analysisResult ?? this.analysisResult,
      savedExercises: savedExercises ?? this.savedExercises,
      aiTags: aiTags ?? this.aiTags,
      aiKnowledgePoints: aiKnowledgePoints ?? this.aiKnowledgePoints,
      customTags: customTags ?? this.customTags,
      splitResult: splitResult ?? this.splitResult,
      candidateAnalyses: candidateAnalyses ?? this.candidateAnalyses,
      parentQuestionId: parentQuestionId ?? this.parentQuestionId,
      rootQuestionId: rootQuestionId ?? this.rootQuestionId,
      splitOrder: splitOrder ?? this.splitOrder,
      studentAnswer: studentAnswer ?? this.studentAnswer,
      expectedAnswer: expectedAnswer ?? this.expectedAnswer,
      isCorrect: isCorrect ?? this.isCorrect,
      reflectionNote: reflectionNote ?? this.reflectionNote,
      ocrConfidence: ocrConfidence ?? this.ocrConfidence,
      archivedAt: archivedAt ?? this.archivedAt,
      questionType: questionType ?? this.questionType,
      lastAnalysisError: lastAnalysisError ?? this.lastAnalysisError,
      originalImageFilename:
          originalImageFilename ?? this.originalImageFilename,
      aiReconstructedText: aiReconstructedText ?? this.aiReconstructedText,
    );
  }

  /// Updates OCR output while allowing nullable recognition fields to clear.
  QuestionRecord withOcrConfidence(
    double? value, {
    required String extractedQuestionText,
    required String normalizedQuestionText,
    required String? studentAnswer,
  }) {
    return QuestionRecord(
      id: id,
      imagePath: imagePath,
      subject: subject,
      extractedQuestionText: extractedQuestionText,
      normalizedQuestionText: normalizedQuestionText,
      contentFormat: contentFormat,
      tags: tags,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      lastReviewedAt: lastReviewedAt,
      nextReviewAt: nextReviewAt,
      reviewCount: reviewCount,
      isFavorite: isFavorite,
      contentStatus: contentStatus,
      masteryLevel: masteryLevel,
      analysisResult: analysisResult,
      savedExercises: savedExercises,
      aiTags: aiTags,
      aiKnowledgePoints: aiKnowledgePoints,
      customTags: customTags,
      splitResult: splitResult,
      candidateAnalyses: candidateAnalyses,
      parentQuestionId: parentQuestionId,
      rootQuestionId: rootQuestionId,
      splitOrder: splitOrder,
      studentAnswer: studentAnswer,
      expectedAnswer: expectedAnswer,
      isCorrect: isCorrect,
      reflectionNote: reflectionNote,
      ocrConfidence: value,
      archivedAt: archivedAt,
      questionType: questionType,
      lastAnalysisError: lastAnalysisError,
      originalImageFilename: originalImageFilename,
      aiReconstructedText: aiReconstructedText,
    );
  }

  /// Explicitly sets [archivedAt], allowing null to clear it.
  ///
  /// [copyWith] uses `?? this.archivedAt`, which keeps the existing value when
  /// `null` is passed. To clear the field (i.e. unarchive) we must bypass
  /// copyWith and construct the record directly.
  QuestionRecord withArchivedAt(DateTime? value) {
    return QuestionRecord(
      id: id,
      imagePath: imagePath,
      subject: subject,
      extractedQuestionText: extractedQuestionText,
      normalizedQuestionText: normalizedQuestionText,
      contentFormat: contentFormat,
      tags: tags,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      lastReviewedAt: lastReviewedAt,
      nextReviewAt: nextReviewAt,
      reviewCount: reviewCount,
      isFavorite: isFavorite,
      contentStatus: contentStatus,
      masteryLevel: masteryLevel,
      analysisResult: analysisResult,
      savedExercises: savedExercises,
      aiTags: aiTags,
      aiKnowledgePoints: aiKnowledgePoints,
      customTags: customTags,
      splitResult: splitResult,
      candidateAnalyses: candidateAnalyses,
      parentQuestionId: parentQuestionId,
      rootQuestionId: rootQuestionId,
      splitOrder: splitOrder,
      studentAnswer: studentAnswer,
      expectedAnswer: expectedAnswer,
      isCorrect: isCorrect,
      reflectionNote: reflectionNote,
      archivedAt: value,
      questionType: questionType,
      lastAnalysisError: lastAnalysisError,
      originalImageFilename: originalImageFilename,
      aiReconstructedText: aiReconstructedText,
    );
  }

  /// Marks this question as archived (e.g. from a previous semester).
  QuestionRecord archive() => withArchivedAt(DateTime.now());

  /// Removes the archive marker so the question shows up in the default list.
  QuestionRecord unarchive() => withArchivedAt(null);

  /// Explicitly sets [expectedAnswer], allowing null to clear it.
  ///
  /// [copyWith] uses `?? this.expectedAnswer`, which keeps the existing value
  /// when `null` is passed. To clear the field we must bypass copyWith and
  /// construct the record directly.
  QuestionRecord withExpectedAnswer(String? value) {
    return QuestionRecord(
      id: id,
      imagePath: imagePath,
      subject: subject,
      extractedQuestionText: extractedQuestionText,
      normalizedQuestionText: normalizedQuestionText,
      contentFormat: contentFormat,
      tags: tags,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      lastReviewedAt: lastReviewedAt,
      nextReviewAt: nextReviewAt,
      reviewCount: reviewCount,
      isFavorite: isFavorite,
      contentStatus: contentStatus,
      masteryLevel: masteryLevel,
      analysisResult: analysisResult,
      savedExercises: savedExercises,
      aiTags: aiTags,
      aiKnowledgePoints: aiKnowledgePoints,
      customTags: customTags,
      splitResult: splitResult,
      candidateAnalyses: candidateAnalyses,
      parentQuestionId: parentQuestionId,
      rootQuestionId: rootQuestionId,
      splitOrder: splitOrder,
      studentAnswer: studentAnswer,
      expectedAnswer: value,
      isCorrect: isCorrect,
      reflectionNote: reflectionNote,
      ocrConfidence: ocrConfidence,
      archivedAt: archivedAt,
      questionType: questionType,
      lastAnalysisError: lastAnalysisError,
      originalImageFilename: originalImageFilename,
      aiReconstructedText: aiReconstructedText,
    );
  }

  /// Explicitly sets [isCorrect], allowing null to clear it.
  ///
  /// [copyWith] uses `?? this.isCorrect`, which keeps the existing value when
  /// `null` is passed. To clear the field we must bypass copyWith and
  /// construct the record directly.
  QuestionRecord withIsCorrect(bool? value) {
    return QuestionRecord(
      id: id,
      imagePath: imagePath,
      subject: subject,
      extractedQuestionText: extractedQuestionText,
      normalizedQuestionText: normalizedQuestionText,
      contentFormat: contentFormat,
      tags: tags,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      lastReviewedAt: lastReviewedAt,
      nextReviewAt: nextReviewAt,
      reviewCount: reviewCount,
      isFavorite: isFavorite,
      contentStatus: contentStatus,
      masteryLevel: masteryLevel,
      analysisResult: analysisResult,
      savedExercises: savedExercises,
      aiTags: aiTags,
      aiKnowledgePoints: aiKnowledgePoints,
      customTags: customTags,
      splitResult: splitResult,
      candidateAnalyses: candidateAnalyses,
      parentQuestionId: parentQuestionId,
      rootQuestionId: rootQuestionId,
      splitOrder: splitOrder,
      studentAnswer: studentAnswer,
      expectedAnswer: expectedAnswer,
      isCorrect: value,
      reflectionNote: reflectionNote,
      ocrConfidence: ocrConfidence,
      archivedAt: archivedAt,
      questionType: questionType,
      lastAnalysisError: lastAnalysisError,
      originalImageFilename: originalImageFilename,
      aiReconstructedText: aiReconstructedText,
    );
  }

  /// Explicitly sets [lastAnalysisError], allowing null to clear it.
  ///
  /// [copyWith] uses `?? this.lastAnalysisError`, which keeps the existing
  /// value when `null` is passed. AI 分析成功后需要清空失败原因，必须用此方法。
  QuestionRecord withLastAnalysisError(String? value) {
    return QuestionRecord(
      id: id,
      imagePath: imagePath,
      subject: subject,
      extractedQuestionText: extractedQuestionText,
      normalizedQuestionText: normalizedQuestionText,
      contentFormat: contentFormat,
      tags: tags,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      lastReviewedAt: lastReviewedAt,
      nextReviewAt: nextReviewAt,
      reviewCount: reviewCount,
      isFavorite: isFavorite,
      contentStatus: contentStatus,
      masteryLevel: masteryLevel,
      analysisResult: analysisResult,
      savedExercises: savedExercises,
      aiTags: aiTags,
      aiKnowledgePoints: aiKnowledgePoints,
      customTags: customTags,
      splitResult: splitResult,
      candidateAnalyses: candidateAnalyses,
      parentQuestionId: parentQuestionId,
      rootQuestionId: rootQuestionId,
      splitOrder: splitOrder,
      studentAnswer: studentAnswer,
      expectedAnswer: expectedAnswer,
      isCorrect: isCorrect,
      reflectionNote: reflectionNote,
      ocrConfidence: ocrConfidence,
      archivedAt: archivedAt,
      questionType: questionType,
      lastAnalysisError: value,
      originalImageFilename: originalImageFilename,
      aiReconstructedText: aiReconstructedText,
    );
  }
}

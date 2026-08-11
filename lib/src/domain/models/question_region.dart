import 'dart:ui';

import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

/// A user-confirmed region of a worksheet page.
/// Coordinates are normalized (0..1) so they survive display scaling.
class QuestionRegion {
  const QuestionRegion({
    required this.id,
    required this.normalizedRect,
    this.detectedNumber,
    this.recognizedText,
    this.originalRecognizedText,
    this.questionStem,
    this.formulas = const <String>[],
    this.tables = const <String>[],
    this.options = const <String>[],
    this.documentBlocks = const <DocumentBlock>[],
    this.contentFormatHint,
    this.recognizedBlockTypes = const <String>[],
    this.subject,
    this.questionType,
    this.analyzeWithAi = true,
    this.reviewStatus = QuestionRegionReviewStatus.accepted,
    this.confidence = 1,
    this.source = QuestionRegionSource.manual,
    this.diagramNote,
    this.studentAnswer,
    this.aiNormalizedText,
    this.confirmedFields = const <String>{},
    this.parentRegionId,
    this.readingOrder,
    this.columnIndex = 0,
    this.assemblyRiskCodes = const <QuestionAssemblyRiskCode>{},
  });

  final String id;
  final Rect normalizedRect;
  final String? detectedNumber;
  /// Text reconstructed by the document service for this candidate question.
  final String? recognizedText;
  /// Immutable source text from the document service; enables comparison/reset.
  final String? originalRecognizedText;
  /// User-reviewed question stem, separated from formula and table blocks.
  final String? questionStem;
  final List<String> formulas;
  final List<String> tables;
  /// User-edited choice options. Empty means not opened; UI may auto-parse.
  final List<String> options;
  /// Ordered source blocks, preserving reading order.
  final List<DocumentBlock> documentBlocks;
  final String? contentFormatHint;
  final List<String> recognizedBlockTypes;
  final Subject? subject;
  final String? questionType;
  final bool analyzeWithAi;
  final QuestionRegionReviewStatus reviewStatus;
  final double confidence;
  final QuestionRegionSource source;
  /// Empty string explicitly clears this note.
  final String? diagramNote;
  final String? studentAnswer;
  final String? aiNormalizedText;
  final Set<String> confirmedFields;
  /// Parent question for a sub-question. Null means a top-level question.
  final String? parentRegionId;
  /// Stable zero-based order after page-level question assembly.
  final int? readingOrder;
  /// Zero-based visual column. Single-column pages use 0.
  final int columnIndex;
  final Set<QuestionAssemblyRiskCode> assemblyRiskCodes;

  /// Nullable fields use a sentinel so passing null explicitly clears the value.
  QuestionRegion copyWith({
    Rect? normalizedRect,
    Object? detectedNumber = _keep,
    Object? recognizedText = _keep,
    Object? originalRecognizedText = _keep,
    Object? questionStem = _keep,
    List<String>? formulas,
    List<String>? tables,
    List<String>? options,
    List<DocumentBlock>? documentBlocks,
    Object? contentFormatHint = _keep,
    List<String>? recognizedBlockTypes,
    Object? subject = _keep,
    Object? questionType = _keep,
    bool? analyzeWithAi,
    QuestionRegionReviewStatus? reviewStatus,
    double? confidence,
    QuestionRegionSource? source,
    Object? diagramNote = _keep,
    Object? studentAnswer = _keep,
    Object? aiNormalizedText = _keep,
    Set<String>? confirmedFields,
    Object? parentRegionId = _keep,
    Object? readingOrder = _keep,
    int? columnIndex,
    Set<QuestionAssemblyRiskCode>? assemblyRiskCodes,
  }) {
    return QuestionRegion(
      id: id,
      normalizedRect: normalizedRect ?? this.normalizedRect,
      detectedNumber: identical(detectedNumber, _keep) ? this.detectedNumber : detectedNumber as String?,
      recognizedText: identical(recognizedText, _keep) ? this.recognizedText : recognizedText as String?,
      originalRecognizedText: identical(originalRecognizedText, _keep) ? this.originalRecognizedText : originalRecognizedText as String?,
      questionStem: identical(questionStem, _keep) ? this.questionStem : questionStem as String?,
      formulas: formulas ?? this.formulas,
      tables: tables ?? this.tables,
      options: options ?? this.options,
      documentBlocks: documentBlocks ?? this.documentBlocks,
      contentFormatHint: identical(contentFormatHint, _keep) ? this.contentFormatHint : contentFormatHint as String?,
      recognizedBlockTypes: recognizedBlockTypes ?? this.recognizedBlockTypes,
      subject: identical(subject, _keep) ? this.subject : subject as Subject?,
      questionType: identical(questionType, _keep) ? this.questionType : questionType as String?,
      analyzeWithAi: analyzeWithAi ?? this.analyzeWithAi,
      reviewStatus: reviewStatus ?? this.reviewStatus,
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
      diagramNote: identical(diagramNote, _keep) ? this.diagramNote : diagramNote as String?,
      studentAnswer: identical(studentAnswer, _keep) ? this.studentAnswer : studentAnswer as String?,
      aiNormalizedText: identical(aiNormalizedText, _keep) ? this.aiNormalizedText : aiNormalizedText as String?,
      confirmedFields: confirmedFields ?? this.confirmedFields,
      parentRegionId: identical(parentRegionId, _keep) ? this.parentRegionId : parentRegionId as String?,
      readingOrder: identical(readingOrder, _keep) ? this.readingOrder : readingOrder as int?,
      columnIndex: columnIndex ?? this.columnIndex,
      assemblyRiskCodes: assemblyRiskCodes ?? this.assemblyRiskCodes,
    );
  }
}

const Object _keep = Object();

/// Keep the first three values in place: persisted v1 drafts use enum indexes.
enum DocumentBlockType { text, formula, table, handwriting, diagram, image, answerMark, unknown }

enum DocumentAuthorRole { printedPrompt, studentAnswer, teacherMark, unknown }

enum DocumentContentFormat { plainText, markdown, latex, tableGrid, imageReference }

enum DocumentRecognitionEngine {
  printedOcr,
  handwritingOcr,
  formulaRecognizer,
  tableRecognizer,
  visionLayout,
  sourceImage,
  unknown,
}

enum DocumentRecognitionStatus { recognized, needsSpecialist, sourcePreserved, failed }

enum DocumentBlockRiskCode {
  lowConfidence,
  roleUncertain,
  contentTruncated,
  structureConflict,
  formulaIncomplete,
  tableStructureInvalid,
  diagramMissing,
}

class DocumentBlock {
  const DocumentBlock({
    required this.type,
    required this.content,
    this.id,
    this.polygon = const <Offset>[],
    this.authorRole = DocumentAuthorRole.unknown,
    this.inkColor,
    this.confidence = 1,
    this.riskCodes = const <DocumentBlockRiskCode>{},
    this.sourceCropRef,
    this.parentBlockId,
    this.contentFormat = DocumentContentFormat.plainText,
    this.recognitionEngine = DocumentRecognitionEngine.unknown,
    this.recognitionStatus = DocumentRecognitionStatus.recognized,
  });
  final DocumentBlockType type;
  final String content;
  final String? id;
  /// Normalized page coordinates in reading order.
  final List<Offset> polygon;
  final DocumentAuthorRole authorRole;
  final String? inkColor;
  final double confidence;
  final Set<DocumentBlockRiskCode> riskCodes;
  final String? sourceCropRef;
  final String? parentBlockId;
  final DocumentContentFormat contentFormat;
  final DocumentRecognitionEngine recognitionEngine;
  final DocumentRecognitionStatus recognitionStatus;

  DocumentBlock copyWith({
    DocumentBlockType? type,
    String? content,
    String? id,
    List<Offset>? polygon,
    DocumentAuthorRole? authorRole,
    String? inkColor,
    double? confidence,
    Set<DocumentBlockRiskCode>? riskCodes,
    String? sourceCropRef,
    String? parentBlockId,
    DocumentContentFormat? contentFormat,
    DocumentRecognitionEngine? recognitionEngine,
    DocumentRecognitionStatus? recognitionStatus,
  }) => DocumentBlock(
    type: type ?? this.type,
    content: content ?? this.content,
    id: id ?? this.id,
    polygon: polygon ?? this.polygon,
    authorRole: authorRole ?? this.authorRole,
    inkColor: inkColor ?? this.inkColor,
    confidence: confidence ?? this.confidence,
    riskCodes: riskCodes ?? this.riskCodes,
    sourceCropRef: sourceCropRef ?? this.sourceCropRef,
    parentBlockId: parentBlockId ?? this.parentBlockId,
    contentFormat: contentFormat ?? this.contentFormat,
    recognitionEngine: recognitionEngine ?? this.recognitionEngine,
    recognitionStatus: recognitionStatus ?? this.recognitionStatus,
  );
}

enum RecognitionPageType {
  printedSingleQuestion,
  markedWorksheet,
  multiQuestionPage,
  essayPage,
  answerSheet,
  handwrittenNotebook,
  screenshot,
  unknown,
}

enum RecognitionSourceType { camera, gallery, pdf, screenshot, unknown }

class RecognitionDocument {
  const RecognitionDocument({
    required this.id,
    required this.pageType,
    required this.regions,
    this.sourceType = RecognitionSourceType.unknown,
    this.pageCount = 1,
    this.qualityIssues = const <String>[],
    this.blocks = const <DocumentBlock>[],
    this.routingConfidence = 0,
  });

  final String id;
  final RecognitionSourceType sourceType;
  final RecognitionPageType pageType;
  final int pageCount;
  final List<String> qualityIssues;
  final List<DocumentBlock> blocks;
  final List<QuestionRegion> regions;
  /// Confidence of page routing only; never substitutes for OCR confidence.
  final double routingConfidence;
}

enum QuestionRegionReviewStatus { accepted, ignored }
enum QuestionRegionSource { manual, layoutModel }

enum QuestionAssemblyRiskCode {
  readingOrderUncertain,
  parentQuestionUncertain,
  authorRoleUncertain,
  specialistRetryRequired,
}

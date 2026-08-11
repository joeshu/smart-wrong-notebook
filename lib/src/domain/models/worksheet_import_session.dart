import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';

/// An in-memory staging area for a multi-page worksheet import.
/// Pages become independent question drafts only after the user reviews them.
class WorksheetImportSession {
  const WorksheetImportSession({
    required this.id,
    required this.pages,
    required this.sourcePageIds,
    required this.createdAt,
    this.processedSourcePageIds = const <String>{},
    this.lastProcessedId,
    this.autoAnalyze = false,
  });

  final String id;
  final List<QuestionRecord> pages;
  final Set<String> sourcePageIds;
  final DateTime createdAt;

  final Set<String> processedSourcePageIds;

  final String? lastProcessedId;

  /// Whether the importer should continue through remaining question
  /// candidates without opening a result page after every successful analysis.
  /// 持久化到仓库，跨进程恢复；空 session 重建时回到默认 false。
  final bool autoAnalyze;

  int get pageCount => pages.length;

  int get sourcePageCount => sourcePageIds.length;

  int get processedSourcePageCount => processedSourcePageIds.length;

  bool isSourcePageProcessed(String pageId) => processedSourcePageIds.contains(pageId);

  WorksheetImportSession copyWith({
    List<QuestionRecord>? pages,
    Set<String>? processedSourcePageIds,
    String? lastProcessedId,
    bool? autoAnalyze,
  }) {
    return WorksheetImportSession(
      id: id,
      pages: pages ?? this.pages,
      sourcePageIds: sourcePageIds,
      createdAt: createdAt,
      processedSourcePageIds: processedSourcePageIds ?? this.processedSourcePageIds,
      lastProcessedId: lastProcessedId ?? this.lastProcessedId,
      autoAnalyze: autoAnalyze ?? this.autoAnalyze,
    );
  }
}

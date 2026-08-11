class WorksheetReviewSummary {
  const WorksheetReviewSummary({
    required this.sourcePageId,
    required this.aiCount,
    required this.ocrCount,
    required this.ignoredCount,
  });

  final String sourcePageId;
  final int aiCount;
  final int ocrCount;
  final int ignoredCount;
}

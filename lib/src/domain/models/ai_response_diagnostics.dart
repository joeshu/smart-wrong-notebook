/// Persisted AI response diagnostics.
///
/// This object is safe-by-default: [rawResponse] is null unless a future explicit
/// local diagnostics switch chooses to retain it. The summary fields are enough
/// to correlate bugs without storing student content.
class AiResponseDiagnostics {
  const AiResponseDiagnostics({
    required this.contentLength,
    required this.contentFingerprint,
    required this.markdownWrapped,
    required this.repairStrategy,
    required this.capturedAt,
    this.rawResponse,
    this.retentionDays,
  });

  final int contentLength;
  final String contentFingerprint;
  final bool markdownWrapped;
  final String repairStrategy;
  final DateTime capturedAt;
  final String? rawResponse;
  final int? retentionDays;

  bool get hasRawResponse => rawResponse != null && rawResponse!.isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'contentLength': contentLength,
        'contentFingerprint': contentFingerprint,
        'markdownWrapped': markdownWrapped,
        'repairStrategy': repairStrategy,
        'capturedAt': capturedAt.toIso8601String(),
        if (rawResponse != null) 'rawResponse': rawResponse,
        if (retentionDays != null) 'retentionDays': retentionDays,
      };

  factory AiResponseDiagnostics.fromJson(Map<String, dynamic> json) =>
      AiResponseDiagnostics(
        contentLength: json['contentLength'] as int? ?? 0,
        contentFingerprint: json['contentFingerprint'] as String? ?? '',
        markdownWrapped: json['markdownWrapped'] as bool? ?? false,
        repairStrategy: json['repairStrategy'] as String? ?? 'unknown',
        capturedAt: DateTime.tryParse(json['capturedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        rawResponse: json['rawResponse'] as String?,
        retentionDays: json['retentionDays'] as int?,
      );

  AiResponseDiagnostics withoutRawResponse() => AiResponseDiagnostics(
        contentLength: contentLength,
        contentFingerprint: contentFingerprint,
        markdownWrapped: markdownWrapped,
        repairStrategy: repairStrategy,
        capturedAt: capturedAt,
        retentionDays: retentionDays,
      );
}

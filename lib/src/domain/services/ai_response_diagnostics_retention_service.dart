import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';

class AiResponseDiagnosticsRetentionService {
  const AiResponseDiagnosticsRetentionService();

  QuestionRecord stripRawResponses(QuestionRecord record) {
    return _mapRecord(record, _stripRaw);
  }

  QuestionRecord expireRawResponses(
    QuestionRecord record, {
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    return _mapRecord(record, (analysis) {
      final diagnostics = analysis.responseDiagnostics;
      if (diagnostics == null || !diagnostics.hasRawResponse) return analysis;
      final days = diagnostics.retentionDays;
      if (days == null) return analysis;
      final expiresAt = diagnostics.capturedAt.add(Duration(days: days));
      if (reference.isBefore(expiresAt)) return analysis;
      return _stripRaw(analysis);
    });
  }

  QuestionRecord _mapRecord(
    QuestionRecord record,
    AnalysisResult Function(AnalysisResult) mapper,
  ) {
    final analysis = record.analysisResult;
    var changed = false;
    AnalysisResult? mappedAnalysis;
    if (analysis != null) {
      mappedAnalysis = mapper(analysis);
      changed = !identical(mappedAnalysis, analysis);
    }
    final mappedCandidates = record.candidateAnalyses
        .map((candidate) {
          final candidateAnalysis = candidate.analysisResult;
          if (candidateAnalysis == null) return candidate;
          final mapped = mapper(candidateAnalysis);
          if (identical(mapped, candidateAnalysis)) return candidate;
          changed = true;
          return candidate.copyWith(analysisResult: mapped);
        })
        .toList(growable: false);
    if (!changed) return record;
    return record.copyWith(
      analysisResult: mappedAnalysis,
      candidateAnalyses: mappedCandidates,
    );
  }

  AnalysisResult _stripRaw(AnalysisResult analysis) {
    final diagnostics = analysis.responseDiagnostics;
    if (diagnostics == null || !diagnostics.hasRawResponse) return analysis;
    return analysis.copyWith(
      responseDiagnostics: diagnostics.withoutRawResponse(),
    );
  }
}

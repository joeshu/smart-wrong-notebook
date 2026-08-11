import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';

/// Persists a completed analysis before the caller navigates or advances a queue.
///
/// The repository's stable question id remains the idempotency key. Verification
/// is deliberately read-after-write so a successful return means the complete
/// result is available from the canonical repository, not only in provider state.
class AnalysisResultSubmissionService {
  const AnalysisResultSubmissionService(this._repository);

  final QuestionRepository _repository;

  Future<QuestionRecord> submit(QuestionRecord record) async {
    if (record.analysisResult == null) {
      throw StateError('Cannot submit an analysis result without analysis data');
    }
    await _repository.saveDraft(record);
    final persisted = await _repository.getById(record.id);
    if (persisted == null || persisted.analysisResult == null) {
      throw StateError('Analysis result was not persisted for ${record.id}');
    }
    return persisted;
  }

  Future<List<QuestionRecord>> submitAll(List<QuestionRecord> records) async {
    if (records.any((record) => record.analysisResult == null)) {
      throw StateError('Cannot submit a batch containing an incomplete result');
    }
    await _repository.saveDrafts(records);
    final persisted = <QuestionRecord>[];
    for (final record in records) {
      final saved = await _repository.getById(record.id);
      if (saved == null || saved.analysisResult == null) {
        throw StateError('Analysis result was not persisted for ${record.id}');
      }
      persisted.add(saved);
    }
    return List<QuestionRecord>.unmodifiable(persisted);
  }
}

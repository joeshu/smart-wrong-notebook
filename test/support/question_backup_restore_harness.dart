import 'package:smart_wrong_notebook/src/data/repositories/pending_knowledge_point_mapping_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_knowledge_link_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/pending_knowledge_point_mapping.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_knowledge_link.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';

/// Test-only portable snapshot for the three persistence contracts used by a
/// question backup. The shape deliberately mirrors the model `toJson()` APIs;
/// no production backup implementation is assumed by this harness.
class QuestionBackupSnapshot {
  const QuestionBackupSnapshot({
    required this.questions,
    required this.links,
    required this.pendingMappings,
  });

  final List<Map<String, dynamic>> questions;
  final List<Map<String, dynamic>> links;
  final List<Map<String, dynamic>> pendingMappings;

  factory QuestionBackupSnapshot.fromRepositories({
    required List<QuestionRecord> questions,
    required List<QuestionKnowledgeLink> links,
    required List<PendingKnowledgePointMapping> pendingMappings,
  }) {
    return QuestionBackupSnapshot(
      questions: questions.map((item) => item.toJson()).toList(),
      links: links.map((item) => item.toJson()).toList(),
      pendingMappings: pendingMappings.map((item) => item.toJson()).toList(),
    );
  }
}

/// Reusable fake/harness around the actual repository interfaces used by the
/// save/restore boundary. It is intentionally dependency-injected so a later
/// end-to-end test can replace the in-memory question repository without
/// changing its assertions.
class QuestionBackupRestoreHarness {
  QuestionBackupRestoreHarness({
    required this.questions,
    required this.links,
    required this.pendingMappings,
  });

  final QuestionRepository questions;
  final QuestionKnowledgeLinkRepository links;
  final PendingKnowledgePointMappingRepository pendingMappings;

  Future<QuestionBackupSnapshot> exportSnapshot() async {
    return QuestionBackupSnapshot.fromRepositories(
      questions: await questions.listAll(),
      links: await links.allLinks(),
      pendingMappings: await pendingMappings.allMappings(),
    );
  }

  /// Restores using the real public repository entry points. Re-running this
  /// method is the idempotency operation under test.
  Future<void> restoreSnapshot(QuestionBackupSnapshot snapshot) async {
    await questions.saveDrafts(
      snapshot.questions.map(QuestionRecord.fromJson).toList(),
    );
    await links.addLinks(
      snapshot.links.map(QuestionKnowledgeLink.fromJson).toList(),
    );
    await pendingMappings.upsertAll(
      snapshot.pendingMappings
          .map(PendingKnowledgePointMapping.fromJson)
          .toList(),
    );
  }
}

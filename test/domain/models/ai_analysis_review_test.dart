import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_review.dart';
import 'package:smart_wrong_notebook/src/domain/services/ai_analysis_confirmation_service.dart';

void main() {
  test('confirmation decision keeps explicit audit fields through JSON', () {
    final decision = AiAnalysisReviewDecision(
      disposition: AiAnalysisReviewDisposition.autoApproved,
      fields: const <String>['standardAnswer'],
      reasons: const <String>['用户已核对'],
      evaluatedAt: DateTime.utc(2026, 7, 25),
      confirmedAt: DateTime.utc(2026, 7, 25),
      confirmedFields: const <String>['standardAnswer'],
      confirmationSource: AiConfirmationSource.editedByUser.name,
    );

    final restored = AiAnalysisReviewDecision.fromJson(decision.toJson());
    expect(restored.confirmedAt, DateTime.utc(2026, 7, 25));
    expect(restored.confirmedFields, ['standardAnswer']);
    expect(restored.confirmationSource, 'editedByUser');
  });
}

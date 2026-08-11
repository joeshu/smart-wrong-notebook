# Phase 1C-2 — Confirmation Workbench Slice

## Delivered

This slice adds the first explicit confirmation path for low-confidence AI results.

- `AiAnalysisConfirmationService` is the only domain service that promotes a gated result to `ContentStatus.ready`.
- Confirmation requires both:
  - `QuestionRecord.contentStatus == ContentStatus.needsConfirmation`
  - `AnalysisResult.reviewDecision.requiresConfirmation == true`
- The confirmation decision is persisted inside `AnalysisResult.reviewDecision` with:
  - `confirmedAt`
  - `confirmedFields`
  - `confirmationSource`
- Confirmed results receive a completed `AiAnalysisPipelineSnapshot`.
- The analysis result screen now includes a visible “我已核对，确认采用” action.
- Confirming from the result screen persists the record, refreshes list providers, and creates structured knowledge links only after confirmation.
- Practice remains disabled until confirmation completes.

## Guardrails

- A ready record cannot be silently reconfirmed.
- A record without an AI analysis result cannot be confirmed.
- Confirmation failures show a user-visible snackbar and do not mutate state.
- Knowledge-point mapping failure does not roll back confirmation.

## Deferred

- Full per-field editing workbench
- Per-field retry buttons wired to `retryAnalysisFields`
- Multi-candidate per-subquestion confirmation
- Dependency invalidation when the user edits upstream fields
- Detail-page inline confirmation controls
- Raw-response persistence and retention controls

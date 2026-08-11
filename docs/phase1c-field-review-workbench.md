# Phase 1C-3 — Field Review Workbench Slice

## Delivered

This slice turns `reviewDecision.fields` into visible, actionable review cards on the analysis result screen.

Each pending field now shows:

- localized field label
- field confidence when available
- gate reason or uncertainty
- supporting evidence quote when available
- current field value preview

For single-question gated results, users can now:

- edit text fields directly:
  - normalized question
  - student answer
  - standard answer
  - solution steps
  - knowledge points
  - mistake reason
  - study advice
- retry supported AI repair fields through the existing `retryAnalysisFields(...)` API
- keep the record in `needsConfirmation` after edit/retry until the user explicitly confirms

## Data behavior

- Manual edits are saved to the current `QuestionRecord` and persisted through `saveDraft`.
- Worksheet-import queue state is synchronized when the edited record belongs to an active worksheet session.
- Edits to upstream fields mark downstream fields as needing confirmation:
  - question/student answer edits invalidate answer, steps, mistake, knowledge, and review-plan fields
  - answer/step edits invalidate mistake, knowledge, and review-plan fields
- Retry results are re-evaluated by `AiAnalysisReviewPolicy`, but still require explicit user confirmation before becoming `ready`.

## Guardrails

- Multi-candidate results show field risks but do not expose direct edit/retry actions yet.
- Unsupported fields remain read-only.
- Local retry failures are shown in a snackbar and do not mutate existing analysis.
- Confirmation remains the only route from `needsConfirmation` to `ready`.

## Deferred

- Multi-candidate per-subquestion edit/retry
- Rich per-field side-by-side image evidence view
- Dedicated full-screen confirmation workbench
- Fine-grained dependency graph stored in the model
- Retry UI for generated exercises
- Raw AI response persistence

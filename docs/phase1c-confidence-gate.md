# Phase 1C + 1D Slice 1 — Confidence Gate

## Scope

This slice establishes durable pipeline/review state and prevents low-confidence AI analysis from becoming a final ready record. It does not implement the full field-editing confirmation workbench.

## Decision policy

A new Contract V2 analysis is automatically approved only when:

- overall confidence is at least 0.72;
- normalized question confidence is at least 0.80;
- standard answer confidence is at least 0.82;
- solution steps confidence is at least 0.78;
- knowledge points confidence is at least 0.68;
- generated exercise confidence is at least 0.62;
- student-answer confidence is at least 0.70 when a student answer exists;
- critical fields have no unresolved uncertainty;
- visual assumptions do not require review;
- answer consistency is neither `needsReview` nor `unverifiable`;
- any mistake diagnosis cites student-answer evidence.

Legacy V1 analysis has unknown confidence and therefore requires confirmation when evaluated. Existing stored V1 records are not migrated or silently rewritten; the gate applies when analysis is newly run.

## Durable state

- `ContentStatus.needsConfirmation` separates gated results from final `ready`.
- `AiAnalysisReviewDecision` stores disposition, affected fields, reasons, and evaluation time inside `aiAnalysisJson`.
- `AiAnalysisPipelineSnapshot` stores the eight-stage pipeline state inside `aiAnalysisJson`.
- Drift needs no new column for this slice: the existing status text column and versioned analysis JSON persist the new values.

## Behavior

- Low-confidence analysis navigates to the result page but is marked `needsConfirmation`.
- It cannot enter review scheduling.
- It cannot start generated practice from the result page.
- It is not automatically mapped into the controlled knowledge tree.
- Batch “save ready” continues to save only fully analyzed/approved records.
- The result page can save it explicitly as a pending-confirmation draft so evidence is not lost.
- Home/batch/detail status surfaces recognize pending confirmation as actionable work.

## Deferred

- Per-field edit and retry controls
- Explicit “confirm all trusted fields” transition to `ready`
- Raw response retention and diagnostics export
- Full stage-by-stage live progress callbacks
- Batch approve-high-confidence action and review workbench

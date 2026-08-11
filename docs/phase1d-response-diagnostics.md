# Phase 1D-1 — AI Response Diagnostics Retention

## Delivered

This slice adds safe persisted diagnostics for AI responses without storing raw student content by default.

Persisted on `AnalysisResult.responseDiagnostics`:

- response length
- short SHA-256 fingerprint
- Markdown-envelope flag
- JSON repair strategy
- capture timestamp
- optional raw response
- optional raw-response retention window

## Default behavior

Raw model output is **not** persisted by default. Newly parsed analysis results store only the safe summary fields above. This keeps the existing privacy posture while making bug reports traceable through a stable fingerprint.

## Controlled raw retention

`AiAnalysisService` recognizes these settings keys:

- `ai_diagnostics_raw_response_enabled`
- `ai_diagnostics_raw_retention_days`

When raw retention is enabled explicitly, the raw response can be attached to diagnostics with a bounded retention window. The current clamp is 1–30 days, defaulting to 7 days.

## Cleanup support

`AiResponseDiagnosticsRetentionService` can:

- strip all raw responses while preserving safe summaries
- expire raw responses based on `capturedAt + retentionDays`
- process main question analysis and candidate analysis snapshots

## Guardrails

- Diagnostics never store API keys, request headers, or provider credentials.
- Default persisted JSON contains no raw model output.
- Raw cleanup does not remove fingerprints, lengths, or repair metadata.
- Legacy records without diagnostics remain valid.

## 1D fast-close additions

To close Phase 1D quickly without growing a separate diagnostics product surface, the data-management flow adds the minimum operational controls:

- Data Management now exposes an **AI diagnostics data** section.
- A user-facing toggle controls whether raw AI responses are retained for debugging.
- Retention days can be set with bounded preset values.
- A manual cleanup action removes only raw response bodies while preserving safe fingerprints and summary metadata.
- Opening the Data Management screen silently expires overdue raw responses.

## Close-out boundary

Phase 1D intentionally stops here:

- keep the privacy-safe summary permanently available for debugging
- keep raw response retention opt-in and time-bounded
- support both automatic expiry and manual cleanup
- avoid building a full diagnostics viewer/exporter in this phase

## Deferred

- Dedicated diagnostics export screen
- Provider-specific request/response correlation IDs
- Raw extraction diagnostics for OCR responses

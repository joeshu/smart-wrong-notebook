# Phase 1B — Structured Output and Field Repair

## Delivered

- Contract V2 is now the production analysis prompt contract.
- OpenAI/OpenRouter-compatible providers use `response_format: json_object`.
- Native Gemini requests use `responseMimeType: application/json`.
- Providers that reject `response_format` with 400/404/422 are retried once in prompt-only mode.
- The JSON decoder is isolated from the AI service and records only length, a short SHA-256 fingerprint, repair strategy, Markdown-envelope state, and field names.
- Contract V2 rejects Markdown code fences and rejects flat-field recovery.
- Legacy extraction and stored V1 analysis fixtures retain compatible repair behavior.
- `studentAnswer` is now forwarded into the analysis prompt.
- `retryAnalysisFields` supports targeted repair of question, answer, solution, knowledge, mistake, advice, and review-plan fields.
- Field patches may only return requested fields and must provide confidence for each repaired field.
- Mistake diagnosis patches still require quoted student-answer evidence.
- Model name, prompt version, and schema version are stamped by the client rather than trusted from model text.

## Structured schema safety

A strict JSON Schema definition is available in `AiPromptBuilder`, but production provider routing currently chooses `json_object` instead of `json_schema`. The existing optional `visualAssumptions` and polymorphic geometry `diagramData` cannot yet be represented losslessly by a strict provider schema without a larger compatibility migration. Activating strict schema prematurely would remove existing geometry behavior.

## Logging policy

Raw model responses, student answers, correct answers, OCR text before/after correction, API response bodies, and API key length are no longer written by `AiAnalysisService` diagnostics. Raw response persistence with explicit local retention controls remains a later Phase 1 task.

## Deferred

- Low-confidence save gate and user confirmation state
- UI entry points for field-level retry
- Raw response persistence and retention controls
- Lossless strict JSON Schema for visual assumptions and diagram data
- Drift columns for pipeline/audit state beyond the serialized analysis JSON

# AI Analysis Contract V2 Compatibility Plan

## Scope

Phase 1A introduces a typed, versioned AI analysis contract without changing the current capture or analysis UI. The existing V1 prompt and payload remain readable while later Phase 1 slices migrate model requests to V2.

## Version rules

- Missing `schemaVersion` is treated as legacy V1 only when `allowLegacy` is enabled.
- Strict boundaries may set `allowLegacy: false` and reject unversioned output.
- `schemaVersion: 2` must pass the complete V2 contract; unsupported versions are rejected.
- Legacy payloads keep `schemaVersion: 1`, `promptVersion: legacy-v1`, `confidence: null`, and `isLegacyContract: true`. Confidence and evidence are never fabricated.

## V2 required fields

- Audit: `schemaVersion`, `promptVersion`, `modelName`
- Trust: `confidence`, `uncertainties`, `evidence`
- Question: `originalQuestion`, `normalizedQuestion`, `studentAnswer`
- Analysis: `standardAnswer`, `solutionSteps`, `mistakeCategory`, `mistakeReason`, `knowledgePoints`
- Learning: `generatedExercises`, `reviewPlan`
- Existing display fields: `subject`, `studyAdvice`, `aiTags`

`confidence` contains both `overall` and field-level scores. V2 requires scores for the normalized question, student answer, standard answer, solution steps, knowledge points, and generated exercises.

## Evidence policy

- If `studentAnswer` is empty, a deterministic `mistakeCategory` or `mistakeReason` is rejected.
- If a mistake diagnosis is present, at least one evidence item for `mistakeReason` must quote `studentAnswer`.
- This prevents unsupported labels such as “careless” from becoming trusted analysis.

## Compatibility aliases

Until presentation and persistence consumers are migrated, a valid V2 payload also exposes:

- `standardAnswer` as `finalAnswer`
- `solutionSteps` as `steps`
- `normalizedQuestion` as `reconstructedQuestionText`

This keeps current screens functional and allows the migration to proceed in small, reversible slices.

## Deferred to later Phase 1 slices

- V2 prompt activation and provider `json_schema` capability routing
- Partial-field repair and retry
- Low-confidence save gate
- Raw response persistence and redacted diagnostics
- Drift schema additions for analysis audit metadata
- Recognition confirmation UI

## Verification gate

Each implementation slice must pass:

```sh
flutter analyze
flutter test
```

The current iSH environment has no Flutter/Dart SDK, so GitHub Actions is the executable validation environment for this branch. Static checks such as `git diff --check` are not substitutes for CI.

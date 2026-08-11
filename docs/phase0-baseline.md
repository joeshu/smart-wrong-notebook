# Phase 0 Baseline

- Baseline commit: `752b60723add2617e8d11e3ae6c48479acb37483`
- Baseline branch: `main`
- Implementation branch: `feat/ai-contract-v2`
- Remote divergence at branch creation: `0 / 0`
- Working tree at branch creation: clean
- Production Dart files: 197
- Test Dart files: 76
- Baseline CI run `30089889268`: failed before Phase 1A with 5 existing
  `RenderFlex` overflows in review widget tests. Root cause: the full attachment
  failure card was rendered inside a 64×64 question thumbnail.
- Existing CI: `.github/workflows/ci.yml`
  - `flutter pub get`
  - `flutter analyze --no-fatal-warnings --no-fatal-infos`
  - `flutter test`

## Safety constraints

1. Keep V1 analysis JSON readable.
2. Do not activate Contract V2 in production prompts until parsing and compatibility tests pass.
3. Do not change capture, analysis, notebook, or review UX in Phase 1A.
4. Do not overwrite uncommitted user work.
5. Deliver Phase 1A as an isolated, revertible commit.

## Local environment limitation

The iSH environment is Alpine Linux on aarch64 and currently has neither Flutter nor Dart installed. `git diff --check` can run locally, but it is not an acceptable replacement for Flutter validation. GitHub Actions is the executable analyze/test gate for this phase.

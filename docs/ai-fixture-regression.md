# AI Fixture Regression

This document describes the local image regression tool for AI analysis quality.
Do not write API keys into this file, command history, or handoff notes.

## Purpose

Use `test/tool/analyze_image_fixture_test.dart` to send local fixture images through `AiAnalysisService` and print a JSON report. The tool checks that analysis output is internally consistent and that generated practice exercises are usable.

The quality gate separates hard failures from expected image-reading uncertainty:

- `issues`: fail the test. Examples: empty final answer, answer/steps conflict, generated exercise self-invalidates, or generated exercise option conflicts with its explanation.
- `warnings`: print for manual review but do not fail. Example: geometry reading is internally consistent but marked `needsReview`, so the app should show `可能解法/需核对` instead of a confirmed answer.

## Single Fixture

Run one image fixture by providing environment variables:

```bash
AI_BASE_URL="https://www.vbcode.io/v1" \
AI_API_KEY="<secret>" \
AI_MODEL="gpt-5.5" \
AI_FIXTURE_IMAGE="test/fixtures/semicircle.png" \
AI_FIXTURE_SUBJECT="math" \
AI_FIXTURE_TEXT="图中标注上边为3、底边为7、右边高为10，图内为半圆，求图中括号所示区域面积。" \
flutter test test/tool/analyze_image_fixture_test.dart
```

## Local Batch

Run the built-in fixture set with `AI_FIXTURE_SET=local`:

```bash
AI_BASE_URL="https://www.vbcode.io/v1" \
AI_API_KEY="<secret>" \
AI_MODEL="gpt-5.5" \
AI_FIXTURE_SET="local" \
flutter test test/tool/analyze_image_fixture_test.dart
```

The built-in set covers:

- `semicircle.png`: composite semicircle area
- `shuxue-jihe.png`: math geometry
- `duoti.png`: multi-question math image
- `wuli-dianzu.png`: physics circuit
- `yuwen.png`: Chinese question
- `yingyu.png`: English question

## Explicit Batch

For ad hoc regression, pass a JSON array in `AI_FIXTURE_CASES`:

```bash
AI_FIXTURE_CASES='[
  {"id":"custom-math","image":"/abs/path/a.png","subject":"math","text":"请识别并分析这道题。"},
  {"image":"/abs/path/b.png","subject":"english","text":"请识别图片中的英语题。"}
]'
```

Each item supports:

- `id`: optional; defaults to the image filename without extension
- `image` or `imagePath`: required
- `subject`: optional; defaults to `math`
- `text` or `prompt`: optional; defaults to `请根据图片识别题目并解答。`

## Interpreting Results

Each fixture prints:

- final answer, derivation, steps
- visual assumptions and consistency state
- whether verifier was used
- extracted/generated exercises
- quality gate `issues` and `warnings`

A passing test with warnings is acceptable for uncertain image-based geometry. It means the app should avoid presenting the answer as definitely correct and should route the user through manual review language.

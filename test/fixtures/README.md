# 识别准确性 fixture 验证基线

本目录只存脱敏样例的 manifest 与验证约定。真实图片不随代码提交；`imagePath` 是约定路径，缺失时 manifest 校验仍可运行。`expected` 必须由人工标注填写，不能从模型输出反推，也不能把模型 confidence 当作准确率。

manifest v2 的每个样例必须声明 `pageType`、`schoolStage`、`contentTags` 和
`authorRoles`。块级真值在人工标注后写入 `expected.blocks`，包含类型、角色、
归一化多边形和内容格式；待标注样例不得用模型预测值回填。

## 执行入口

```bash
flutter test test/tool/accuracy_fixture_manifest_test.dart
flutter test test/domain/services/analysis_result_submission_service_test.dart
```

生成本地 Markdown 验收报告（未标注项目会明确显示 `pending`）：

```bash
dart run tool/generate_recognition_report.dart
dart run tool/generate_recognition_report.dart \
  test/fixtures/accuracy_manifest.json build/recognition-report.md
```

需要真实图片和远程模型回归时，使用既有入口，并通过环境变量提供凭据：

```bash
AI_BASE_URL=... AI_API_KEY=... AI_MODEL=... \
AI_FIXTURE_CASES='[...]' \
flutter test test/tool/analyze_image_fixture_test.dart
```

本机未安装 Flutter/Dart 时，只能运行仓库外的 JSON/source-level 校验；不能把静态检查报告为 Flutter 测试通过。

## 标注与指标

- 题框 IoU：预测框与人工框的交集面积 / 并集面积；逐题记录，目标 `>= 0.85`，低于阈值必须人工确认。
- OCR 字符准确率：脱敏人工文本与识别文本的字符级准确率；印刷体目标 `>= 98%`，手写单独统计。
- 公式完整率：公式边界、成对标记、关键符号均保留；任一缺失即需确认。
- 表格结构准确率：行列结构及单元格文本/Markdown 均可复核；结构异常不得静默转普通文本。
- 用户修改率：确认前文本发生修改的题目数 / 有文本的题目数；它是质量趋势，不是真实准确率。
- 重复 AI 调用率：同 stable ID + 同文本版本的远程调用次数大于 1 的调用数 / 总调用数；重复点击和重进页面目标不超过 1 次有效调用。
- 保存完整率：分析成功后按 stable ID 重读，`analysis/status/exercises` 一致的记录数 / 成功分析数；目标 100%。
- 恢复率：模拟中断后能读回并转为可重试状态的记录数 / 中断记录数；`processing/analyzing` 均需覆盖。

## 人工流程

1. 复制脱敏图片到 `test/fixtures/accuracy/`，只使用 manifest 中已有类别；补录 `expected.text`、`regions`、公式数量和表格行列。
2. 两名标注者独立复核题框与文本；分歧保留人工裁决，不改成模型“多数意见”。
3. 运行 manifest 契约测试，确认每个类别、图片路径和 expected 字段完整；再运行实际识别入口。
4. 将每次结果另存为本地报告，不提交 API key、原图、识别结果中的个人信息或凭据。
5. 报告分组展示印刷体/手写、快速/详细模式、PaddleOCR/MinerU/普通 AI；缺少人工标注的项显示 `pending`，不计算百分比。

`ai_failure_recovery` 与 `duplicate_save` 是无图行为 fixture，由现有 domain/service 测试验证，不应通过伪造图片衡量识别准确率。

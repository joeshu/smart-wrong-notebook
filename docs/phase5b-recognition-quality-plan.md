# Phase 5B：识别质量信号与确认体验实施方案

日期：2026-08-11
范围：只处理 B 方向——拍摄质量、版面/文字/公式/表格识别信号，以及识别确认门禁。本文是基于当前 HEAD 的源码审计和可执行验收契约，不代表模型准确率已经测得。

## 1. 审计边界与结论

本轮核对了以下真实代码路径：

- 图片质量：`lib/src/shared/utils/image_quality_detector.dart`，由 `lib/src/features/capture/presentation/question_correction_screen.dart` 调用。
- 确认策略：`lib/src/domain/services/recognition_confirmation_policy.dart`，单题确认页 `lib/src/features/ocr/presentation/recognition_confirmation_screen.dart` 目前仍有一套页面内的简化判断。
- 整页候选：`lib/src/domain/models/question_region.dart`、`lib/src/data/services/auto_document_layout_service.dart`、`lib/src/data/repositories/worksheet_review_draft_repository.dart`。
- 单题记录：`lib/src/domain/models/question_record.dart`；持久化接口为 `lib/src/data/repositories/question_repository.dart`，Drift 实现为 `lib/src/data/repositories/drift_question_repository.dart`。
- 入口与路由：`/capture/correction`、`/capture/recognition-confirmation`、`/analysis/loading`，以及 `lib/src/app/router.dart`。
- 现有测试与样例契约：`test/domain/services/recognition_confirmation_policy_test.dart`、`test/domain/models/question_region_structured_test.dart`、`test/features/ocr/recognition_confirmation_screen_test.dart`、`test/fixtures/accuracy_manifest.json`。

结论：当前已有可用的质量提示、字段确认、公式/表格结构字段、印刷/手写/混合模式和恢复入口，但“信号定义—确认决策—人工标注—统计验收”尚未形成一条统一且可复核的链路。下一步应先统一 domain/application 契约和测试，再做小范围 UI 接线；不应继续泛化 UI。

## 2. 当前真实流程

### 2.1 单题

1. 拍照/相册进入 `/capture/correction`。
2. `detectImageQuality(imagePath)` 在 isolate 中解码图片，计算拉普拉斯方差、平均亮度、原图最短边，并只返回一个 `primaryIssue`。
3. 用户继续后进入 `/analysis/loading`；当识别需要确认时进入 `/capture/recognition-confirmation`。
4. 确认页编辑题干、选项、学生答案；可整题或题干重识别，确认后保存 `QuestionRecord`，移除系统确认标签并进入 `ContentStatus.analyzing`。
5. 确认页当前使用页面内的 `.85`、非空题干、公式字符串启发式和原图文件存在性判断；这些判断没有完全复用 `RecognitionConfirmationPolicy`。

### 2.2 整页

1. `/worksheet/import` 进行版面识别，生成 `QuestionRegion` 候选。
2. `QuestionRegion` 已保存 normalized rect、识别文字/原文、题干、公式、表格、选项、文档块、置信度、来源、review status 和 confirmed fields。
3. `RecognitionConfirmationPolicy` 定义字段集合：stem、options、studentAnswer、formulas、tables、diagram；高置信阈值默认 `.85`。
4. 低置信、空题干、结构风险进入字段确认；贴边、重叠、面积、宽高比等空间风险不可被字段确认绕过。
5. 确认后的区域裁切并进入 worksheet 队列，再由分析/保存流程处理。

### 2.3 模式

`CaptureMode` 只有 `printed`、`handwritten`、`mixed`：

- `printed`：忽略手写批改痕迹、圈画、红叉。
- `handwritten`：保留手写解答过程。
- `mixed`：同时识别印刷内容和手写批注。

该模式已经传入结构提取服务，且 AI prompt 有对应分支；本计划不改变其枚举或既有默认值。

## 3. 已具备能力与边界

| 能力 | 当前证据 | 当前可保证的事实 | 尚不能宣称 |
|---|---|---|---|
| 拍摄质量提示 | `image_quality_detector.dart` | 可检测模糊、过暗、过亮、低分辨率；给出 sharpness/brightness/min dimension | 不能由阈值推出 OCR 准确率；没有曝光、倾斜、反光、遮挡和多问题完整结果契约 |
| 统一确认策略 | `RecognitionConfirmationPolicy` | 高置信且无风险可自动确认；空间风险硬拦截；字段可分别确认 | 单题确认页未完全使用该策略；风险字符串不是稳定类型 |
| 题框/多题 | `QuestionRegion` 与 layout service | 可保存多个候选、normalized rect、来源和忽略状态 | 当前 manifest 尚无真实标注框，不能计算 IoU |
| 公式/表格 | `QuestionRegion.formulas/tables/documentBlocks` | 能保留字段并进入确认 | 没有真实标注集，不能报告公式完整率或表格结构准确率 |
| 记录置信度 | `QuestionRecord.ocrConfidence` | 可在记录上保存 OCR confidence | model confidence 不是 ground truth accuracy；没有按模式/引擎统计 |
| 草稿与恢复 | QuestionRepository、worksheet draft repository、已有 recovery 路径 | 可保存草稿，若干失败路径可重试/保留 | 本轮不把恢复可靠性冒充识别质量指标 |
| 样例清单 | `test/fixtures/accuracy_manifest.json` | 已列出模糊、倾斜、手写、公式、表格、多题、空白、不完整 OCR、AI 失败、重复保存 | `annotationStatus=pending_human_annotation`；图片和 expected 标注尚未完成 |

## 4. 缺口分级

### P0：确认决策存在两套实现

`RecognitionConfirmationPolicy` 已是纯策略，但单题确认页自行计算 required fields 和 `_highConfidenceSafe`。两套实现对选项、学生答案、公式、原图缺失和结构风险的覆盖不完全一致，容易出现单题能继续、整页不能继续，或反向阻断。

验收：单题和整页对同一组输入产生相同的 required fields、spatial hard block 和 canProceed 结果；UI 只展示策略结果，不复制阈值。

### P0：质量结果只保留 primary issue

检测器虽计算多个严重度，但返回单个主要问题，无法在确认页明确告诉用户“模糊且过暗”，也无法按问题类型统计重拍收益。

验收：在不改变现有调用兼容性的前提下，新增可选/向后兼容的 issue 集合或等价 domain 结果；旧调用仍能读取 `primaryIssue`。

### P1：风险是自由文本，指标不可稳定聚合

`RecognitionConfirmationPolicy` 通过中文字符串 `contains` 识别题干、公式、表格、图形和空间风险。服务文案变更即可改变门禁，且无法可靠统计风险类型。

验收：新增内部稳定 risk code 与展示文案映射；旧风险文本在过渡期仍可映射；空间风险始终是硬门禁。

### P1：formula/table/multi-question 只有字段，没有标注执行器

`QuestionRegion` 已有结构字段，但 manifest 的 `regions`、`text`、`formulaCount`、表格行列仍为 null/空数组，状态明确为 `pending_human_annotation`。

验收：先完成脱敏图人工标注和 manifest schema 校验；在此之前所有准确率输出必须是 `pending annotation`，不得填估算值。

### P1：质量阈值未与输入模式分层验证

印刷、手写、混合模式已经存在，但当前质量检测阈值和验收指标没有按模式拆分。手写不得混入印刷 OCR 字符准确率。

验收：manifest 每个 case 记录 capture mode、识别引擎、版本和人工标注状态；报告按 printed/handwritten/mixed 分组。

### P2：确认体验缺少可解释的“为什么不能自动通过”摘要

当前页面能高亮字段，但“低置信、空题、公式损坏、原图缺失、空间风险”没有统一的原因对象和验收文案。

验收：每个阻断结果至少有稳定 code、字段、证据值和用户动作；不增加无证据的模型解释。

## 5. 实施拆分

### B2：统一质量/识别信号契约（先做纯 domain）

精确范围：

- `lib/src/shared/utils/image_quality_detector.dart`
- `lib/src/domain/services/recognition_confirmation_policy.dart`
- 必要时新增 `lib/src/domain/models/recognition_quality_signal.dart` 或同层纯模型
- 对应 domain/service tests

内容：

1. 保留现有 `ImageQualityResult` 字段和 `primaryIssue` 兼容边界，补充多问题、阈值版本和不可识别错误的明确结果。
2. 将确认风险从自由文本逐步归一为稳定 code；保留旧文本适配器。
3. 将 required fields、spatial hard block、empty stem、formula/table/diagram 风险统一由纯策略计算。
4. 不调整数据库 schema、不改变 `/capture/*` 路由、不改变 CaptureMode 枚举。

依赖：无；B3、B4 必须等待 B2 的契约测试稳定。

### B3：接线确认页与批量页，保持兼容

精确范围：

- `lib/src/features/ocr/presentation/recognition_confirmation_screen.dart`
- worksheet regions/review 相关 presentation 文件
- 必要的 widget tests

内容：

1. 删除单题页重复的阈值/风险判断，调用 B2 策略。
2. 统一展示阻断原因、待确认字段和空间风险硬拦截。
3. 保持旧路由、现有保存草稿、重识别、放弃和 `ContentStatus` 行为。
4. 只做确认体验接线，不在本批改变分析结果提交或恢复逻辑。

依赖：B2；不得在 B3 重新定义指标。

### B4：脱敏 fixture 标注、统计脚本与验收报告

精确范围：

- `test/fixtures/accuracy_manifest.json`
- `test/fixtures/accuracy/`（仅在取得真实脱敏图片和人工标注后）
- 新增纯文本/脚本契约测试；具体路径由实现时按现有测试布局确定
- 文档中的报告输出

内容：

1. 完成真实脱敏图片的人工标注：题框、题干、公式、表格行列/单元格、多题数量，并记录模式和引擎。
2. 增加 manifest 校验：图片存在性、case id 唯一、annotation status、expected 字段与 validation 类型一致。
3. 统计题框 IoU、OCR 字符准确率、公式完整率、表格结构准确率、用户修改率、重复 AI 调用率、保存完整率；没有图片时输出 `pending annotation`。
4. 报告必须区分人工标注指标和模型 confidence，不用 confidence 代替准确率。

依赖：B2 的稳定 signal code；B3 的确认事件/字段行为；不得阻塞前两批的纯逻辑验证。

## 6. 明确暂不做

- 不在本任务或 B2/B3 中迁移 Drift schema、增加质量表或改 `QuestionRecords`。
- 不重写拍照、裁剪、分析 loading、AI provider 或路由。
- 不把阈值调优写成准确率提升；阈值变更必须有真实标注样本支撑。
- 不构造、下载或提交未经脱敏授权的用户图片。
- 不在没有人工标注时填写 OCR、公式、表格或题框准确率。
- 不把“用户修改率低”解释为识别准确率高，也不把一次成功请求解释为模型质量达标。
- 不在本轮处理 P0/P1 的分析成功持久化、单题 durable recovery 和异常编排；那些属于 A 方向/后续批次。

## 7. 可执行验收契约

### 7.1 纯策略契约（B2）

- 置信度 `< 0.85` 或题干为空：题干必须待确认。
- 公式、表格、选项、学生答案、图形出现对应风险：对应字段必须待确认。
- 贴边、重叠、面积、宽高比等空间风险：无论字段是否确认，都不得继续。
- ignored region：不得自动确认、不得进入裁切题库队列。
- 高置信、非空、无任何风险且原图可用：只有在用户启用自动确认时才可自动确认；默认仍由用户显式授权。
- printed/handwritten/mixed 只改变识别输入语义，不改变“空间风险硬拦截”规则。

### 7.2 质量信号契约（B2）

- 不存在/无法解码图片：返回可解释的不可识别状态；不得伪造质量分数。
- 同时存在多种质量问题：不得丢失问题集合；`primaryIssue` 仅作为兼容的主问题。
- 质量分数范围保持 `0..1`，原图最短边保持原始像素值。
- 阈值和算法版本可记录，避免不同版本结果不可比较。

### 7.3 人工标注和指标契约（B4）

- `accuracy_manifest.json.annotationStatus` 在图片未完成脱敏与人工标注前保持 `pending_human_annotation`。
- `pending annotation` 不输出数字准确率；自动契约只能验证状态机、持久化和重复调用次数。
- 印刷体、手写体、混合体分组统计；手写不并入印刷 OCR 字符准确率。
- 题框 IoU：预测框与人工框逐题记录，目标阈值暂定 `>= 0.85`；低于阈值必须人工确认。该阈值是验收门槛，不是当前结果。
- OCR 字符准确率：只对有人工文本标注的 case 统计；当前无真实结果。
- 公式完整率：边界、成对标记、关键符号均保留才算通过，任一缺失进入确认。
- 表格结构：行列和单元格文本可复核；结构异常不得静默降级为普通文本。
- 用户修改率、重复 AI 调用率、保存完整率作为可靠性/体验指标单独统计，不替代识别准确率。

## 8. 兼容边界与回滚

兼容要求：

- 保留现有 `ImageQualityResult.primaryIssue`、阈值常量的调用方式，新增字段使用可选/默认值。
- 保留 `RecognitionConfirmationPolicy` 公共方法和 `.85` 默认值；新 code 通过适配层接入。
- 保留 `QuestionRegion`、`QuestionRecord` JSON 字段和旧草稿读取；不要求旧数据回填质量指标。
- 保留 `/capture/correction`、`/capture/recognition-confirmation` 路由、CaptureMode 默认 `printed`、现有保存草稿和重试行为。

回滚方式：

1. B2 仅涉及纯模型/策略时，按单次 commit 回退即可，不触碰数据库数据。
2. B3 若 UI 接线出现行为回归，回退 B3 commit，保留 B2 契约测试和适配层，恢复原确认页实现。
3. B4 的 fixture/报告为测试与文档资产，可单独回退；不得删除已经授权的标注原始记录，先保留审计副本。
4. 每批只允许一个可回滚切片；CI 未通过不得进入下一批。

## 9. 依赖关系与门禁

```text
B1（本审计与契约）
  -> B2（统一质量/确认 domain 契约）
       -> B3（单题/整页确认 UI 接线）
            -> B4（真实脱敏标注、指标脚本与报告）
```

- B2 不依赖真实图片，可先完成纯逻辑测试。
- B3 依赖 B2 的稳定风险 code 和策略测试。
- B4 依赖真实脱敏图片与人工标注；在此之前必须标记 `pending annotation`，不得因为缺图而编造结果。
- 每批修改后执行 `git diff --check` 和仓库约定的源码/文档一致性检查；不在本机安装或运行 Flutter/Dart。
- 提交并推送后，以 exact SHA 检查 GitHub Actions CI。若仅 docs/test 路径未触发 iOS unsigned workflow，记录 `not_applicable`，不等待不存在的 run。

## 10. 本轮验证记录

已完成当前 HEAD、Phase 5 审计文档、质量检测器、确认策略、QuestionRegion/QuestionRecord、CaptureMode、相关路由/页面和 `accuracy_manifest.json` 的静态核对。manifest 当前明确为 `pending_human_annotation`，因此本文没有填入任何模型准确率或真实图片结果。未在本机运行 Flutter/Dart；本文件只改进实施契约，不改变 schema、路由和生产逻辑。

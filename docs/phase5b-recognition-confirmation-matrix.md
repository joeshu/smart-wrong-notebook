# Phase 5B：识别确认决策矩阵

日期：2026-08-11
范围：B1/B2 审计证据的 domain 决策矩阵。本文只定义识别质量信号如何影响确认门禁，不新增数据库、网络或页面层规则，也不把模型 confidence 当作真实准确率。

## 1. 证据边界

本矩阵基于当前仓库可核对的源码和测试：

- `lib/src/domain/services/recognition_confirmation_policy.dart`：已有 `.85` 默认阈值、字段级确认、空间风险硬阻断、ignored region 阻断，以及单题/整页两组策略入口。
- `lib/src/domain/models/question_region.dart`：候选区域保存 normalized rect、识别文本、题干、公式、表格、选项、图形提示、学生答案、confidence、review status 和 confirmed fields。
- `lib/src/features/ocr/presentation/recognition_confirmation_screen.dart`：单题确认页保留题干/选项/作答编辑、草稿保存、返回旧的 `/capture/correction` 路由；当前已调用 domain policy，但公式损坏检测仍在页面内产生风险输入。
- `lib/src/shared/utils/image_quality_detector.dart`：当前可计算 sharpness、brightness、原图最短边，并只向外暴露一个兼容的 `primaryIssue`；文件不存在或无法解码时抛出错误。
- `lib/src/domain/models/content_status.dart`：保留 `processing`、`analyzing`、`needsConfirmation`、`ready`、`failed`、`analysisFailed`。
- `test/domain/services/recognition_confirmation_policy_test.dart`：已覆盖低置信、公式风险、候选/作答不完整、缺图、空间贴边/倾斜阻断和缺失 confidence。
- `test/fixtures/accuracy_manifest.json` 与 `recognition_accuracy_metrics_test.dart`：当前样例仍是 `pending_human_annotation`；未提供真实图片和人工标注，因此不产生准确率结论。

证据缺失项：当前未发现可用于计算模糊/倾斜、公式完整率、表格结构准确率、多题框 IoU 或按手写模式分层准确率的人工标注结果。下表中的“通过”是决策条件，不是已测得的模型准确率。

## 2. 决策结果类型

| 结果 | domain 含义 | 允许动作 | 不允许动作 |
|---|---|---|---|
| `autoPass`（可自动通过） | 当前候选没有已知必须确认或空间硬风险，且满足自动确认条件 | 仅在用户显式启用自动确认时确认并继续；默认仍可展示确认页 | 不因 confidence 单项就宣称识别准确；不绕过空间风险 |
| `mustConfirm`（必须用户确认） | 识别结果存在字段级不确定性或无法证明完整性 | 进入现有确认页，逐字段编辑/确认；确认后继续 | 不用“用户没修改”替代确认；不静默降级结构字段 |
| `ignorePrompt`（可忽略提示） | 仅提示性质、不会使候选安全或字段完整性成立的非门禁信息 | 展示提示，用户可继续处理或忽略提示 | 不把提示当作自动通过依据；不得覆盖 `mustConfirm` 或空间硬阻断 |
| `hardBlock`（不可继续） | 区域空间结构无效，或候选被明确忽略 | 保留草稿、返回/取消、重新裁切或手动录入 | 不可由字段确认绕过；ignored region 不进入裁切题库队列 |

优先级：`hardBlock` > `mustConfirm` > `autoPass`；`ignorePrompt` 仅在没有更高优先级结果时作为展示信息。自动确认开关不是证据，它只是允许 `autoPass` 执行自动动作的用户授权。

## 3. 核心确认矩阵

| 输入信号 | 证据/判定 | 结果 | 必须确认字段或动作 | 说明 |
|---|---|---|---|---|
| confidence 缺失或 `< 0.85` | `null` 按低置信处理；不得当作准确 | `mustConfirm` | `stem`；若选项/作答存在，同时确认对应字段 | confidence 是模型信号，不是真实准确率 |
| confidence `>= 0.85` 且题干为空/仅空白 | 题干不可用 | `mustConfirm` | `stem`；优先人工编辑或手动录入 | 不能为空题干自动通过 |
| 公式边界不成对、公式可能损坏或关键符号缺失 | 当前页面已有公式定界符启发式；B1 契约要求缺失即确认 | `mustConfirm` | `formulas`，必要时 `stem` | 不把公式当普通文本静默处理 |
| 表格行列/单元格结构异常 | 结构风险 | `mustConfirm` | `tables` | 没有人工标注时不输出表格准确率 |
| 选择题候选不完整/选项风险 | 选项缺失或候选不完整 | `mustConfirm` | `options` | 选项为空本身不代表题目一定是非选择题；由风险输入决定 |
| 作答区域/学生答案可能缺失 | 学生答案风险 | `mustConfirm` | `studentAnswer` | 不因没有学生答案而强制伪造内容；可确认“无作答” |
| 图形/示意图内容风险 | 图形字段可能缺失 | `mustConfirm` | `diagram` | `diagramNote` 可作为现有兼容字段，不改变 schema |
| 模糊或明显倾斜的质量提示 | 当前检测器能报告模糊相关质量问题；倾斜需由结构/图像信号证明 | `mustConfirm`（影响文字/结构时）或 `ignorePrompt`（仅提示） | 受影响字段；建议重拍/重识别 | 不能从阈值直接推出 OCR 准确率；多问题集合不能丢失 |
| 过暗、过亮、低分辨率 | `ImageQualityIssue` 信号 | `mustConfirm`（若影响可读性）或 `ignorePrompt`（不影响当前字段的提示） | 受影响字段或重拍 | 质量分数范围为 `0..1`；原图最短边保留原始像素值 |
| 原图不存在或不可解码 | 无法提供可复核证据 | `mustConfirm`；无法安全确认时 `hardBlock` | 重选图片、重拍或手动录入 | 不伪造质量分数；现有检测器的底层错误需由调用方转为可解释恢复路径 |
| 题框贴边、重叠、面积异常、宽高比异常 | 空间结构风险 | `hardBlock` | 重新裁切/忽略候选/手动录入 | 即使所有字段都已确认，也不得继续 |
| `QuestionRegion.reviewStatus == ignored` | 用户或版面流程明确忽略 | `hardBlock` | 保留忽略状态；必要时恢复候选再审 | 不自动确认，不进入裁切题库队列 |
| 高置信、非空题干、原图可用、无任何风险 | 所有自动条件满足 | `autoPass` | 无字段必须确认 | 只有用户启用自动确认时才执行自动动作；默认保留显式确认 |
| 仅有非门禁提示，字段与空间均安全 | 提示不改变安全性 | `ignorePrompt` | 无 | 可忽略提示不能升级为通过证据 |

### 3.1 多信号合并

- 同一候选同时有多个字段风险时，结果仍是一个 `mustConfirm`，但 required fields 必须是并集；不得只保留一个 primary risk。
- 同时存在字段风险和空间风险时，结果为 `hardBlock`，字段列表可保留供用户修复后继续，但字段确认不能解除空间阻断。
- 同时存在质量提示和低置信时，至少为 `mustConfirm`；质量提示应作为证据和动作建议展示，不改变 confidence 的含义。
- `primaryIssue` 只保留为旧调用的主问题兼容字段；后续多问题集合若加入 domain，应以集合为准做决策。

## 4. 模式矩阵

`CaptureMode` 仅改变识别输入语义，不改变空间硬阻断和确认优先级：

| 模式 | 应保留的内容 | 模式特有确认关注点 | 不变规则 |
|---|---|---|---|
| `printed` | 印刷题干、印刷选项；忽略手写批改痕迹、圈画、红叉 | 手写痕迹不应被误当作选项/作答；若混入导致字段不确定，确认对应字段 | 低置信、空题干、结构风险和空间风险规则不变 |
| `handwritten` | 手写题干、解答过程 | 笔迹不可读、步骤/作答缺失时确认 `stem` 或 `studentAnswer` | 不把手写样本并入印刷 OCR 准确率 |
| `mixed` | 印刷内容与手写批注 | 需区分题干、选项、作答和批注归属；混淆时分别确认字段 | 空间风险仍是 `hardBlock`；不因模式自动放宽门禁 |

当前没有按模式人工标注准确率，不能据此声称某模式优于另一模式。

## 5. `ContentStatus` 与旧路由行为

| 决策/动作 | 状态边界 | 现有路由与行为 |
|---|---|---|
| 识别尚未完成 | `processing` | 保留原识别中流程；不进入最终 ready |
| 低置信或结构风险待确认 | `needsConfirmation` | 进入 `/capture/recognition-confirmation`；保留字段编辑、确认和草稿行为 |
| 用户确认后开始 AI 分析 | `analyzing` | 保留现有分析入口和旧路由；确认不是 AI 准确率证明 |
| 识别成功且可继续 | `ready` | 保留既有结果/分析流程；是否已分析仍由 `analysisResult` 等现有记录判断 |
| OCR 失败 | `failed` | 保留原错误展示、返回、重试和手动录入边界；不可用原图时不伪造识别结果 |
| AI 分析失败但 OCR 保留 | `analysisFailed` | 保留 OCR/用户修改快照和可重试入口；不得因失败清空可恢复文本 |
| 用户保留草稿 | 不把草稿误标为最终 `ready` | 确认页现有“保留草稿”行为不变；后续恢复从持久化草稿继续 |

边界约束：

1. “取消/返回”只退出当前确认动作或回到 `/capture/correction`，不得隐式确认、删除未保存草稿或改变 `ContentStatus` 为 `ready`。
2. “恢复/重试”可以重新识别或继续手动编辑，但必须重新经过同一矩阵；不得用上一次的低置信结果直接自动通过。
3. “手动录入”是识别失败、原图不可用或用户无法修复时的可恢复路径；它不等于模型识别成功，也不应被确认门禁阻断。
4. 用户确认字段只解除对应字段的 `mustConfirm`；不能解除 `hardBlock`，也不能把 ignored candidate 放回队列。
5. 旧路由、旧草稿读取、`ContentStatus` 枚举和 `CaptureMode` 默认值保持兼容；本矩阵不要求数据库迁移。

## 6. 可追溯验收清单

后续实现或测试应逐项引用以下契约：

- 正常高置信输入：无风险时策略给出 `autoPass` 条件；自动动作必须受用户开关控制。
- 低置信、缺 confidence、空题干：`stem` 必须待确认。
- 公式、表格、选项、作答、图形风险：对应字段分别进入 required fields，合并风险不得丢失。
- 模糊/过暗/过亮/低分辨率：质量提示可解释；不存在/解码失败不得伪造 score。
- 贴边、重叠、面积、宽高比：统一 `hardBlock`，确认全部字段也不能继续。
- ignored region：不自动确认、不进入裁切队列。
- printed/handwritten/mixed：只改变输入语义和检查重点，不改变空间硬门禁。
- 取消、恢复、重试、手动录入：保留旧路由与可恢复边界，不将草稿或失败伪装为 ready。
- manifest 未完成脱敏和人工标注前：所有准确率字段保持 `pending_human_annotation`/`pending`，不填数字。

## 7. 未决项（不能用猜测补齐）

- 当前未取得真实脱敏图片和人工标注，无法给出 OCR、题框、公式或表格的真实准确率。
- 当前质量检测器对外只暴露 `primaryIssue`；多问题集合和倾斜信号的最终兼容 API 仍应由 B2 实现并补测试。
- 当前单题公式风险由页面内启发式生成；B2/B3 应将其适配为稳定 domain signal，但不能在本文中虚构尚不存在的 risk code。

因此，本文件定义的是可实现、可测试的决策边界，不是质量结果报告。

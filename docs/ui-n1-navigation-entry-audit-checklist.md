# UI-N1 导航与录题入口事实清单

日期：2026-08-11
范围：`router.dart`、`HomeScreen`、`AddScreen`、`CaptureEntrySheet`、录题 session 以及现有入口测试。

本文件是只读源码审计结果，记录当前实现事实、必须保持的兼容性和后续可验证条件。不代表 4-tab + 中央入口目标已经实现。

## 1. 当前导航基线

| 项目 | 证据 | 当前行为 | 必须保持/验证 |
|---|---|---|---|
| 路由构造 | `lib/src/app/router.dart:46-64` | `buildRouter(SettingsRepository, {required OnboardingNotifier})`，初始路径 `/`，onboarding redirect 仍生效。 | 保留函数签名、初始路径和 onboarding redirect；验证未完成 onboarding 时不会绕过 `/onboarding`。 |
| Stateful shell | `lib/src/app/router.dart:68-181` | `StatefulShellRoute.indexedStack` 当前有 6 个 branch，不是 4 个。 | 后续导航改造不得把当前 6 分支误记为已完成目标；改造时验证 shell 状态保留。 |
| 分支 0 | `lib/src/app/router.dart:74-78` | `/` -> `HomeScreen`。 | `/` 继续匹配并打开首页。 |
| 分支 1 | `lib/src/app/router.dart:79-83` | `/add` -> `AddScreen`，当前是普通导航 branch。 | `/add` 作为旧兼容入口必须继续可直接访问；若移出普通 Tab，不得删除路由。 |
| 分支 2 | `lib/src/app/router.dart:84-90` | `/notebook` -> `NotebookScreen`。 | 保留路径、页面和 shell 分支状态。 |
| 分支 3 | `lib/src/app/router.dart:91-96` | `/review` -> `ReviewScreen`。 | 保留路径、页面和 shell 分支状态。 |
| 分支 4 | `lib/src/app/router.dart:97-106` | `/export` -> `ExportWorkbenchScreen`，当前是普通导航 branch。 | 导出页不能因移除导出 Tab 而成为不可达页面；至少保留 `/export` 深链和现有入口。 |
| 分支 5 | `lib/src/app/router.dart:107-180` | `/settings` -> `SettingsScreen`，含多个设置子路由。 | 保留 `/settings/*` 子路由，包括 provider、data、knowledge-tree、export-workbench 等。 |
| 底部目的地 | `lib/src/app/router.dart:303-342` | `NavigationBar` 读取 `navigationShell.currentIndex`，当前有 6 个 destination：首页、添加、错题本、复习、导出、设置。 | 4 个常驻 Tab 目标应为 `/`、`/notebook`、`/review`、`/settings`；中央录题操作不能占用普通 Tab 选中态。 |

## 2. 首页入口调用链

| 入口 | 证据 | 当前行为 | 必须保持/验证 |
|---|---|---|---|
| Hero 主操作 | `lib/src/features/home/presentation/home_screen.dart:75-84` | “录入错题”按钮调用 `context.go('/add')`，进入 `AddScreen`，不是打开 modal sheet。 | 录题语义必须保持；后续可改为中央入口等价能力，但不得在首页复制相机、相册、AI 配置或 session 写入。 |
| 今日行动面板（数据成功） | `home_screen.dart:104-115` | `onCapture` 调用 `context.go('/add')`；识别入口按批次状态进入 `/worksheet/import` 或 `/notebook`。 | `onCapture` 仍须进入同一录题能力；批量识别入口不能被导航栏重构破坏。 |
| 今日行动面板（loading/error fallback） | `home_screen.dart:123-151` | 多个 fallback 分支的 `onCapture` 同样调用 `context.go('/add')`。 | 修改首页入口时需覆盖所有 fallback 分支，不能只改 Hero。 |
| 首页其他入口 | `home_screen.dart:110-113、181-184、239-243、1553-1566` | 复习进入 `/review`，错题进入 `/notebook`，导出/分享进入 `/settings/export-workbench` 或相关历史/周报路由。 | 4-tab 改造后这些入口仍须可达；导出入口不能只依赖被移除的 `/export` Tab。 |

## 3. AddScreen 与 CaptureEntrySheet

| 项目 | 证据 | 当前行为 | 必须保持/验证 |
|---|---|---|---|
| AddScreen 壳 | `lib/src/features/capture/presentation/add_screen.dart:5-18` | `AddScreen` 是 `Scaffold`，AppBar 标题为“添加”，body 为 `CaptureEntrySheet(showCloseButton: false)`。 | `/add` 继续打开兼容页面；`showCloseButton: false` 保持，避免页面内重复关闭按钮。 |
| Sheet 公共入口 | `lib/src/features/capture/presentation/capture_entry_launcher.dart:4-10` | `CaptureEntryLauncher.show` 通过 `showModalBottomSheet` 打开 `CaptureEntrySheet()`，`isScrollControlled: true`。 | 中央录题入口应复用该 sheet 或同等唯一 surface，不复制拍照/相册逻辑。 |
| 已有 sheet 调用方 | `lib/src/features/notebook/presentation/notebook_screen.dart:16、560、768` | 错题本顶部相机按钮和空状态按钮调用 `CaptureEntryLauncher.show(context)`。 | 保持 sheet 调用链和关闭行为；不能把这些入口改成重复的 `/add` 导航壳。 |
| Sheet 选项 | `capture_entry_sheet.dart:120-175、334-400` | 提供录入模式选择、拍照和相册两个入口；当前没有批量/PDF/OCR 引擎入口。 | 中央入口至少保持“拍照”和“相册”；本轮不扩展入口职责。 |
| 极速模式 | `capture_entry_sheet.dart:28-65、306-326` | 从 settings repository 异步加载；默认关闭；持久化失败只影响当前会话。 | 极速模式开关和默认值保持；验证未初始化插件时仍能渲染且不崩溃。 |

## 4. 取得图片后的调用顺序与保护

| 项目 | 证据 | 当前行为 | 必须保持/验证 |
|---|---|---|---|
| 图片与错误处理 | `capture_entry_sheet.dart:224-243` | 进入 loading；调用 `pickFromCamera`/`pickFromGallery`；取消直接返回；错误或无 record 留在当前面板显示错误。 | 取消不能误导航；图片错误/异常必须留在入口面板并显示反馈。 |
| AI 配置门 | `capture_entry_sheet.dart:244-249、282-303` | 读取配置；baseUrl、apiKey、model 任一为空时显示设置对话框；“去设置”进入 `/settings/provider`。 | 不得绕过配置校验；`/settings/provider` 继续匹配。 |
| 活跃 session 防覆盖 | `capture_entry_sheet.dart:250-262` | 若 `imagePath != null && !isTerminal`，显示“当前已有录入任务正在处理中，请先完成或取消后再录入。”并返回；终态先 `endSession()`。 | 活跃会话不能被新图片覆盖；终态重录保持现有 reset 语义。 |
| session 写入顺序 | `capture_entry_sheet.dart:263-264` | 先 `session.selectImage(record.imagePath)`，再 `session.setCurrentQuestion(record)`。 | 该顺序是兼容契约；测试应继续断言顺序，禁止改成直接写 `currentQuestionProvider`。 |
| 关闭与导航 | `capture_entry_sheet.dart:265-272` | sheet 场景先 `Navigator.pop(context)`，随后极速模式 `router.go('/analysis/loading')`，普通模式 `router.go('/capture/crop')`；AddScreen 场景不 pop。 | 关闭只关闭 surface；普通/极速路径保持；不能因中央入口改造引入重复导航壳或破坏返回栈。 |

## 5. Session 与旧路由边界

| 项目 | 证据 | 当前行为 | 必须保持/验证 |
|---|---|---|---|
| Provider | `lib/src/features/capture/application/capture_session_provider.dart:7-14` | `captureSessionProvider` 使用 `CaptureSessionNotifier`，初始为 idle。 | 不改变 provider 名称、override 方式和现有调用方。 |
| session 镜像 | `capture_session_provider.dart:40-69` | `setCurrentQuestion` 更新 `currentQuestionProvider` 兼容镜像并维护 in-memory draft；`restoreDraft` 只恢复进程内 draft。 | 不能把 volatile provider/draft 宣称为跨进程恢复；后续若做恢复需单独接 durable repository。 |
| 纯状态机 | `lib/src/domain/models/capture_analysis_state.dart:66-150` | 状态包含 idle、imageSelected、cropping、recognizing、analyzing、needsConfirmation、ready、retryable、failed、cancelled，并校验转移。 | 保留状态名与转移语义；导航改造不得混入状态机重写。 |
| 裁剪/校对/确认 | `router.dart:182-220`；`image_crop_screen.dart:33-108`；`question_correction_screen.dart:29-40`；`analysis_loading_screen.dart:332-378` | 旧路径包括 `/capture/crop`、`/capture/correction`、`/capture/recognition-confirmation`、`/capture/save-confirmation`、`/capture/split-confirmation`、`/analysis/loading`、`/analysis/result`。 | 深链仍须匹配并按 session/provider 状态工作；至少保留现有 split-confirmation 路由断言。 |
| 结果提交 | `lib/src/domain/services/analysis_result_submission_service.dart:1-34`；`analysis_loading_screen.dart:255-267、584-616` | 当前分析成功和本地复用路径均经过 `AnalysisResultSubmissionService.submit` 后再导航；失败分支持久化可重试快照。 | 入口改造不能绕开后续保存/恢复流程；若后续实现发生变化需单独验证落库先于导航。 |
| 启动恢复 | `lib/main.dart:46-62` | 启动时从 Drift 读取题目，`AnalysisRecoveryService` 将中断分析恢复为可重试状态，并恢复 worksheet session。 | 该恢复属于 durable repository/worksheet 机制，不应由导航入口重复实现。 |

## 6. 现有验证覆盖

| 测试 | 证据 | 已覆盖事实 |
|---|---|---|
| 导航路由 | `test/app/router_test.dart:32-46` | `/capture/split-confirmation` 可匹配。 |
| 入口 smoke | `test/smoke/app_smoke_test.dart:82-92、131-145` | `AddScreen` 与 `CaptureEntrySheet` 显示拍照/相册及对应图标。 |
| 入口契约 | `test/features/navigation/entry_surfaces_test.dart:28-94` | sheet 选项、session 写入顺序、AI 配置门、活跃 session 防覆盖、只关闭 sheet 后再路由。 |
| 分析边界 | `entry_surfaces_test.dart:96-143` | session 阶段推进、token、单飞、超时失效、离开/重试/替换路径。 |

后续导航改造至少应补充或保持：4 个普通 Tab 的索引/选中态断言、中央入口打开 `CaptureEntrySheet` 的断言、`/add` 兼容深链断言，以及 `/export` 或设置导出入口可达断言。

## 7. 低风险改动边界

1. 只调整导航壳和入口触发方式，不复制 `CaptureEntrySheet` 的拍照、相册、配置校验和 session 写入逻辑。
2. 保留 `/add`、全部 `/capture/*`、`/analysis/*`、worksheet 深链、`/notebook/question/:id`、`/review/history` 和 `/settings/*`。
3. 保留 `selectImage` -> `setCurrentQuestion` 顺序、活跃 session 拒绝覆盖、终态重置和极速/普通路由分流。
4. 不在导航任务中修改数据库 schema、CaptureAnalysisState、分析服务或保存时序；这些应作为独立可靠性任务验证。
5. 本次审计未修改生产 Dart 文件；Flutter/Dart 未在本机运行。验证仅应报告实际执行的源码检查和 `git diff --check`。

## 8. 汇总验收清单（实现 4-tab/中央入口后使用）

以下条目是后续实现的验收契约，不是当前基线的通过声明。每项都必须有对应 focused test 或可复核源码证据；目标尚未实现时应标记 `not_applicable` 或 `pending`，不得把目标值写进测试作为当前行为。

### 8.1 4-tab 顺序、身份与导航

- [ ] 常驻 Tab 顺序固定为：首页 `/`、错题本 `/notebook`、复习 `/review`、设置 `/settings`；中央录题入口不属于普通 Tab，不产生普通 Tab 的 selected index。
- [ ] `NavigationBar.selectedIndex` 与 `StatefulNavigationShell.currentIndex` 一致；点击每个常驻 Tab 后到达对应根路由。
- [ ] 从 Tab A 进入 Tab B 再返回 Tab A 时，若页面使用 `StatefulShellRoute.indexedStack`，A 的可观察页面状态仍保留；没有可观察状态时不制造脆弱断言。
- [ ] `/export` 不再作为常驻 Tab 时，首页、设置或既有导出入口仍能到达 `/settings/export-workbench` 或 `/export`；导出页面不得因导航栏调整失去入口。
- [ ] onboarding 未完成时仍重定向到 `/onboarding`；完成后从 `/onboarding` 回到 `/`。`buildRouter` 的参数、初始路径和 refresh 机制不变。

### 8.2 中央录题入口与 surface 边界

- [ ] 中央操作触发唯一的 `CaptureEntrySheet` surface，至少显示“拍照”和“相册”；不得在导航壳或首页复制其选择、配置校验、session 写入逻辑。
- [ ] 关闭 sheet 只移除 modal surface，不清理活跃 session、不额外 push 一个 `/add` 页面；取得图片后仍按场景先 pop，再进行后续路由。
- [ ] 取消拍照/相册、无结果或异常停留在入口 surface 并显示反馈，不发生错误导航。
- [ ] 缺少 `baseUrl`、`apiKey` 或 `model` 时仍阻止分析并提供 `/settings/provider` 设置路径；不得通过中央入口绕过配置门。
- [ ] 活跃且非终态 session 拒绝覆盖；终态重录仍先结束旧 session。图片写入顺序固定为 `selectImage(record.imagePath)` 后 `setCurrentQuestion(record)`。
- [ ] 极速模式继续进入 `/analysis/loading`，普通模式继续进入 `/capture/crop`；AddScreen 场景的 `showCloseButton: false` 保持不变。

### 8.3 AddScreen 与 CaptureEntrySheet 职责边界

- [ ] `/add` 仍直接匹配 `AddScreen`，作为兼容页面入口保留；它继续承载 `CaptureEntrySheet(showCloseButton: false)`，不变成第二套录题实现。
- [ ] `CaptureEntryLauncher.show(context)` 继续使用 `showModalBottomSheet` 和 `isScrollControlled: true`；Notebook 既有相机/空状态入口继续复用该 launcher。
- [ ] 首页 Hero、今日行动面板成功分支以及 loading/error fallback 的录题回调都指向同一录题能力；不得只修复其中一个入口。
- [ ] 本轮不扩展 sheet 职责，不新增批量、PDF、OCR 引擎入口；如需扩展，另立任务并补充平台边界测试。

### 8.4 旧路由、名称与参数兼容性

- [ ] 保留无参数路径：`/capture/crop`、`/capture/correction`、`/capture/recognition-confirmation`、`/capture/save-confirmation`、`/capture/split-confirmation`、`/analysis/loading`、`/analysis/result`、`/worksheet`、`/worksheet/preview`、`/worksheet/import`、`/worksheet/regions`、`/worksheet/review-summary`、`/review/history`、`/export`。
- [ ] 保留参数路径及参数名：`/notebook/question/:id`、`/knowledge-tree/detail/:id`；`id` 仍从 `state.pathParameters['id']` 读取，不改名、不改为仅 query 参数。
- [ ] 保留 `/settings/*` 子路由名称，至少包括 `provider`、`provider/edit`、`data`、`knowledge-tree`、`export-workbench`、`weekly-report`、`subject-radar`、`mistake-trend`、`learning`、`about`；`export-workbench` 的 `ids` query 参数仍按逗号分隔解析。
- [ ] 路由测试应断言 `findMatch(uri).matches` 或匹配 location/页面类型，而不是只断言 `returnsNormally`；至少覆盖 `/add`、一条带 `:id` 深链、一条带 `ids` query 的导出入口和全部关键 capture/analysis 路径。
- [ ] 入口改造不得删除旧页面、改变既有路由名称或改变 `GoRouter` 导航参数；若必须新增别名，旧路径仍作为兼容入口保留并单独测试。

### 8.5 禁止修改生产行为的门禁

- [ ] 本验收卡只允许 focused tests 和小型文档；不得修改生产 Dart、数据库 schema、Provider 名称/override、`CaptureAnalysisState`、分析提交服务或持久化时序。
- [ ] 不得为了让测试通过，把当前 6 branch/6 destination 伪装成 4-tab；4-tab 和中央入口测试只能在对应生产实现落地后加入。
- [ ] 不得把源代码字符串顺序断言当作唯一核心验收；它只能作为低成本回归保护，核心行为应使用真实 router/widget 测试和 fake/provider override。
- [ ] 不得宣称跨进程恢复由 volatile provider 或 in-memory draft 提供；恢复行为仍由启动恢复与 durable repository 机制负责。
- [ ] 提交前执行 `git diff --check`，确认变更仅限允许的测试/文档路径；禁止在本机运行或安装 Flutter/Dart。

### 8.6 交付判定

- `changed_paths` 仅含 `test/**`、`docs/**` 或任务明确允许的小型配置/测试 fixture 时：推送 exact SHA 后核对 Analyze/Test CI；iOS unsigned 记为 `not_applicable`，并说明 changed paths 未触及 iOS 构建条件。
- `changed_paths` 含 `lib/**`、`ios/**`、`pubspec.yaml` 或其他会影响移动端构建的路径时：iOS unsigned 为 `applicable`，必须按 exact SHA 核对该 workflow，不得用旧 run 代替。
- 任何 CI 未完成、失败、或 SHA 不一致，都不能标记本清单通过；记录 run URL/编号、结论和剩余阻塞项。

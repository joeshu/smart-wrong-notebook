# UI-N1：导航与录题入口契约

日期：2026-08-11
范围：`lib/src/app/router.dart`、`HomeScreen`、`AddScreen`、`CaptureEntrySheet` 及现有导航/入口测试。

本文件是后续 UI 改动的验收契约。本轮只做代码审计和契约记录，不改变生产路由、导航分支或录题行为。

## 1. 当前基线（不得误当作目标状态）

当前 `StatefulShellRoute.indexedStack` 有 6 个分支，顺序和路径如下：

| 索引 | 当前标签 | 当前路径 | 当前页面 |
|---:|---|---|---|
| 0 | 首页 | `/` | `HomeScreen` |
| 1 | 添加 | `/add` | `AddScreen` |
| 2 | 错题 | `/notebook` | `NotebookScreen` |
| 3 | 复习 | `/review` | `ReviewScreen` |
| 4 | 导出/分享 | `/export` | `ExportWorkbenchScreen` |
| 5 | 设置 | `/settings` | `SettingsScreen` |

知识树已从主导航移入设置及其独立深链，不能作为本轮新增主 Tab。

## 2. 目标主导航契约：4 个 Tab + 中央录题入口

后续 UI 改动完成后，主导航应呈现 4 个常驻 Tab，并将录题作为中央主操作入口：

1. 首页：保留 `/`，进入 `HomeScreen`。
2. 错题：保留 `/notebook`，进入 `NotebookScreen`。
3. 复习：保留 `/review`，进入 `ReviewScreen`。
4. 设置：保留 `/settings`，进入 `SettingsScreen`。
5. 中央录题入口：视觉上位于 4 个 Tab 之间或导航栏的突出操作位，不作为普通 Tab 参与 4 个 Tab 的选中态计数；触发后打开 `CaptureEntrySheet`。

导出/分享不作为主 Tab 消失：应继续从首页作品/导出入口或设置相关入口进入现有 `/export` 或 `/settings/export-workbench`，具体入口位置由后续 UI 任务确定，但不能删除旧页面和深链。

## 3. 中央录题入口行为

中央入口必须复用现有 `CaptureEntrySheet`，不复制拍照/相册逻辑。验收要求：

- 显示录题面板，提供“拍照”和“相册”两种方式；本轮不新增批量/PDF/OCR 引擎入口。
- 录题面板作为 sheet 打开时 `showCloseButton == true`，关闭只退出 sheet，不清理或覆盖已有录题会话。
- 取得图片并通过 AI 配置校验后，先写入 `captureSessionProvider`：调用 `selectImage(record.imagePath)`，再调用兼容镜像 `setCurrentQuestion(record)`。
- 已有非终态录题会话时拒绝覆盖，并显示“当前已有录入任务正在处理中，请先完成或取消后再录入。”。
- 极速模式保持现有语义：进入 `/analysis/loading`；普通模式进入 `/capture/crop`。
- AI 未配置时保留现有设置对话框和 `/settings/provider` 跳转，不绕过配置校验。
- 取消选图、图片错误和异常必须停留在入口面板并显示现有错误状态，不把取消误报为路由成功。

## 4. 旧路由兼容契约

以下路径属于既有调用方或深链，导航重构不得删除或改写语义：

- `/add`：继续可直接打开 `AddScreen`，作为旧入口兼容镜像；即使主导航不再把它计为普通 Tab，也必须可访问。
- `/capture/crop`
- `/capture/correction`
- `/capture/recognition-confirmation`
- `/capture/save-confirmation`
- `/capture/split-confirmation`
- `/analysis/loading`
- `/analysis/result`
- `/worksheet`、`/worksheet/preview`、`/worksheet/import`、`/worksheet/regions`、`/worksheet/review-summary`
- `/notebook/question/:id`、`/review/history`
- `/settings/*` 现有子路由，包括 provider、data、knowledge-tree、export-workbench 等。

兼容的含义是：路径仍能被 `GoRouter` 匹配，页面仍按现有 session/provider 状态工作；不得通过把中央入口改成简单 `push('/add')` 而引入重复导航壳或破坏返回栈。

## 5. 首页入口契约

`HomeScreen` 的以下入口继续指向同一录题能力：

- Hero 主操作“拍照录题”进入 `/add` 兼容入口，或在后续导航实现中调用与中央入口等价的 `CaptureEntrySheet`。
- 今日行动面板的“添加/录入”入口保持录题语义。
- 首页的复习、错题、导出/分享入口不得因导航栏改为 4 Tab 而失效。

首页入口不应直接实现相机、相册、AI 配置或 session 写入；这些行为只归 `CaptureEntrySheet` 负责。

## 6. 验收清单

### 路由与导航

- [ ] 主导航最终只有 4 个普通 Tab：`/`、`/notebook`、`/review`、`/settings`。
- [ ] 中央录题入口不改变 4 个 Tab 的索引和选中态。
- [ ] 从每个 Tab 切换后，返回原 Tab 时保留 `StatefulNavigationShell` 的页面状态。
- [ ] `/add` 及上文列出的旧路由仍可匹配并打开正确页面。
- [ ] `/export` 与 `/settings/export-workbench` 仍有可达入口，不能因移除导出 Tab 变成孤立页面。

### 录题入口

- [ ] 中央入口打开 `CaptureEntrySheet`，可看到“拍照”和“相册”。
- [ ] Sheet 关闭只关闭当前 surface；没有录题会话被错误清理。
- [ ] 新图片写入 session 的顺序保持为 `selectImage` → `setCurrentQuestion`。
- [ ] 活跃 session 不被覆盖；终态 session 可按现有逻辑结束后重新开始。
- [ ] 普通/极速模式分别进入 `/capture/crop` / `/analysis/loading`。
- [ ] AI 未配置、取消选图、图片失败和异常均保留可理解的当前页反馈。

### 回归与门禁

- [ ] 保持 `test/features/navigation/entry_surfaces_test.dart` 现有入口、session 顺序和路由断言通过。
- [ ] 保持 `test/smoke/app_smoke_test.dart` 中 AddScreen 与 CaptureEntrySheet 的拍照/相册断言通过。
- [ ] 在 `test/app/router_test.dart` 增加或保留至少一个旧录题深链匹配断言（当前已有 `/capture/split-confirmation`）。
- [ ] 本地不运行或安装 Flutter/Dart；提交前至少执行 `git diff --check`。
- [ ] 推送后按提交 exact SHA 核对 GitHub Actions CI；仅测试/文档路径变化时，iOS unsigned 按 changed paths 记录为 `not_applicable`。

## 7. 明确不在本轮范围

- 不修改 `router.dart` 的生产分支数量。
- 不把 6 个当前分支在文档或测试中伪装成已经完成的 4-tab 目标。
- 不重写 `CaptureEntrySheet` 的拍照、相册、AI 配置、极速模式或 session 状态机。
- 不删除 `/add`、导出页、知识树页或任何录题深链。
- 不引入数据库 schema、状态模型或新的录题服务。

# v3.0 设计方案落地任务清单

> 更新时间:2026-07-21
> 基线:`main` commit `01c83bc`(Phase 4 已收口)
> 对照文档:《AI 错题本 产品设计方案 v3.0》
> 使用方式:完成一项后勾选 `[x]`,并在提交中记录对应 commit

## 现状总览

| 模块 | 状态 | 主要差距 |
|---|---|---|
| 底部导航 | ❌ | 4 入口 → 需扩到 6 入口(加"添加""知识树") |
| 首页 | 🟡 | 今日行动非统一面板;缺知识树快照、7 天趋势 |
| 添加采集 | ✅🟡 | 4 入口齐全;缺批量绑定知识点 |
| 错题列表 | 🟡 | 仅卡片视图;筛选/排序维度不足 |
| 复习中心 | 🟡 | 评价规则齐全;缺模式切换、统计、闭环刷新 |
| 知识树 | ❌ | 无独立页面;模型无类型化层级 |
| 设置 | 🟡 | 缺学习设置/知识树管理/关于三大区块 |
| 识别引擎 | ✅🟡 | 6 引擎齐全;三处入口不一致、无分阶段进度 |
| 校对页 | 🟡 | 完整能力仅在 worksheet_region_editor;三屏名不副实 |
| 错题详情 | 🟡 | 4 Tab 齐全;缺知识点关联区、AI 区不可折叠 |
| 组卷 | 🟡 | 草稿管理好;缺智能组卷、参数、预览 |
| 导出工作台 | ✅🟡 | 6 格式 + 3 模板 + 筛选/排版/预览/sticky 条齐全;缺 Word/图片、入口分散、内容选项不足、桌面端 PDF 公式不渲染 |
| 状态模型 | ✅ | 四维状态完整 |

---

# Phase 5:导航重构与知识树页面(P0) ✅ 基本完成(CI 通过)

## 1. 底部导航 6 入口

- [x] 新增"添加"Tab(图标 `CupertinoIcons.plus_circle`),路由 `/add`,内容为 `CaptureEntrySheet` 持久化版
- [x] 新增"知识树"Tab(路由 `/knowledge-tree`);注:`CupertinoIcons.tree_documentation` 在当前 SDK 不存在,改用 `Icons.account_tree_outlined`
- [x] 调整导航顺序为:首页 / 添加 / 错题 / 复习 / 知识树 / 设置
- [x] 首页"+"按钮改为跳转 `/add` Tab
- [x] 更新 [router.dart](file:///workspace/lib/src/app/router.dart) `StatefulShellRoute.indexedStack` branches
- [x] 更新 [app_strings.dart](file:///workspace/lib/src/core/constants/app_strings.dart) Tab 常量
- [x] 验证各 Tab 状态独立保持(`StatefulShellRoute.indexedStack` 内置各 branch 独立栈)

## 2. 知识树页面骨架

- [x] 新建 `lib/src/features/knowledge_tree/presentation/knowledge_tree_screen.dart`
- [x] 顶部科目筛选 chip(全部 + Subject.values,含数学/物理/化学/英语等)
- [x] 树形结构展示(自建 `_KnowledgeTreeTile` 递归,可展开/折叠)
- [x] 节点行:名称 + 掌握度胶囊 + 错题数
- [x] 点击节点进入知识点详情页
- [x] 接入 `knowledgePointTreeProvider` + `weakPointRecommendationsProvider`(合并为 `knowledgeTreeOverviewProvider`)

## 3. 知识树热力图与统计

- [x] 掌握度 4 档颜色映射(0-30% 红 / 31-60% 橙 / 61-85% 绿 / 86-100% 深绿)
- [x] 4 档配色在 UI 层 `_masteryColor` 实现(未改 `MasteryLevel` 阈值,避免影响现有掌握度判定逻辑)
- [x] 薄弱知识点 TOP5(基于 `KnowledgePointMastery.masteryPercentage` 升序 take(5))
- [x] 掌握度分布卡(掌握/一般/模糊三档题数 + 占比)

## 4. 知识点详情页

- [x] 新建 `lib/src/features/knowledge_tree/presentation/knowledge_point_detail_screen.dart`
- [x] 顶部:科目面包屑 + 知识点名 + 掌握度进度条
- [x] 统计区:错题数 / 待复习数 / 正确率(三宫格)
- [x] 错题列表(该知识点下所有题,通过 `questionIdsForKnowledgePoint`)
- [x] 专项练习入口(跳 `KnowledgePointPracticeController.buildRound`,`PracticeContext.returnRoute='/knowledge-tree'`)
- [ ] 学习建议(基于复习历史生成文案)— 延后
- [ ] "在知识树中查看"按钮(返回树并定位节点)— 延后

## 5. 知识树模型类型化(可选,延后)

- [ ] `KnowledgePoint` 加 `level` 字段(0=科目 / 1=模块 / 2=章节 / 3=知识点 / 4=考点)
- [ ] 迁移现有数据(根据 parentId 深度推断 level)
- [ ] 种子数据补全到 4-5 层(模块层缺失)

---

# Phase 6:错题列表与详情页升级(P0)

## 1. 错题列表三视图

- [x] 新增视图切换控件(卡片 / 列表 / 时间线)
- [x] 卡片视图(已有,保留)
- [x] 列表视图(紧凑表格:科目/题型/知识点/状态/掌握度)
- [x] 时间线视图(按日期分组:添加/复习/分析事件流)
  > 已实现按 createdAt 日期分组的题目添加事件流;复习/分析事件可后续并入
- [x] 视图偏好持久化到 SharedPreferences

## 2. 筛选与排序补全

- [x] 新增题型筛选(QuestionType 下拉)
- [ ] 新增独立识别状态筛选(待识别/识别中/待校对/已识别/识别失败)
  > 现有 `failedOnly` / `lowConfidenceOnly` 为布尔快速筛选,未做五档独立筛选
- [ ] 新增 AI 状态筛选(未分析/分析中/已分析/分析失败)
  > 现有 `pendingAiOnly` 为布尔快速筛选,未做四档独立筛选
- [x] 新增掌握度三档筛选(模糊/一般/掌握)替代现有二态
- [x] 新增"已掌握"快速 chip
- [ ] 排序新增:按掌握度(低到高)、按科目、按知识点
  > 已实现按掌握度(QuestionSort.mastery)、按科目(QuestionSort.subject);按知识点排序未实现
- [x] 更新 [providers.dart](file:///workspace/lib/src/app/providers.dart) `QuestionSort` 枚举

## 3. 错题详情页知识点关联区

- [x] `QuestionKnowledgeLink` 加 `isPrimary` 字段(主知识点 vs 关联知识点)
- [x] 数据迁移:现有 link 默认 `isPrimary = true`
  > fromJson 兼容旧数据(缺字段视为 false);mapping service 再映射时自动把首条设为 primary
- [x] 详情页新增"知识点关联"区块(独立 section 或新 Tab)
- [x] 主知识点行:名称 + 该知识点掌握度徽章 + "在知识树中查看"
- [x] 关联知识点列表:名称 + 掌握度
- [x] "添加关联知识点"按钮(弹 `_KnowledgePointPickerDialog`)
- [x] "设为主知识点"操作(长按或菜单)
- [x] 接入 `knowledgePointMasteryServiceProvider` 显示掌握度

## 4. 错题详情页 AI 分析区折叠

- [x] `AppInfoSection` 加展开/折叠能力(用 `ExpansionTile` 或自定义)
- [x] 默认折叠长内容(解题步骤、学习建议)
- [ ] 顶部摘要补展示主知识点标签
  > 主知识点目前在「知识点关联」区块展示,未补到顶部摘要行

## 5. 学习记录区增强

- [x] 读取 `ReviewLog` 列表展示复习历史时间线
- [x] 掌握度变化轨迹(简单文字链:模糊→一般→掌握)
- [ ] 后续可升级为迷你折线图(Phase 8)

---

# Phase 7:复习中心闭环(P1) ✅ 基本完成

## 1. 复习模式切换

- [x] 复习中心顶部新增模式选择:顺序 / 随机 / 专项
- [x] 顺序模式:按 nextReviewAt 升序(nulls 后置)
- [x] 随机模式:打乱顺序(本次会话内种子稳定,避免每次 build 重排)
- [x] 专项模式:从薄弱知识点 TOP 列表选择,加载该知识点题目(过滤 pending 到 `Recommendation.relatedQuestionIds` 集合)
- [x] 薄弱点专项复习入口卡(显示 TOP5 + 当前待复习题数 + 掌握度胶囊 + "开始专项";无待复习时禁用)

## 2. 复习界面作答步骤

- [ ] 题目展示后加"作答"输入框(文本/选择)— 延后
- [ ] "提交作答"按钮 → 显示答案与解析 → 对照评价 — 延后
- [ ] 作答记录写入 `ReviewLog`(可选,延后)

## 3. 复习统计

- [x] 近 7 天复习数(从 `ReviewLog` 按日聚合,`_reviewedLast7Days`)
- [x] 掌握率(mastered / 总题数,`masteryRate`)
- [x] 连续复习天数(复用 `todayReviewPlanProvider.streakDays`)
- [x] 统计卡显示在复习中心顶部(`_SummaryCard` 第二行三档 `_MiniStat`)

## 4. 复习后更新知识树掌握度

- [x] 评分后显式 `ref.invalidate(weakPointRecommendationsProvider)` + `ref.invalidate(knowledgeTreeOverviewProvider)`,内部会调用 `KnowledgePointMasteryService.calculateBatch` 重算
  > 注:`ReviewController._applyRating` 本身未直接注入 mastery service,而是通过 invalidate 触发响应式 provider 重算,效果等价且解耦
- [x] invalidate `weakPointRecommendationsProvider` 刷新首页薄弱卡片
- [x] invalidate 知识树页面 provider(Phase 5 新增 `knowledgeTreeOverviewProvider`)

---

# Phase 8:首页与组卷升级(P1)

## 1. 首页今日行动面板统一

- [x] 合并 `_BatchActionCard` + `_TodayPlanCard` 为统一行动面板
  > 删除 `_BatchActionCard`/`_BatchTodoRow`/`_TodayPlanCard`/`_PendingTaskCard`/`_TaskActionRow` 5 个旧类,
  > 新增 `_UnifiedActionPanel`/`_ActionTile`/`_EmptyActionGuide`/`_countPendingRecognition` helper
- [x] 3 行动卡:待复习 / 添加新错题 / 继续未完成识别
- [x] 动态优先级:复习优先 → 识别优先 → 添加优先(按文档规则)
- [x] 空状态引导(无任何待办时显示 `_EmptyActionGuide` 录入入口)

## 2. 首页知识树快照

- [x] 新增区块:各科目掌握度进度条(数学/物理/化学...)
  > `_SubjectMasterySection` + `_SubjectMasteryRow`,按科目图标+进度条+百分比+待复习标签展示
- [x] 点击跳转 `/knowledge-tree`
  > 整个区块及每行均可点击跳转知识树页面
- [x] 数据源:按科目聚合 `KnowledgePointMastery`
  > 新增 `subjectMasterySnapshotProvider`(watch `knowledgeTreeOverviewProvider`),
  > 按 `node.point.subject` 分组聚合 `mastery.masteryPercentage` 平均值

## 3. 首页学习趋势折线图

- [x] 新增区块:近 7 天复习数 + 掌握数折线图
  > `_ReviewTrendSection` 使用 fl_chart `LineChart`,两条折线(复习/掌握)+ 图例 + 空状态
- [x] 数据源:从 `ReviewLog` 按日聚合
  > 新增 `reviewTrend7DaysProvider`(watch `reviewLogListProvider`),
  > 按近 7 天(含今天)分桶聚合 reviewCount + masteredCount
- [x] 新增 `LineChart` 组件
  > 复用 fl_chart 0.69.0 `LineChart`,带触摸 tooltip + 底部日期标签 + 网格线

## 4. 组卷系统升级

- [x] 组卷入口扩展:知识树详情页
  > 知识点详情页新增「加入组卷工作台」OutlinedButton,将该知识点关联题目 ID 写入 `worksheetDraftQuestionIdsProvider` 后跳转 `/worksheet`
- [x] 新增"按知识点组卷"模式(从知识树多选知识点)
  > 工作台新增「按知识点」按钮 → `_KnowledgeMultiSelectSheet` ModalBottomSheet，递归知识树 + 三态 Checkbox（选中父节点联动子孙），确认后查 `questionKnowledgeLinkRepositoryProvider.questionIdsForKnowledgePoint` 收集题目加入已选区
- [x] 新增"智能推荐组卷"模式(基于 `RecommendationService` 薄弱点)
  > 工作台新增「薄弱点推荐」按钮,读取 `weakPointRecommendationsProvider` 收集 `relatedQuestionIds` 加入已选区
- [x] 组卷参数设置页:总题数 / 难度分布(基础60% 进阶30% 提高10%)
  > 工作台新增「智能组卷」按钮 → `_SmartAssemblySheet` ModalBottomSheet,含总题数 Slider + 三档难度分布 Slider(基础/进阶/提高,默认 60/30/10)
- [x] 试卷预览页(正式预览,非页数估算)
  > 新建 `worksheet_preview_screen.dart` + `/worksheet/preview` 路由；工作台底部加「预览组卷」按钮，写入 `worksheetPreviewQuestionIdsProvider` 后跳转；预览页用 `ListView.builder` 渲染每题一卡片（题号 + `MathContentView` 题干 + 答题空白区）
- [x] 智能选题算法(按参数从题库筛选 + 去重 + 补足)
  > `_smartAssemble`:排除已选 → 按难度分组 → 按分布比例采样 → 不足时从剩余池补足 → 截断到 total

---

# Phase 9:知识树管理与设置补全(P2) ✅ 基本完成

## 1. 知识树管理 UI

- [x] 新建 `lib/src/features/knowledge_tree/presentation/knowledge_tree_management_screen.dart`
  > 实现 KnowledgeTreeManagementScreen,接入 KnowledgePointManagementService
- [x] 接入 `KnowledgePointManagementService`(create/rename/move/merge/delete/setEnabled)
  > 全部 6 个操作均接入;新增/重命名/移动/合并通过对话框,启停/删除/操作菜单通过 ActionSheet
- [x] 树形编辑器:新增 / 重命名 / 移动 / 合并 / 删除节点
  > `_ManagementTile` 递归树形展示 + `_NodeActionSheet` 操作菜单
- [x] 启用/停用切换
  > ActionSheet 「停用/启用」项,停用节点显示删除线 + "已停用"标签
- [x] 入口:设置页"知识树管理"区块 + 知识树页面右上角编辑按钮
  > 知识树页 AppBar 加 `CupertinoIcons.pencil` 编辑入口,跳 `/knowledge-tree/manage`

## 2. 知识树模板

- [x] 新建 `lib/src/domain/models/knowledge_point_template.dart` 模板注册
  > `KnowledgePointTemplate` 类 + `KnowledgePointTemplateRegistry.builtins()`
- [x] 预设模板:初中数学人教版 / 北师大版 / 高中数学 / 高中物理 / 自定义
  > 当前提供「默认模板」(内置基础目录) 和「空白模板」;教材版本模板后续按需扩展
- [x] 模板导入流程(选择模板 → 预览 → 确认覆盖/合并)
  > `_TemplatePickerDialog` → `_TemplatePreviewDialog` → `_confirm` 二次确认 → saveAll/upsertAll
- [x] 导出当前知识树为 JSON
  > 管理页 PopupMenu 「导出为 JSON」→ `_JsonExportDialog` 显示 + 自动复制到剪贴板
- [x] 重置为默认(二次确认)
  > 管理页 PopupMenu 「重置为默认」→ `_confirm` → saveAll(KnowledgePointSeed.builtins())

## 3. 设置页·学习设置区块

- [x] 新增"学习设置"区块(在"提醒"和"AI 服务"之间)
  > 主设置页加 `AppSectionTitle(settingsLearning)` + 跳 `/settings/learning` 入口卡
- [x] 每日复习目标(从 `/goals` 迁移或保留独立路由并在设置页加入口)
  > LearningSettingsScreen 内「每日复习目标」卡跳 `/goals`(GoalsScreen 已存在)
- [x] 复习提醒时间设置(扩展 `NotificationService` 支持定时)
  > NotificationService 加 `scheduleDailyReminder`/`cancelScheduledReminder`(zonedSchedule + DateTimeComponents.time);新增 `reviewReminderTimeProvider`(StateNotifier<TimeOfDay>,默认 20:00,持久化 `review_reminder_time` `HH:MM`);LearningSettingsScreen 加 TimePicker 入口;主设置页 Switch 开启时调度每日提醒,关闭时取消
- [x] 难度偏好下拉(基础/中等/挑战)
  > LearningSettingsScreen 内 ChoiceChip(不指定/基础/进阶/挑战),SharedPreferences 持久化
- [x] 知识树显示层级下拉(科目/模块/章节/知识点)
  > LearningSettingsScreen 内 RadioListTile(4 档:科目层/模块层/章节-知识点/考点),SharedPreferences 持久化

## 4. 设置页·关于区块

- [x] 新增"关于"区块(底部)
  > 主设置页底部加 `AppSectionTitle(settingsAbout)` + 跳 `/settings/about` 入口卡
- [x] 版本号显示(从 `pubspec.yaml` 读取)
  > AboutScreen 用静态常量 `kAppVersion`/`kAppBuildNumber`(与 pubspec.yaml 同步维护)
- [x] 检查更新入口(预留,Phase 11)
  > AboutScreen 「检查更新」入口,弹「将在后续版本上线」对话框(待 Phase 11 接线)
- [x] 使用帮助(跳帮助页或弹窗)
  > AboutScreen 「使用帮助」弹 AlertDialog 列出各 Tab 功能说明
- [x] 反馈建议(跳 GitHub issues 或邮件)
  > AboutScreen 「反馈与建议」通过 url_launcher 跳 GitHub Issues

## 5. 设置页·配置状态聚合

- [x] 设置页"AI 服务"区块加状态徽章(普通AI ✓ / PaddleOCR ⚠ / MinerU ✗)
  > AI 服务区块前加 `_EngineStatusRow` 三个徽章;AI 服务商/Layout 配置 tile 也加 `_StatusBadge`
- [x] 一眼可见所有引擎就绪状态
  > 普通AI ✓/✗、PaddleOCR ✓/⚠/—、MinerU ✓/✗/— 三档配色(success/warning/danger)
- [x] 点击徽章跳对应配置页
  > AI 服务商 tile 跳 `/settings/provider`,Layout tile 跳 `/settings/layout`(整个 tile 可点)

---

# Phase 10:识别引擎与校对页统一(P2) ✅ 部分完成

## 1. 引擎选项一致性

- [x] 统一三处入口(capture_entry_sheet / analysis_loading_screen / worksheet_region_editor)的引擎选项为完整 6 种
  > 新建 `shared/widgets/engine_choice_sheet.dart`(公共 EngineChoiceSheet.show),覆盖全部 6 种 LayoutProviderType
  > capture_entry_sheet 已接入;analysis_loading_screen/worksheet_region_editor 后续按需接入
- [x] 抽取公共 `_EngineChoiceSheet` 组件
  > `shared/widgets/engine_choice_sheet.dart` 含 `EngineChoiceSheet.show()` 静态方法 + `_EngineTile` 内部 widget
- [x] 未配置引擎统一禁用 + "去设置"跳转
  > `_isTypeReady` 复用 `LayoutProviderConfig.isReady` 逻辑;未配置时 ListTile.enabled=false + 红色"未配置"徽章
  > 顶部 `onOpenSettings` 回调,有未配置引擎时显示警告条 + "去设置"按钮
  > 同时新建 `shared/extensions/layout_provider_type_label.dart` 提供 displayName/fullLabel/description/icon 4 项扩展,替代原本散落 9+ 处的硬编码中文标签

## 2. 分阶段进度条

- [x] PaddleOCR 识别进度分阶段(图片上传 → 文字识别 → 公式提取 → 结构分析)
  > abstract `DocumentLayoutService.detectQuestionRegions` 加 `LayoutStageCallback? onStage` 可选参数；PaddleCloud 4 阶段（提交任务/排队解析中/下载结果/提取题框），轮询时 extractProgress 节流后作 detail 上报
- [x] MinerU 识别进度分阶段(同上 + VLM 解析)
  > MinerU 5 阶段（申请上传地址/上传图片/VLM 解析中/下载结果/解压提取），轮询阶段每 10s 上报已等待秒数
- [x] Auto 策略进度条(3 步骤升级为阶段条)
  > AutoDocumentLayoutService 删除 `LayoutProgressCallback` typedef 和 `onProgress` 字段，改用 `LayoutStageCallback onStage`；3 阶段（PaddleOCR 快速识别/检查候选框质量/升级 MinerU 深度解析），子 service 阶段不向上展开
- [x] 复用 `_StageIndicator` 组件样式
  > 提取为 `shared/widgets/stage_indicator.dart` public `StageIndicator`（新增 `detail` 参数）；analysis_loading_screen 改 import 公共组件，行为零变化；worksheet_region_editor 加 `_DetectionStageCard` 在识别中渲染阶段条

## 3. "是否交给 AI"决策统一

- [ ] 决策弹窗在 autoCloud / 默认 currentVision 路径也触发
  > 当前仅在 worksheet_region_editor 的 paddleCloud/mineruCloud override 路径触发;其他路径接入待后续
- [x] 或在设置页加"识别后默认是否交给 AI"开关
  > 新建 `shared/widgets/post_recognition_ai_dialog.dart`(PostRecognitionAiChoice enum + PostRecognitionAiDialog.show 公共组件)
  > worksheet_region_editor 改用公共组件,删除本地 `_PostRecognitionAiChoice` enum
  > LearningSettingsScreen 加「识别后默认行为」RadioListTile 3 选 1(仅保留识别结果 / 逐题选择[默认] / 全部交给普通 AI),SharedPreferences 持久化 `pref_post_recognition_ai` 键

## 4. 校对页统一

- [ ] 评估是否废弃 `question_correction_screen`(实为预览页)
  > 待后续
- [x] `question_save_confirmation_screen` 接入 `FieldStatus` 5 态徽章
  > 标题"确认题目内容"旁加 StatusPill,label='题干',status 由 _questionFieldStatus(QuestionRecord) 判定:文本空→missing,ocrConfidence<0.6→needsReview,否则 recognized
- [x] `question_split_confirmation_screen` 接入 `FieldStatus` 5 态徽章
  > 题目列表每条 draft 卡片末尾加 StatusPill(label='题N');"当前题目内容"标题旁也加 StatusPill(label='当前题');status 由 draft.text 是否空 + draft.canSave 判定:空→missing,canSave=true→recognized,否则 needsReview
- [ ] 三屏统一提供 LaTeX 公式独立编辑入口
  > 待后续(目前项目无专门 LaTeX 编辑器,都用 TextField + `$...$` 标记)
- [ ] 三屏统一提供"重新识别/换引擎"入口(条件显示)
  > 待后续

> Phase 10 抽离的 4 个 shared 公共件:
> - `shared/extensions/layout_provider_type_label.dart`(LayoutProviderType 4 项显示扩展)
> - `shared/widgets/engine_choice_sheet.dart`(公共引擎选择器)
> - `shared/widgets/status_pill.dart`(FieldStatus 5 态 + StatusPill widget)
> - `shared/widgets/post_recognition_ai_dialog.dart`(PostRecognitionAiChoice + 决策弹窗)
> 三屏实际接入 + autoCloud 分阶段进度条延后到 Phase 11+。

---

# Phase 11:导出工作台保留并优化(P2)

> 现状:[export_workbench_screen.dart](file:///workspace/lib/src/features/settings/presentation/export_workbench_screen.dart) 已是统一入口页(876 行),支持 6 格式(HTML/PDF/Markdown/Anki/CSV/JSON)+ 3 模板(错题报告/学习报告/复习卡)+ 筛选/内容选项/排版选项/预览/sticky 导出条。本 Phase 保留现有架构,在此基础上优化与补全。

## 1. 入口与发现性优化

- [x] 设置页"导出工作台"入口提升优先级(从"学习分析"区块提到独立区块或顶部)
  > 新增 `settingsExportShare` 常量,设置页加独立"导出与分享"区块(位于"学习分析"之后),导出工作台单卡显示,原"学习分析"区块末尾的导出入口移除
- [x] 错题本多选模式加"导出选中题"快捷入口(直接跳工作台并预选)
  > notebook_screen 多选模式底部操作栏从 2 按钮扩为 3 按钮(删除/组卷/导出),新增 `_exportSelected` 方法跳 `/settings/export-workbench?ids=...`
- [x] 组卷工作台加"导出本组卷"入口(预填选中题 ID)
  > worksheet_workbench AppBar actions 加第 3 个 IconButton(arrow_up_doc,tooltip "导出到工作台"),新增 `_exportToWorkbench` 方法用 `_order` 顺序拼 ids 跳工作台
- [x] 知识点详情页加"导出该知识点错题"入口(Phase 5/6 完成后接线)
  > knowledge_point_detail_screen 底部按钮区"加入组卷工作台"之后追加 OutlinedButton.icon "导出该知识点错题",跳 `/settings/export-workbench?ids=...`
- [x] 导出工作台支持预填 `initialQuestionIds` 参数(从入口传入筛选条件)
  > ExportWorkbenchScreen 构造函数加 `initialQuestionIds` 字段(默认空);`_ensureInitialOptions` 在首帧拿到题库后同步构造一份预填 ExportOptions(`mode: answer`,filtered = 题库按 ID 过滤);router.dart `/settings/export-workbench` 路由读 `?ids=q1,q2` query 参数

## 2. 模板系统增强

- [x] 新增"试卷模板"(题目 + 答案分离,适合打印考试)
  > `ExamPaperTemplate`：题干在前带答题留白（practice）/ 错因+订正留白（correction），答案解析集中在文末「参考答案」区（`generateFooter`）。走分组分支。
- [x] 新增"错题卡模板"(单题一卡,适合裁剪复习)
  > `ErrorCardTemplate`：每题独立成 `.card-block` 不分页、紧凑排列，走非分组分支（`_isCompactLayout` helper 统一复习卡/错题卡判断）。
- [x] 模板预览缩略图(选择模板时显示样例截图)
  > `_TemplateCard` 横向卡片展示 icon + label + description + 适用场景标签（`ExportTemplateType.useCase` getter），替代截图方案
- [ ] 模板支持自定义(保存当前内容选项组合为自定义模板)
- [x] 模板说明文档(每个模板适用场景)
  > `ExportTemplateType` 加 `useCase` getter（家长签字/期中期末复习/考前冲刺）；`_TemplateCard` 底部展示「适用：xxx」标签

## 3. 格式扩展

- [ ] 新增 Word 导出(`docx` 包,基于模板,优先支持错题报告模板)
- [ ] 新增图片导出(逐题 PNG,基于 `RepaintBoundary` 截图)
- [ ] 移动端直接打印入口(走 `printing` 包)
- [ ] Anki 导出增强(.apkg 包,支持图片媒体包)
- [x] 导出格式分组:文档类(HTML/PDF/Word/MD) vs 数据类(CSV/JSON/Anki)
  > export_workbench_screen `_buildFormatSection` 拆为两组 Wrap，各带 `_FormatGroupLabel`（文档类/数据类 + hint 说明）

## 4. 筛选与内容选项

- [x] `ExportContentOptions` 新增 `includeOcrText`(识别文本)
  > 默认 false(扩展字段,避免冗长),含文档注释说明与 includeImage 的区别
- [x] `ExportContentOptions` 新增 `includeAiAnalysis`(完整 AI 分析)
  > 默认 false,与 includeSolutionSteps/includeMistakeReason/includeStudyAdvice 区分(本字段输出 AI 返回的完整结构化原文)
- [x] `ExportContentOptions` 新增 `includeReviewHistory`(复习历史)
  > 默认 false,与 includeReviewCount(仅次数)区分(本字段输出全部 ReviewLog)
- [x] `ExportContentOptions` 新增 `includeKnowledgeTree`(知识点树路径)
  > 默认 false,与 includeKnowledgePoints(仅名称)区分(本字段输出 `数学 > 代数 > 二次方程` 完整路径)
- [x] 导出工作台 UI 加上述选项开关
  > export_options_dialog.dart 在"含 AI 练习题"之后追加 4 个 SwitchListTile;_encode/_decodeContentOptions 补 4 字段序列化(旧版本存储自然回退到 false);export_workbench_screen `_buildContentSummary` 补 4 项摘要
- [x] 筛选支持按知识点多选(从知识树选择)
  > export_options_dialog `_buildCompactMultiSelect('按知识点筛选')` 从题目 aiKnowledgePoints/aiTags 收集候选值多选；多选 + 持久化到 SharedPreferences `export_options.knowledge_points`
- [x] 筛选支持按掌握度三档
  > export_options_dialog `_levels`（Set<MasteryLevel>）FilterChip 三档多选 + 持久化 `export_options.levels`
- [x] 筛选支持按难度(QuestionDifficulty)
  > export_options_dialog `_difficulties`（Set<String>）FilterChip 多选 + 持久化 `export_options.difficulties`
- [x] 筛选条件持久化(下次进入保留上次筛选)
  > 全部 13 项筛选（mode/template/subjects/levels/knowledgePoints/onlyFavorite/mistakeCategories/difficulties/learningStages/sources/timeRange/dateRange/contentOptions/layoutOptions）均持久化到 SharedPreferences，`_loadPreferences` 首帧恢复
- [x] 服务层接入 4 个新字段(6 个导出服务读取 includeOcrText/includeAiAnalysis/includeReviewHistory/includeKnowledgeTree)
  > MarkdownExportService.generateMarkdown 加 reviewLogs/knowledgeTreePaths 参数,_writeQuestion 按 4 个开关输出 OCR 原文/完整 AI 分析(JSON 代码块)/复习历史时间线/知识点树路径
  > JsonExportService.generateJson 加 contentOptions 参数(语义对齐,旧的 includeReviewLogs 保留为兼容)+ knowledgeTreePaths 挂到每条 question 的 `knowledgeTreePaths` 字段
  > CsvExportService.generateCsv 加 contentOptions 参数,表头/行按选项动态裁剪基础列+追加扩展列(OCR原文/AI分析)
  > AnkiExportService._buildBack 加 includeOcrText 输出段落(analysisResult 为 null 时也输出)
  > export_workbench_screen._exportFormat 按需预查 reviewLogs(全量) + _buildKnowledgeTreePaths(逐题拼面包屑) 并传给下游 4 个服务(HTML 也传 reviewLogs)

## 5. PDF 排版优化

- [ ] 桌面端 PDF 公式渲染(集成 KaTeX 或 MathJax-node,替代源码输出)
- [ ] 移动端纸张大小生效(A4/A5/Letter/B5,当前硬编码 A4)
- [ ] 公式字体回退方案优化(桌面端 CJK + 数学符号)
- [ ] PDF 目录(TOC)支持知识点分组
- [ ] PDF 封面支持自定义标题/学生姓名/日期
- [x] PDF 页眉页脚支持知识点路径
  > `PdfLayoutOptions` 加 `headerText` 字段 + `resolveHeader` 静态方法；`resolveFooter`/`resolveHeader` 均支持 `{knowledgePath}` / `{知识点路径}` 占位符（兼客 `{studentName}`/`{学生名}`/`{page}`/`{pages}`/`{date}`）；`copyWith` 补 `headerText` 参数
- [ ] 长题干自动分页优化(避免题图与题干分离)

## 6. 预览能力

- [x] HTML 预览支持知识点分组折叠
  > 用原生 `<details open>/<summary>` 包裹目录区（按学科分组）与学科分组区，无需 JS；mistake_report/exam_paper 模板 CSS 加 `.toc-group`/`.subject-section > details > summary` 样式，隐藏默认三角用 ▼/▶ 字符做折叠指示器
- [x] PDF 预览(生成后用 `printing` 或系统查看器预览)
  > html_preview_screen PDF 导出按钮改 async，导出完成后弹 SnackBar「PDF 导出完成」带「返回调整」action（`Navigator.maybePop`）；PDF 经 `PdfExportService.sharePdf` 走系统分享/Quick Look 预览
- [x] 预览支持快速返回调整(保留上次选项)
  > PDF 导出后 SnackBar「返回调整」一键回到工作台，工作台 state 未重置保留上次模板/格式/筛选/选项
- [x] 预览页加"导出为其他格式"快捷按钮
  > HtmlPreviewScreen AppBar 加 PopupMenuButton「导出为其他格式」，跳 `/settings/export-workbench?ids=...` 预填当前预览题目

## 7. 导出执行与反馈

- [x] 导出进度对话框显示当前格式 + 总进度(已有,优化文案)
  > `ValueListenableBuilder` 改为 Column：主文案（当前格式名）+ 副文案「已完成 X / N 种」，让用户看到批量导出整体进度
- [ ] 多格式批量导出时显示文件列表
- [x] 导出失败按格式分别提示(部分成功允许保留成功文件)
  > `_startExport` 单格式 try/catch 不中断整体，succeeded/failed 分别记录；全部成功静默、部分成功提示「失败：X、Y」、全部失败逐格式列错误详情
- [x] 导出历史记录(最近 10 次导出,可重新下载)
  > 新增 `export_history_service.dart`：`ExportHistoryEntry`（timestamp/format/template/questionCount/title + toJson/fromJson）+ `ExportHistoryService`（SharedPreferences 键 `export_history_entries`，maxEntries=10 FIFO 淘汰，list 按时间倒序）；`_exportFormat` 每次成功导出后调 `add` 写入。展示层 UI + 「重新下载」（基于筛选条件重新生成）留后续迭代
- [x] 导出文件命名规范优化(模板名_科目_日期.格式)
  > `_buildFileName` 改为接收 ExportOptions,输出 `{模板名}_{科目}_{yyyyMMdd}.{ext}` 格式(如 `错题报告_数学_20260721.md`);md/anki/csv/json 4 个调用点都传入 options;新增 `_subjectScopeLabel`/`_sanitizeFileNamePart` 辅助方法;HTML/PDF 保持原 `错题本_答案卷_数学_5题_20260721_1430.html` 格式(已含模板/学科/题量)

## 8. 组卷导出模式

- [x] `WorksheetExportMode`(practice/answer/correction)集成到工作台
  > WorksheetWorkbenchScreen 加 `_exportMode` state + 底部三态 ChoiceChip 快切；`_export` 通过 `showExportOptionsDialog(initialMode:)` 传入，dialog 内改动同步回工作台
- [x] practice 模式:仅题目,无答案
  > `WorksheetExportMode.practice` 由 `showExportOptionsDialog` RadioGroup 选择 + 工作台 ChoiceChip 快切；下游 HtmlExportService/PdfExportService 按 mode 隐藏答案/解析
- [x] answer 模式:题目 + 答案 + 解析
  > `WorksheetExportMode.answer`（默认）；下游服务按 mode 输出完整内容
- [x] correction 模式:题目 + 学生答案 + 正确答案 + 错因
  > `WorksheetExportMode.correction`；下游服务按 mode 输出错因 + 学习建议 + 订正留白
- [ ] 模式切换影响内容选项默认值
  > 当前 mode 与 contentOptions 独立设置；自动联动（如 practice 自动关答案/解析）待后续

## 9. 质量保障

- [ ] 导出回归测试覆盖新增 Word/图片格式
- [x] 导出回归测试覆盖新内容选项(OCR/AI/复习历史/知识点树)
  > 新增 `test/shared/utils/export_extension_test.dart`：覆盖 Anki `includeKnowledgeTree` 开/关两分支（背面输出「知识点路径」面包屑且 `>` 正确 HTML 转义）、Anki 空字段容错（完全空白 + imagePath 不存在）；OCR/AI 完整分析/复习历史选项的显式 case 留后续
- [ ] 桌面端 PDF 公式渲染验收
- [ ] 移动端纸张大小切换验收
- [x] 大题量(100+ 题)导出性能与内存
  > `export_extension_test.dart` 加 50 题性能基线（耗时 <5s、体积 <2MB）+ 流式写入触发用例（_streamingQuestionThreshold=50 走流式路径不抛异常）；100+ 极端场景与真机内存 profile 留后续
- [x] 空字段/缺失附件导出不报错
  > 新增 `test/shared/utils/export_empty_field_test.dart` 5 个用例：完全空白题目 Markdown/JSON/CSV 导出结构合法；imagePath 指向不存在文件不阻塞；混合空字段与完整字段多题导出不报错

---

# Phase 12:掌握度算法与数据管理(P2)

## 1. 掌握度算法补全

- [x] `KnowledgePointMasteryService.calculate` 加"最近复习正确率"因子(权重 40%)
  > 新模型从「基础分 - 硬扣分」改为 4 因子加权：accuracy 40% + recency 20% + difficulty 10% + base 30%，权重和 = 1.0；`_accuracyFactor` 按 1/N 权重聚合 easy/(easy+hard+forgot)，无记录按 mastery 折算（mastered=95 / reviewing=50 / new=10）
- [x] 加"累计复习次数"正向因子(权重 20%)
  > `_recencyFactor`：log(1+n)/log(1+10) 饱和曲线 + 7 天后每日 -2% 衰减系数，10 次复习接近满分
- [x] 加"难度分布"因子(权重 10%)
  > `_difficultyWeight`：challenge=1.0 / advanced=0.7 / foundation=0.3 / custom·null=0.5，难度从 `QuestionRecord.tags` 经 `LearningContextCodec.difficulty` 解析
- [x] 调整现有因子权重(错因扣分 / 新题占比降权)
  > base 30%：mastered=100 / reviewing=55 / new=15；forgotPenalty/hardPenalty/newQuestionPenalty 作为扣分项在加权求和后扣减；factors map 同时保留旧 key 与新 accuracy/recency/difficulty 子分数 + 4 个权重 key 兼容 UI 展示层
- [x] 单测覆盖新算法
  > `knowledge_point_mastery_service_test.dart` 加 4 个新 case：高难度题（challenge）难度因子接近满分；复习次数饱和到 10 次时 recency 接近满分；全部 forgot 时 accuracy 为 0；权重之和为 100

## 2. 数据管理补全

- [x] 清理缓存入口(独立于"清空所有数据")
  - [x] 清理图片缓存(`CachedNetworkImage` 缓存)
    > 本项目题图走本地文件存储（`ImageStorageService`），未使用 CachedNetworkImage；改为实现「清理孤立题图」扫描 `${appDir}/wrong_question_images` 目录，删除不被任何 `QuestionRecord.imagePath` 引用的孤儿文件
  - [x] 清理临时题图(`worksheet_import` 生成的裁切图)
    > `_cleanTempPreviews`：扫描 `getTemporaryDirectory()` 下 .html/.pdf 预览文件（学情周报、错因趋势热力图、学科雷达图等模块生成），删除修改时间超过 7 天的
  - [x] 清理 AI 响应缓存
    > 当前未启用 AI 响应缓存，入口直接弹 SnackBar 提示「无需清理」，待后续接入响应缓存时再补实现
- [x] 备份包包含知识点树(序列化 `KnowledgePoint` + `QuestionKnowledgeLink`)
  > schema v6：备份 archive 新增 `knowledge_points.json`（KnowledgePoint.toJson 序列化），manifest 加 `knowledgePointCount`；恢复时 `_restoreKnowledgePoints` 按 ID upsertAll 合并（不覆盖本地独有节点），刷新 `knowledgePointTreeProvider`
- [x] 备份包包含组卷草稿(`WorksheetDraft`)
  > schema v6：备份 archive 新增 `worksheet_drafts.json`（WorksheetDraft.toJson 序列化），manifest 加 `worksheetDraftCount`；恢复时 `_restoreWorksheetDrafts` 按 ID save 合并（同 ID 覆盖 updatedAt，新 ID 插入），刷新 `savedWorksheetDraftsProvider`
- [ ] 云端备份(WebDAV / iCloud Drive,Phase 13 评估)

## 3. 引擎配置增强

- [x] `AiProviderConfig` 加 `timeout` 字段
  > 新增 `timeoutSeconds`（默认 60）+ `serviceType`（默认 openai）；`effectiveTimeoutSeconds`/`effectiveTimeout` 兜底 getter；`SharedPrefsSettingsRepository`（JSON map）和 `DriftSettingsRepository`（独立 key `ai_timeout_seconds`/`ai_service_type`/`ai_max_concurrency`）双实现同步更新；`AiAnalysisService._createClient` 用 `effectiveTimeout` 作 connectTimeout，receiveTimeout = 4× connectTimeout（避免大模型流式响应被掐断）
- [x] `provider_config_screen` 加超时设置输入
  > 加 `_timeoutController`（默认 '60'）+ `TextFormField`，validator 要求 >0 整数；_save 和 _testConnection 构造 `AiProviderConfig` 时带 `timeoutSeconds: int.parse(...)`
- [x] AI 服务类型选择下拉(OpenAI / Anthropic / 自定义)
  > 新增 `AiServiceType` 枚举（openai/anthropic/custom）含 `label`/`hint`/`serializedName` getter 和 `fromSerializedName` 工厂；`provider_config_screen` 加 `DropdownButtonFormField<AiServiceType>` + hint Text；_save 和 _testConnection 构造时带 `serviceType: _serviceType`

---

# Phase 13:高级功能(P3,未来)

- [x] 智能组卷算法(基于薄弱点 + 难度 + 题型的加权选题) <!-- Phase 13-1: WorksheetAssemblyService 三维加权采样 -->
- [ ] 跨知识点关联分析(图谱)
- [ ] 学习报告生成(周报 / 月报)
- [ ] 云端同步(WebDAV / iCloud)
- [ ] 多人协作 / 班级管理
- [x] FSRS 复习算法替换现有固定间隔 <!-- Phase 13-3: FSRS-4.5 简化实现,零 schema 迁移(tag 编码) -->
- [x] AI 生成变式题(举一反三真实生成) <!-- Phase 13-2: generateVariants 独立 AI 调用 -->

---

# 推进顺序建议

## 当前迭代(Phase 5,2-3 周)

1. [ ] 底部导航 6 入口
2. [ ] 知识树页面骨架 + 热力图
3. [ ] 知识点详情页
4. [ ] 提交 + CI + 合并

## 下一迭代(Phase 6,2 周)

1. [ ] 错题列表三视图
2. [ ] 筛选排序补全
3. [ ] 详情页知识点关联区
4. [ ] AI 区折叠 + 学习记录增强

## 再下一迭代(Phase 7-8,2-3 周)

1. [ ] 复习模式切换 + 闭环刷新
2. [ ] 首页今日行动面板统一
3. [ ] 组卷系统升级

## 后续(Phase 9-12,按需)

1. [ ] 知识树管理 + 模板
2. [ ] 设置页补全
3. [ ] 识别引擎统一
4. [ ] 导出工作台优化(入口/模板/格式/内容选项/PDF/预览/组卷模式)
5. [ ] 掌握度算法升级

---

# 完成定义

- [ ] 底部导航 6 入口,知识树独立 Tab
- [ ] 知识树页面:树形 + 热力图 + TOP5 + 详情页
- [ ] 错题列表三视图 + 完整筛选排序
- [ ] 详情页:知识点关联区 + AI 区可折叠 + 学习记录时间线
- [ ] 复习中心:三模式 + 闭环刷新 + 7 天统计
- [ ] 首页:统一行动面板 + 知识树快照 + 7 天趋势
- [ ] 组卷:4 种方式 + 参数 + 预览
- [ ] 导出工作台:Word/图片格式 + 多入口 + 桌面端 PDF 公式渲染 + 组卷导出模式
- [ ] 设置:学习设置 + 知识树管理 + 关于 + 状态聚合
- [ ] `flutter analyze`、`flutter test`、构建检查全部通过

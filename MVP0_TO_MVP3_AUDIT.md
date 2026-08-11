# MVP-0 ～ MVP-3 审计报告

**审计时间**：2026-07-18
**方式**：源码与数据流审阅、Provider/启动覆盖检查、数据库/存储检查、测试资产盘点、`git diff --check`。
**限制**：当前 iSH 环境无 Flutter/Dart，未能执行 `flutter analyze` 和 `flutter test`；本报告不会将静态检查等同于运行通过。

## 总览

| 阶段 | 审计结论 | 发布状态 |
|---|---|---|
| MVP-0 基础主链路 | 拍照/分析/保存/浏览/练习的代码入口齐全；需 Flutter 真机回归 | 有条件可验收 |
| MVP-1 数据与安全 | API Key 安全存储已接入；备份恢复可用；历史数据迁移和日志库统一未完成 | **不建议直接向历史用户发布** |
| MVP-2 间隔复习 | 三档调度、到期查询、计划 UI 与兼容持久化已接入 | 待自动化/真机验收 |
| MVP-3 学习反馈 | L1–L4 代码范围收口，筛选/来源/收藏/计划/专项入口已具备 | 待 Flutter 验收 |

## 本轮修复

1. **Drift AI 配置编译错误**：安全存储重构中漏读 `ai_model`，但后续仍引用 `model`；已恢复读取。
2. **上次复习时间丢失**：Drift 表没有独立列，读取时被置空；已通过内部持久化标记 `__system_last_reviewed_at:<ISO>` 保存并恢复，新增 Drift 回归断言。
3. **详情页标签窄屏溢出**：新增来源标签后 `Row` 可能溢出；已改为 `Wrap`。
4. **进度条 Flutter 兼容性**：移除旧 Flutter 可能不支持的 `LinearProgressIndicator.borderRadius`。
5. **数据库静默降级风险**：数据库目录异常时原逻辑会切到内存 SQLite，用户可能以为数据已保存；已取消该静默降级，异常会显式暴露。
6. **SharedPreferences 损坏误判为空题库**：原实现解析失败直接返回空列表；已改为抛出 `FormatException`，避免覆盖/清空风险。

## MVP-0：基础主链路

### 已检查

- `main.dart` 生产入口覆盖 `QuestionRepository` 为 Drift；拍照、OCR、AI 分析、确认保存、错题详情、练习与路由均有入口。
- CI 已配置 `flutter pub get`、`flutter analyze`、`flutter test` 和 Android 构建。

### 风险/待验收

- 无 Flutter 运行环境，无法验证相机权限、图片裁剪、WebView 数学渲染、实际模型请求与 Android/iOS 构建。
- `AppDatabase` 目录初始化失败现在会显式失败而非丢数据；后续建议加入启动错误页和可导出诊断信息。

## MVP-1：数据可靠性与安全

### 已检查

- SharedPreferences 与 Drift 配置路径均将 API Key 迁移至 `flutter_secure_storage`。
- JSON 备份有 schema version、题目数据、Base64 图片附件、SHA-256 校验、旧格式兼容与 ID 去重。
- 收藏、来源、错因、上次复习时间以内部标记跨现有 SQLite/JSON 链路持久化。

### 阻断风险

1. **缺少 SharedPreferences → Drift 历史题库迁移**：正式 `main.dart` 已强制使用 Drift，但旧版题库 key `questions_list` 没有迁移代码。历史用户升级后可能看不到旧题库。
2. **复习日志仍在 SharedPreferences**：生产题库在 Drift，但 `ReviewLogRepository` 仍使用 `SharedPrefsReviewLogRepository`；Drift 的 `review_logs` 表未接入且 schema 与领域日志不一致。
3. **备份不含复习日志**：JSON 目前恢复题目和附件，不恢复完成率/连续学习所依赖的 ReviewLog。
4. **Base64 备份没有容量策略**：大量原图会令 JSON 文件与内存占用大幅增长；需要文件大小预估、单图上限、压缩或 ZIP 流式方案。

## MVP-2：间隔复习

### 已检查

- `forgot/hard/easy` 对应 1 小时、1/3 天、3/7/14/30 天调度。
- 首页、复习页、提醒统计统一调用 `ReviewScheduleService.isDue()`。
- 旧“已掌握”且无计划的题保持完成；其他旧题立即进入队列。
- `lastReviewedAt`、收藏等未独立建列的数据已兼容持久化。

### 风险/待验收

- 本地通知目前仅支持权限请求和应用内手动即时提醒；没有可靠的“每日后台查询到期题后再通知”机制。
- ReviewLog 与题库分属不同存储，清理/备份/迁移一致性不足。
- 调度是 MVP 固定策略，不是 FSRS；不应宣称自适应记忆算法。

## MVP-3：可用性与学习反馈

### 已检查

- L1：错因编辑、首页 Top 3、筛选。
- L2：来源编辑/动态筛选、收藏、到期、近 7/30 天、排序与全量重置。
- L3：今日计划、固定估时、完成率、连续学习。
- L4：知识点筛选结果可进入关联题的已生成练习。

### 风险/待验收

- 来源/错因/收藏/上次复习时间暂存在 `tags` 内部标记，后续 Drift schema 升级必须无损迁移。
- 专项练习只选择已有练习；未实现跨题合卷与缺题时自动生成。
- “全部”筛选、动态来源 chips、长标签的组合交互尚需窄屏真机验证。

## 必须执行的验收

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

建议真机覆盖：首次 API Key 迁移、旧题库升级、备份大图导入、复习时间跨重启、通知权限、窄屏标签/筛选组合、练习作答回写。

## 发布建议

- **新用户测试包**：可以进入 Flutter CI/真机验收。
- **历史用户正式升级**：先实现并验证 SharedPreferences → Drift 题库与复习日志迁移，且把复习日志纳入备份恢复；否则不建议发布。

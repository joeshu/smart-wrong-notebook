# 商业化视觉批次 0 差异记录

## 当前实现已经具备

- `AppColors`、`AppGradients`、`AppShadows` 语义颜色与阴影令牌
- `AppSpace`、`AppRadius`、`AppBreakpoints`、`AppContentWidth` 基础布局令牌
- `AppTextStyle` 字阶和字重层级
- `AppVisualStyle` 支持 academic / paper / aurora / forest 四套主题
- 首页已经具备 Hero、今日行动、统计、最近错题、趋势等模块
- 录题链路已经具备框选、预览、质量检测、放弃/重拍保护

## 当前与商业化目标的主要差距

1. 首页模块较多，首屏主线仍被统计、流程条和多个内容区块分散。
2. 首页已有 Hero 与行动卡，但需要收敛为“一个首要 CTA + 两个快捷入口”。
3. 四套视觉风格能力较完整，但品牌默认需要从“多风格展示”收敛到一套主品牌体验。
4. 设计稿使用 24/20/18 圆角和更明确的 Surface 层级，代码中仍有部分全局 16/20 混用。
5. 首页测试覆盖 Provider/功能较多，缺少针对主 CTA 优先级和窄屏布局的行为验收。
6. 设计资产尚未纳入 Git 提交。

## 实施约束

- 不在批次 1 重写 Provider、数据库和路由。
- 优先改共享令牌和首页展示层。
- 每批只改一个主链路，保持 CI 可诊断。
- 不用 `continue-on-error`、跳过测试或截图字符串断言掩盖回归。

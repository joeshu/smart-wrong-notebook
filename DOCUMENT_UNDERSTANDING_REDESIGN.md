# 文档理解重构蓝图：PaddleOCR / MinerU 不只切题框

## 已确认的问题
当前 `DocumentLayoutService` 只返回 `QuestionRegion`，导致 PaddleOCR 与 MinerU 的文字、公式、表格等文档理解结果在候选题框阶段被丢弃；用户只能感觉到“画了框”，看不到服务价值。

## 产品目标
一次整页试卷导入应产生可确认的 **文档理解结果**：

- 题目边界、题号、题型/多栏顺序；
- 每道题的 OCR 文本；
- 公式的 LaTex/Markdown 表示及置信提示；
- 表格、图形、选项等结构块；
- 实际执行服务、阶段、耗时、降级与失败原因；
- 用户可逐题编辑、接受、忽略或放弃整个批次。

PaddleOCR 和 MinerU 负责“读懂整页文档”；普通 AI 分析模型负责“错因、知识点、讲解和练习生成”。两者不得混淆。

## 本轮先落地

1. `QuestionRegion` 已可携带 `recognizedText` 与 `contentFormatHint`。
2. MinerU 按题号聚合块时会保留该题完整文字/公式 Markdown。
3. PaddleOCR 对返回块保留可用文本；后续需升级为按题号聚合而非单块候选。
4. 用户确认裁切后，文字/公式格式会进入 `QuestionRecord`，分析页不再从空文本重新开始。
5. 结果页保存实际切题服务标签，识别面板显示“已提取文字/公式”的数量。

## 下一开发切片

### D1：统一文档理解模型
将 `LayoutDetectionResult` 升级为 `DocumentUnderstandingResult`：

```dart
class RecognizedQuestion {
  String id;
  Rect normalizedRect;
  String? number;
  String text;                 // Markdown + LaTex
  QuestionContentFormat format;
  List<DocumentBlock> blocks;  // text/formula/table/image/option
  double confidence;
  List<String> warnings;
}
```

保留旧 `regions` 兼容字段，逐步迁移调用方。

### D2：可见的逐题确认页
整页框选界面增加底部题目列表：每题展示题号、文字前两行、公式/表格标记、置信度。点击可编辑文字；接受/忽略独立控制。用户确认后才生成题图与草稿。

### D3：PaddleOCR PP-StructureV3 适配
解析 PP-StructureV3 的文本行、公式、表格与阅读顺序；以题号开头作为分组锚点，形成完整 `RecognizedQuestion`，而不是把每个文档块当作题框。

### D4：MinerU VLM 适配
使用 `content_list.json` / `middle.json` 的 Markdown 与公式块，按题号和阅读顺序聚合；保留表格 Markdown、图像引用和公式错误提示。

### D5：取消与草稿策略
- 分析结果可“放弃并删除”；已实现。
- 逐题确认页支持“忽略此题”，不会入库也不会再分析。
- 整个导入批次支持“取消并清理所有临时裁剪图”。

## 验收标准

1. 导入一份含 3 道数学题、公式和表格的试卷，用户能看到每题文字预览与公式标记。
2. 页面明确显示 `PaddleOCR PP-StructureV3` 或 `MinerU VLM`、耗时和候选数。
3. 用户修改识别文本后，后续 AI 分析使用修改后的文本。
4. 用户忽略/放弃题目后，题库、导入队列和临时图片均无残留。
5. 单题拍照流程明确只走普通 AI 模型，不冒充 PaddleOCR/MinerU。

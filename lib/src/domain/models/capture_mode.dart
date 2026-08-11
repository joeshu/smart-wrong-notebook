/// 录入模式：决定 AI 识别时如何处理图片中的印刷与手写内容。
///
/// - [printed]：只识别印刷题干，忽略手写批改痕迹、圈画、红叉等内容
/// - [handwritten]：忠实转录手写解答过程，包括错误步骤
/// - [mixed]：同时识别印刷题干和手写批注
enum CaptureMode {
  printed,
  handwritten,
  mixed,
}

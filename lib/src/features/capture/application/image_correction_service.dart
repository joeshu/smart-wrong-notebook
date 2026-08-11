import 'dart:io';

import 'package:smart_wrong_notebook/src/features/capture/application/correction_state.dart';
import 'package:smart_wrong_notebook/src/shared/utils/image_preprocessor.dart';

class ImageCorrectionService {
  CorrectionState rotate90(CorrectionState state) {
    return state.copyWith(quarterTurns: (state.quarterTurns + 1) % 4);
  }

  CorrectionState reset(CorrectionState state) {
    return state.copyWith(quarterTurns: 0);
  }

  /// 自动纠偏 / 预处理入口。
  ///
  /// 原实现为空 stub。现在改为读取 [CorrectionState.imagePath] 对应的
  /// 原图字节，调用 [preprocessForOcr] 在后台 isolate 内执行去噪 / 纠偏 /
  /// 二值化等预处理，并把结果写回同目录下的 `xxx_preprocessed.jpg`。
  ///
  /// 失败时（文件不存在、解码失败、isolate 异常）原样返回 [state]，
  /// 不影响后续流程。
  Future<CorrectionState> autoStraighten(CorrectionState state) async {
    final path = state.imagePath;
    if (path.isEmpty) return state;
    final file = File(path);
    if (!file.existsSync()) return state;
    try {
      final sourceBytes = await file.readAsBytes();
      if (sourceBytes.isEmpty) return state;
      final processed = await preprocessForOcr(sourceBytes);
      if (processed.isEmpty || identical(processed, sourceBytes)) {
        return state;
      }
      final outPath = _preprocessedPath(path);
      await File(outPath).writeAsBytes(processed, flush: true);
      // 这里仍返回原 state（imagePath 不变），调用方可以按需读取 outPath；
      // 保留 state 字段是为了向后兼容现有测试与 UI。
      return state;
    } catch (_) {
      return state;
    }
  }

  String _preprocessedPath(String original) {
    final dot = original.lastIndexOf('.');
    if (dot < 0) return '${original}_preprocessed.jpg';
    // 始终输出 JPEG，避免 PNG 体积过大
    return '${original.substring(0, dot)}_preprocessed.jpg';
  }
}

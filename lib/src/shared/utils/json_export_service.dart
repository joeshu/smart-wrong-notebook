import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/shared/utils/latex_normalizer.dart';

import 'export_content_options.dart';

/// 生成 JSON 格式的错题本导出。
///
/// 输出结构化 JSON：
/// ```
/// {
///   "appVersion": "1.0",
///   "exportedAt": "2025-01-01T00:00:00",
///   "questions": [...],
///   "reviewLogs": [...]
/// }
/// ```
///
/// 每个 question 用 [QuestionRecord.toJson] 序列化，不包含题图附件。
class JsonExportService {
  /// 应用版本号，写入 JSON 元信息。
  static const String appVersion = '1.0';

  /// 生成 JSON 文本。
  ///
  /// [contentOptions] 用于语义对齐 Phase 11-4 的扩展字段：
  /// - [ExportContentOptions.includeReviewHistory] 控制是否输出 reviewLogs
  ///   字段（默认 false；若同时传入 [includeReviewLogs]=true，后者兼容
  ///   旧行为，仍以 true 为准）。
  /// - [ExportContentOptions.includeOcrText] / [includeAiAnalysis] 控制
  ///   是否裁剪 question JSON 中的对应字段（默认 false=保留全部，与历史
  ///   行为一致；设为 true 时不裁剪——这两个开关在 JSON 中仅作占位语义，
  ///   因为 JSON 导出本身就是完整结构化的，不强制裁剪）。
  /// - [ExportContentOptions.includeKnowledgeTree] 由调用方预查并注入
  ///   [knowledgeTreePaths] 时生效，本服务负责挂到每条 question 上。
  ///
  /// [includeReviewLogs] 为兼容旧调用方保留，新调用方应使用 contentOptions。
  ///
  /// [reviewLogs] 由调用方预查的全量复习日志，仅在 includeReviewHistory
  /// 或 includeReviewLogs 为 true 时输出。
  ///
  /// [knowledgeTreePaths] 由调用方预查的"题目→知识点路径列表"映射，仅
  /// 在 contentOptions.includeKnowledgeTree 为 true 时挂到每条 question
  /// 的 `knowledgeTreePaths` 字段。
  Future<String> generateJson({
    required List<QuestionRecord> questions,
    ExportContentOptions? contentOptions,
    @Deprecated('Use contentOptions.includeReviewHistory')
    bool includeReviewLogs = false,
    List<ReviewLog>? reviewLogs,
    Map<String, List<String>>? knowledgeTreePaths,
  }) async {
    final options = contentOptions ?? const ExportContentOptions();
    final includeLogs = includeReviewLogs || options.includeReviewHistory;
    final data = <String, dynamic>{
      'appVersion': appVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'questionCount': questions.length,
      // 归一化字面量 \n（反斜杠+n 两字符，AI 输出残留）为真正换行，
      // 避免导入端或下游工具看到选项 ABCD 前的字面量 \n 文本。
      'questions': questions
          .map((q) {
            List<String>? paths;
            if (options.includeKnowledgeTree && knowledgeTreePaths != null) {
              paths = knowledgeTreePaths[q.id];
            }
            return _normalizeQuestionRecordJson(
              q.toJson(),
              knowledgeTreePaths: paths,
            );
          })
          .toList(growable: false),
    };
    if (includeLogs) {
      data['reviewLogs'] = (reviewLogs ?? const <ReviewLog>[])
          .map(_reviewLogToJson)
          .toList(growable: false);
    } else {
      data['reviewLogs'] = const <Map<String, dynamic>>[];
    }

    // 使用 prettyPrint 让导出文件可读，便于调试与二次加工。
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(data);
  }

  /// 把 [content] 写入 .json 文件并调起系统分享。
  Future<void> shareJson(String content, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/exports');
    if (!exportDir.existsSync()) {
      await exportDir.create(recursive: true);
    }
    final file = File('${exportDir.path}/$fileName');
    await file.writeAsString(content, flush: true, encoding: utf8);
    await Share.shareXFiles([XFile(file.path)]);
  }

  // ─────────────────────────────────────────────────────────────────────
  // 工具
  // ─────────────────────────────────────────────────────────────────────

  /// [ReviewLog] 没有自带 toJson，这里手动序列化。
  Map<String, dynamic> _reviewLogToJson(ReviewLog log) {
    return {
      'id': log.id,
      'questionRecordId': log.questionRecordId,
      'reviewedAt': log.reviewedAt.toIso8601String(),
      'result': log.result,
      'masteryAfter': log.masteryAfter.name,
    };
  }

  /// 归一化 [QuestionRecord.toJson] 输出中的文本字段，统一字面量 `\n` →
  /// 真正换行符。覆盖题干、AI 解析等所有字符串字段，确保 JSON 导出在
  /// 下游工具（Excel/Notion/再导入）中显示正常。
  ///
  /// [knowledgeTreePaths] 由调用方预查的"该题目→知识点树路径列表"，
  /// 非 null 时挂到返回 JSON 的 `knowledgeTreePaths` 字段。
  Map<String, dynamic> _normalizeQuestionRecordJson(
    Map<String, dynamic> json, {
    List<String>? knowledgeTreePaths,
  }) {
    const textFields = <String>{
      'extractedQuestionText',
      'normalizedQuestionText',
      'studentAnswer',
      'expectedAnswer',
      'reflectionNote',
    };
    final normalized = json.map((key, value) {
      if (textFields.contains(key) && value is String) {
        return MapEntry(key, LatexNormalizer.normalizeLiteralNewlines(value));
      }
      return MapEntry(key, value);
    });
    if (knowledgeTreePaths != null && knowledgeTreePaths.isNotEmpty) {
      normalized['knowledgeTreePaths'] =
          List<String>.unmodifiable(knowledgeTreePaths);
    }
    return normalized;
  }
}

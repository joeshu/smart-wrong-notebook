import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/shared/utils/latex_normalizer.dart';

import 'export_content_options.dart';
import 'worksheet_export_mode.dart';

/// 生成 Markdown 格式的错题本导出。
///
/// 输出结构：
/// - `# 错题本整理报告` + 元信息
/// - 按学科分一级标题 `## 数学`
/// - 每题一个 `### 题 N：题干前 30 字...`
/// - 题干用纯文本，[QuestionContentFormat.latexMixed] 时保留 `$...$` 语法
/// - 末尾统计：总题数、按学科分布、按掌握度分布
class MarkdownExportService {
  /// 生成 Markdown 文本，调用方负责后续分享或写文件。
  ///
  /// [reviewLogs] 当 [ExportContentOptions.includeReviewHistory] 为 true 时
  /// 用于输出每题的复习历史时间线，调用方应预查并按 [QuestionRecord.id]
  /// 索引传入；为 null 时即使开关打开也不会输出复习历史。
  ///
  /// [knowledgeTreePaths] 当 [ExportContentOptions.includeKnowledgeTree] 为
  /// true 时用于输出每题的知识点树面包屑路径，key 为 questionId，value 为
  /// 形如 `数学 > 代数 > 二次方程` 的路径字符串列表；为 null 时即使开关
  /// 打开也不会输出知识点路径。
  Future<String> generateMarkdown({
    required List<QuestionRecord> questions,
    required WorksheetExportMode mode,
    required ExportContentOptions contentOptions,
    String? studentName,
    String? className,
    List<ReviewLog>? reviewLogs,
    Map<String, List<String>>? knowledgeTreePaths,
  }) async {
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final buffer = StringBuffer();

    // 按 questionId 索引复习历史，避免每次循环重新过滤。
    final reviewLogsByQuestion = <String, List<ReviewLog>>{};
    if (reviewLogs != null) {
      for (final log in reviewLogs) {
        reviewLogsByQuestion
            .putIfAbsent(log.questionRecordId, () => [])
            .add(log);
      }
      for (final list in reviewLogsByQuestion.values) {
        list.sort((a, b) => a.reviewedAt.compareTo(b.reviewedAt));
      }
    }

    // ── 文件头 ──────────────────────────────────────────────────────────
    buffer.writeln('# 错题本整理报告');
    buffer.writeln();
    if (studentName != null && studentName.isNotEmpty) {
      buffer.writeln('- **学生姓名：** $studentName');
    }
    if (className != null && className.isNotEmpty) {
      buffer.writeln('- **班级：** $className');
    }
    buffer.writeln('- **导出日期：** $dateStr');
    buffer.writeln('- **题目总数：** ${questions.length} 道');
    buffer.writeln('- **导出模式：** ${mode.label}');
    buffer.writeln();

    // ── 按学科分组 ─────────────────────────────────────────────────────
    final grouped = <Subject, List<QuestionRecord>>{};
    for (final q in questions) {
      grouped.putIfAbsent(q.subject, () => []).add(q);
    }
    final sortedSubjects = grouped.keys.toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    int globalIndex = 0;
    for (final subject in sortedSubjects) {
      final list = grouped[subject]!;
      buffer.writeln('## ${subject.label}（${list.length} 题）');
      buffer.writeln();
      for (final q in list) {
        globalIndex++;
        _writeQuestion(buffer, globalIndex, q,
            mode: mode,
            contentOptions: contentOptions,
            reviewLogs: reviewLogsByQuestion[q.id],
            knowledgeTreePaths: knowledgeTreePaths?[q.id]);
      }
    }

    // ── 末尾统计 ──────────────────────────────────────────────────────
    _writeStatistics(buffer, questions, grouped);

    return buffer.toString();
  }

  /// 把 [content] 写入临时 .md 文件并调起系统分享。
  Future<void> shareMarkdown(String content, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/exports');
    if (!exportDir.existsSync()) {
      await exportDir.create(recursive: true);
    }
    final file = File('${exportDir.path}/$fileName');
    await file.writeAsString(content, flush: true);
    await Share.shareXFiles([XFile(file.path)]);
  }

  // ─────────────────────────────────────────────────────────────────────
  // 题目块
  // ─────────────────────────────────────────────────────────────────────

  void _writeQuestion(
    StringBuffer buffer,
    int index,
    QuestionRecord q, {
    required WorksheetExportMode mode,
    required ExportContentOptions contentOptions,
    List<ReviewLog>? reviewLogs,
    List<String>? knowledgeTreePaths,
  }) {
    final questionText = q.normalizedQuestionText.isNotEmpty
        ? q.normalizedQuestionText
        : q.extractedQuestionText;
    final preview = _takePreview(questionText, 30);
    buffer.writeln('### 题 $index：$preview');
    buffer.writeln();

    // 题干
    if (questionText.isNotEmpty) {
      buffer.writeln(_formatQuestionText(q, questionText));
      buffer.writeln();
    }

    // 题图
    if (contentOptions.includeImage && q.imagePath.isNotEmpty) {
      buffer.writeln('![题目](${q.imagePath})');
      buffer.writeln();
    }

    // Phase 11-4：OCR 识别原文（与用户校对后的题干对照，便于校对场景）。
    if (contentOptions.includeOcrText &&
        q.extractedQuestionText.isNotEmpty &&
        q.extractedQuestionText != q.normalizedQuestionText) {
      buffer.writeln('**OCR 原文：** ${q.extractedQuestionText}');
      buffer.writeln();
    }

    final analysis = q.analysisResult;
    if (analysis != null) {
      // 知识点（所有模式都输出，便于复习时定位）
      if (contentOptions.includeKnowledgePoints) {
        final kps = [...analysis.knowledgePoints, ...analysis.aiTags]
            .where((s) => s.isNotEmpty)
            .take(8)
            .toList();
        if (kps.isNotEmpty) {
          buffer.writeln('**知识点：** ${kps.join('、')}');
          buffer.writeln();
        }
      }

      // 错因
      if (contentOptions.includeMistakeReason &&
          analysis.mistakeReason.isNotEmpty) {
        buffer.writeln('**错因：** ${analysis.mistakeReason}');
        buffer.writeln();
      }

      // 正确答案：practice 不输出；answer/correction 输出
      if (contentOptions.includeCorrectAnswer &&
          mode != WorksheetExportMode.practice &&
          analysis.finalAnswer.isNotEmpty) {
        buffer.writeln('**正确答案：** ${analysis.finalAnswer}');
        buffer.writeln();
      }

      // 解题步骤：仅 correction 模式输出
      if (contentOptions.includeSolutionSteps &&
          mode == WorksheetExportMode.correction &&
          analysis.steps.isNotEmpty) {
        buffer.writeln('**解题步骤：**');
        buffer.writeln();
        for (var i = 0; i < analysis.steps.length; i++) {
          buffer.writeln('${i + 1}. ${analysis.steps[i]}');
        }
        buffer.writeln();
      }

      // 学习建议
      if (contentOptions.includeStudyAdvice &&
          analysis.studyAdvice.isNotEmpty) {
        buffer.writeln('**学习建议：** ${analysis.studyAdvice}');
        buffer.writeln();
      }
    }

    // Phase 11-4：完整 AI 分析原文（结构化 JSON 代码块）。
    // 与上面分段字段不同：本字段输出 AnalysisResult 完整序列化，
    // 便于离线复盘 AI 推理质量。
    if (contentOptions.includeAiAnalysis && q.analysisResult != null) {
      final json = q.analysisResult!.toJson();
      const encoder = JsonEncoder.withIndent('  ');
      buffer.writeln('**完整 AI 分析：**');
      buffer.writeln();
      buffer.writeln('```json');
      buffer.writeln(encoder.convert(json));
      buffer.writeln('```');
      buffer.writeln();
    }

    // 复习次数
    if (contentOptions.includeReviewCount && q.reviewCount > 0) {
      buffer.writeln('**复习次数：** ${q.reviewCount}');
      buffer.writeln();
    }

    // Phase 11-4：复习历史时间线（含每次复习日期、评分、掌握度）。
    // 与 includeReviewCount（仅次数）不同：本字段输出全部 ReviewLog。
    if (contentOptions.includeReviewHistory &&
        reviewLogs != null &&
        reviewLogs.isNotEmpty) {
      buffer.writeln('**复习历史：**');
      buffer.writeln();
      for (final log in reviewLogs) {
        final date = DateFormat('yyyy-MM-dd HH:mm').format(log.reviewedAt);
        buffer.writeln(
            '- $date · ${log.result} · ${_masteryLabel(log.masteryAfter)}');
      }
      buffer.writeln();
    }

    // 收藏标记
    if (contentOptions.includeFavoriteMark && q.isFavorite) {
      buffer.writeln('**收藏：** ★');
      buffer.writeln();
    }

    // 日期
    if (contentOptions.includeDates) {
      buffer.writeln(
          '**创建日期：** ${DateFormat('yyyy-MM-dd').format(q.createdAt)}');
      if (q.lastReviewedAt != null) {
        buffer.writeln(
            '**上次复习：** ${DateFormat('yyyy-MM-dd').format(q.lastReviewedAt!)}');
      }
      if (q.nextReviewAt != null) {
        buffer.writeln(
            '**下次复习：** ${DateFormat('yyyy-MM-dd').format(q.nextReviewAt!)}');
      }
      buffer.writeln();
    }

    // Phase 11-4：知识点树路径（形如 `数学 > 代数 > 二次方程`）。
    // 与 includeKnowledgePoints（仅名称）不同：本字段输出完整层级路径。
    if (contentOptions.includeKnowledgeTree &&
        knowledgeTreePaths != null &&
        knowledgeTreePaths.isNotEmpty) {
      buffer.writeln('**知识点树路径：**');
      buffer.writeln();
      for (final path in knowledgeTreePaths) {
        buffer.writeln('- $path');
      }
      buffer.writeln();
    }

    buffer.writeln('---');
    buffer.writeln();
  }

  void _writeStatistics(
    StringBuffer buffer,
    List<QuestionRecord> questions,
    Map<Subject, List<QuestionRecord>> grouped,
  ) {
    buffer.writeln('## 统计');
    buffer.writeln();
    buffer.writeln('- **总题数：** ${questions.length} 道');
    buffer.writeln();
    buffer.writeln('### 按学科分布');
    buffer.writeln();
    final sortedSubjects = grouped.keys.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    for (final subject in sortedSubjects) {
      buffer.writeln('- ${subject.label}：${grouped[subject]!.length} 道');
    }
    buffer.writeln();
    buffer.writeln('### 按掌握度分布');
    buffer.writeln();
    final masteryCount = <MasteryLevel, int>{
      for (final level in MasteryLevel.values) level: 0,
    };
    for (final q in questions) {
      masteryCount[q.masteryLevel] = masteryCount[q.masteryLevel]! + 1;
    }
    for (final level in MasteryLevel.values) {
      buffer.writeln('- ${_masteryLabel(level)}：${masteryCount[level]} 道');
    }
    buffer.writeln();
  }

  // ─────────────────────────────────────────────────────────────────────
  // 工具
  // ─────────────────────────────────────────────────────────────────────

  /// 取题干前 [length] 字作为标题预览，去除换行避免破坏 Markdown 标题。
  String _takePreview(String text, int length) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= length) return flat;
    return '${flat.substring(0, length)}…';
  }

  /// 题干文本输出，[QuestionContentFormat.latexMixed] 时保留 `$...$` 语法。
  ///
  /// 入口先归一化字面量 `\n`（反斜杠+n 两字符，AI 输出残留）为真正换行，
  /// 避免选项 ABCD 前出现字面量 `\n` 文本。
  String _formatQuestionText(QuestionRecord q, String text) {
    final normalized = LatexNormalizer.normalizeLiteralNewlines(text);
    if (q.contentFormat == QuestionContentFormat.latexMixed) {
      // 题干本身已带 `$...$`，原样输出。
      return normalized;
    }
    return normalized;
  }

  String _masteryLabel(MasteryLevel level) => switch (level) {
        MasteryLevel.newQuestion => '待学习',
        MasteryLevel.reviewing => '复习中',
        MasteryLevel.mastered => '已掌握',
      };
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_import_session.dart';

/// Keeps an unfinished worksheet import recoverable across app restarts.
class WorksheetImportRepository {
  static const _key = 'worksheet_import_session_v1';

  Future<WorksheetImportSession?> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final pages = (json['pages'] as List)
          .map((item) => QuestionRecord.fromJson(item as Map<String, dynamic>))
          .toList();
      // 跨进程兜底：上次运行时仍处于 processing/analyzing 的页面一定没成功完成
      // （App 被杀掉 / 进程被回收 / 用户从识别中退出后强杀）。
      // processing → failed（识别中断），analyzing → analysisFailed（OCR 已成功，
      // 仅 AI 中断）。让 UI 显示"失败可重试"而非无限"处理中"。
      final needsReset = pages.any((page) =>
          (page.contentStatus == ContentStatus.processing ||
              page.contentStatus == ContentStatus.analyzing) &&
          !page.isArchived);
      final normalizedPages = needsReset
          ? pages
              .map((page) {
                if (page.contentStatus == ContentStatus.processing) {
                  return page.copyWith(contentStatus: ContentStatus.failed);
                }
                if (page.contentStatus == ContentStatus.analyzing) {
                  return page.copyWith(
                      contentStatus: ContentStatus.analysisFailed,
                      lastAnalysisError: '分析被中断，请重试');
                }
                return page;
              })
              .toList()
          : pages;
      return WorksheetImportSession(
        id: json['id'] as String,
        pages: normalizedPages,
        sourcePageIds: ((json['sourcePageIds'] as List?) ?? const <Object>[])
            .map((item) => '$item')
            .toSet(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        processedSourcePageIds:
            ((json['processedSourcePageIds'] as List?) ?? const <Object>[])
                .map((item) => '$item')
                .toSet(),
        lastProcessedId: json['lastProcessedId'] as String?,
        autoAnalyze: json['autoAnalyze'] as bool? ?? false,
      );
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> save(WorksheetImportSession session) async {
    await (await SharedPreferences.getInstance()).setString(_key, jsonEncode({
      'id': session.id,
      'pages': session.pages.map((page) => page.toJson()).toList(),
      'sourcePageIds': session.sourcePageIds.toList(),
      'createdAt': session.createdAt.toIso8601String(),
      'processedSourcePageIds': session.processedSourcePageIds.toList(),
      'lastProcessedId': session.lastProcessedId,
      'autoAnalyze': session.autoAnalyze,
    }));
  }

  Future<void> clear() async {
    await (await SharedPreferences.getInstance()).remove(_key);
  }
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 单条导出历史记录（Phase 11-7）。
///
/// 记录每次导出的核心元数据，用于「最近导出」列表展示与重做。
/// 文件路径可能因 [HtmlExportService.cleanupExports] 清理而失效，
/// 因此「重新下载」应基于筛选条件重新生成而非复用旧文件（筛选条件
/// 序列化较重，本期暂不记录，留待后续迭代）。
class ExportHistoryEntry {
  const ExportHistoryEntry({
    required this.timestamp,
    required this.format,
    required this.template,
    required this.questionCount,
    required this.title,
    this.fileName,
  });

  /// 导出时间（毫秒时间戳）。
  final int timestamp;

  /// 导出格式标签（如 `PDF`、`Markdown`、`Anki`）。
  final String format;

  /// 模板标签（如 `错题报告`、`复习卡`）。
  final String template;

  /// 题目数量。
  final int questionCount;

  /// 导出标题。
  final String title;

  /// 生成的文件名（可能已失效，仅用于展示）。
  final String? fileName;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'timestamp': timestamp,
        'format': format,
        'template': template,
        'questionCount': questionCount,
        'title': title,
        'fileName': fileName,
      };

  factory ExportHistoryEntry.fromJson(Map<String, dynamic> json) {
    return ExportHistoryEntry(
      timestamp: json['timestamp'] as int? ?? 0,
      format: json['format'] as String? ?? '',
      template: json['template'] as String? ?? '',
      questionCount: json['questionCount'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      fileName: json['fileName'] as String?,
    );
  }
}

/// 导出历史服务：用 SharedPreferences 持久化最近 [maxEntries] 条导出记录。
///
/// Phase 11-7：导出工作台每次导出成功后调用 [add] 写入一条记录，
/// 数据管理页或工作台可调用 [list] 读取展示。
class ExportHistoryService {
  ExportHistoryService._();

  /// 最多保留的历史条数（FIFO，超出自动丢弃最旧的）。
  static const int maxEntries = 10;

  /// SharedPreferences 键。
  static const String _key = 'export_history_entries';

  /// 读取全部历史记录（按时间倒序，最新的在前）。
  static Future<List<ExportHistoryEntry>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key);
    if (raw == null || raw.isEmpty) return const <ExportHistoryEntry>[];
    final entries = <ExportHistoryEntry>[];
    for (final item in raw) {
      try {
        final json = jsonDecode(item) as Map<String, dynamic>;
        entries.add(ExportHistoryEntry.fromJson(json));
      } catch (_) {
        // 跳过损坏的条目。
      }
    }
    // 按时间戳倒序（最新在前）。
    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries;
  }

  /// 追加一条导出记录，超出 [maxEntries] 时丢弃最旧的。
  static Future<void> add(ExportHistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? <String>[];
    raw.add(jsonEncode(entry.toJson()));
    // 保留最后 maxEntries 条（最旧的在列表头部，被截断）。
    final trimmed = raw.length > maxEntries
        ? raw.sublist(raw.length - maxEntries)
        : raw;
    await prefs.setStringList(_key, trimmed);
  }

  /// 删除与文件对应的历史记录；旧记录仅按时间、格式和文件名尽力匹配。
  static Future<void> remove(ExportHistoryEntry target) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await list();
    final remaining = entries.where((entry) {
      return !(entry.timestamp == target.timestamp &&
          entry.format == target.format &&
          entry.fileName == target.fileName);
    }).toList(growable: false);
    await prefs.setStringList(
      _key,
      remaining.map((entry) => jsonEncode(entry.toJson())).toList(),
    );
  }

  /// 更新历史记录中的文件名（用于数据管理页重命名）。
  static Future<void> renameFile(String oldName, String newName) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await list();
    final updated = entries.map((entry) {
      return entry.fileName == oldName
          ? ExportHistoryEntry(
              timestamp: entry.timestamp,
              format: entry.format,
              template: entry.template,
              questionCount: entry.questionCount,
              title: entry.title,
              fileName: newName,
            )
          : entry;
    }).toList(growable: false);
    await prefs.setStringList(
      _key,
      updated.map((entry) => jsonEncode(entry.toJson())).toList(),
    );
  }
  /// 删除全部历史记录。
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

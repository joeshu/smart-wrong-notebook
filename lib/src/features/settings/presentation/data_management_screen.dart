import 'dart:convert';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/data/files/backup_attachment_integrity.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/pending_knowledge_point_mapping.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_knowledge_link.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_draft.dart';
import 'package:smart_wrong_notebook/src/domain/services/ai_response_diagnostics_retention_service.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/shared/utils/app_share_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_history_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_options_dialog.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/pdf_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/single_text_field_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

class DataManagementScreen extends ConsumerStatefulWidget {
  const DataManagementScreen({super.key});

  @override
  ConsumerState<DataManagementScreen> createState() =>
      _DataManagementScreenState();
}

class _DataManagementScreenState extends ConsumerState<DataManagementScreen> {
  static const _backupSchemaVersion = 6;
  static const _lastImportKey = 'backup_last_import_v1';
  bool _aiDiagnosticsRawEnabled = false;
  int _aiDiagnosticsRetentionDays =
      AiAnalysisService.defaultDiagnosticsRawRetentionDays;
  bool _aiDiagnosticsBusy = false;

  int _sanitizeAiDiagnosticsRetentionDays(int? days) {
    final value = days ?? AiAnalysisService.defaultDiagnosticsRawRetentionDays;
    if (value < 1) return 1;
    if (value > 30) return 30;
    return value;
  }
  /// 加密备份文件魔数 "WNB1"，用于识别加密格式。
  static final _encryptedMagic = <int>[0x57, 0x4E, 0x42, 0x31];
  _ImportUndo? _lastImport;
  String? _lastBackupLabel;
  bool _encryptBackup = false;
  final TextEditingController _backupPasswordController =
      TextEditingController();
  Future<List<File>>? _exportFilesFuture;

  @override
  void initState() {
    super.initState();
    _loadLastImport();
    _loadAiDiagnosticsSettings();
    // 初始先用空列表占位，避免在测试环境（path_provider 未注册）中
    // CircularProgressIndicator 一直转导致 pumpAndSettle 超时；
    // 首帧后再异步加载真实文件列表。
    _exportFilesFuture = Future.value(const <File>[]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _expireAiDiagnosticsRawResponsesSilently();
      _reloadExports();
    });
  }

  @override
  void dispose() {
    _backupPasswordController.dispose();
    super.dispose();
  }

  /// 从统一的持久化导出记录解析文件；文件系统只负责确认文件是否存在。
  Future<List<File>> _loadExportFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final exportDir = Directory('${dir.path}/exports');
      final entries = await ExportHistoryService.list();
      final files = <File>[];
      for (final entry in entries) {
        final fileName = entry.fileName;
        if (fileName == null || fileName.isEmpty) continue;
        final file = File('${exportDir.path}/$fileName');
        if (await file.exists()) files.add(file);
      }
      return files;
    } catch (_) {
      return const <File>[];
    }
  }

  /// 刷新导出历史列表（分享/删除/重命名后调用）。
  Future<void> _reloadExports() async {
    final files = await _loadExportFiles();
    if (!mounted) return;
    setState(() => _exportFilesFuture = Future.value(files));
  }

  Future<void> _loadAiDiagnosticsSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _aiDiagnosticsRawEnabled =
            prefs.getBool(AiAnalysisService.diagnosticsRawResponseEnabledKey) ??
                false;
        _aiDiagnosticsRetentionDays = _sanitizeAiDiagnosticsRetentionDays(
          prefs.getInt(AiAnalysisService.diagnosticsRawRetentionDaysKey),
        );
      });
    } catch (_) {
      // 测试环境或 SharedPreferences 不可用时沿用默认值。
    }
  }

  Future<void> _setAiDiagnosticsRawEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        AiAnalysisService.diagnosticsRawResponseEnabledKey,
        enabled,
      );
      if (!mounted) return;
      setState(() => _aiDiagnosticsRawEnabled = enabled);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存设置失败: $e')),
      );
    }
  }

  Future<void> _setAiDiagnosticsRetentionDays(int days) async {
    final sanitized = _sanitizeAiDiagnosticsRetentionDays(days);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        AiAnalysisService.diagnosticsRawRetentionDaysKey,
        sanitized,
      );
      if (!mounted) return;
      setState(() => _aiDiagnosticsRetentionDays = sanitized);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存保留天数失败: $e')),
      );
    }
  }

  Future<int> _rewriteQuestionsWithMapper(
    List<QuestionRecord> questions,
    QuestionRecord Function(QuestionRecord record) mapper,
  ) async {
    final repository = ref.read(questionRepositoryProvider);
    var changedCount = 0;
    for (final question in questions) {
      final updated = mapper(question);
      if (identical(updated, question)) continue;
      await repository.update(updated);
      changedCount++;
    }
    return changedCount;
  }

  Future<void> _expireAiDiagnosticsRawResponsesSilently() async {
    try {
      final questions = await ref.read(questionRepositoryProvider).listAll();
      final retention = const AiResponseDiagnosticsRetentionService();
      final changedCount = await _rewriteQuestionsWithMapper(
        questions,
        (record) => retention.expireRawResponses(record),
      );
      if (changedCount > 0) {
        ref.invalidate(questionListProvider);
      }
    } catch (_) {
      // 静默失败，避免影响数据管理页打开。
    }
  }

  Future<void> _clearAiDiagnosticsRawResponses(
    BuildContext context,
    List<QuestionRecord> questions,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理 AI 原始响应'),
        content: const Text(
          '将删除已保存的 AI 原始响应内容，仅保留长度、指纹、修复策略和采集时间等安全摘要。此操作不可恢复。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('立即清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _aiDiagnosticsBusy = true);
    try {
      final retention = const AiResponseDiagnosticsRetentionService();
      final changedCount = await _rewriteQuestionsWithMapper(
        questions,
        retention.stripRawResponses,
      );
      ref.invalidate(questionListProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            changedCount == 0
                ? '没有检测到需要清理的 AI 原始响应'
                : '已清理 $changedCount 道题中的 AI 原始响应',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清理失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _aiDiagnosticsBusy = false);
      }
    }
  }

  Future<void> _shareExportFile(BuildContext context, File file) async {
    await AppShareService.shareFile(context, file.path);
  }

  /// 删除导出历史中的文件（带二次确认）。
  Future<void> _deleteExportFile(BuildContext context, File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除导出文件'),
        content: Text('确定要删除「${file.uri.pathSegments.last}」吗？此操作不可恢复。'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await file.delete();
      final history = await ExportHistoryService.list();
      for (final entry in history) {
        if (entry.fileName == file.uri.pathSegments.last) {
          await ExportHistoryService.remove(entry);
        }
      }
      await _reloadExports();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已删除导出文件')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  /// 重命名导出历史中的文件。
  Future<void> _renameExportFile(BuildContext context, File file) async {
    final newName = await showSingleTextFieldDialog(
      context: context,
      title: '重命名导出文件',
      initialText: file.uri.pathSegments.last,
      autofocus: true,
      labelText: '新文件名',
    );
    if (newName == null || newName.isEmpty) return;
    final safeName = newName.contains('.')
        ? newName
        : '$newName.${file.uri.pathSegments.last.split('.').last}';
    final newPath = '${file.parent.path}/$safeName';
    if (newPath == file.path) return;
    try {
      await file.rename(newPath);
      await ExportHistoryService.renameFile(
        file.uri.pathSegments.last,
        newPath.split('/').last,
      );
      await _reloadExports();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已重命名')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重命名失败: $e')),
        );
      }
    }
  }

  /// 用 mailto: 调起邮件客户端（无法直接附带文件，仅作为提示入口）。
  Future<void> _emailExportFile(BuildContext context, File file) async {
    final filename = file.uri.pathSegments.last;
    final uri = Uri(
      scheme: 'mailto',
      queryParameters: <String, dynamic>{
        'subject': filename,
        'body': '请查收附件：$filename（请在系统分享中手动添加此文件作为附件）',
      },
    );
    try {
      if (!await launchUrl(uri)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未找到邮件客户端，请改用「重新分享」')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('调起邮件失败: $e')),
        );
      }
    }
  }

  // --- 加密备份（基于 SHA-256 派生密钥流的 XOR 加密） ---

  /// 由密码 + salt 派生指定长度的密钥流（SHA-256 + counter，类 HKDF 展开）。
  Uint8List _deriveKeyStream(String password, Uint8List salt, int length) {
    final out = Uint8List(length);
    var offset = 0;
    var counter = 0;
    while (offset < length) {
      final counterBytes = Uint8List(4)
        ..buffer.asByteData().setInt32(0, counter, Endian.big);
      final hash = sha256
          .convert(Uint8List.fromList(
              [...utf8.encode(password), ...salt, ...counterBytes]))
          .bytes;
      final take = math.min(hash.length, length - offset);
      out.setRange(offset, offset + take, hash);
      offset += take;
      counter++;
    }
    return out;
  }

  /// 加密：magic(4) + saltLen(4) + salt(16) + cipher(XOR)。
  Uint8List _encryptBytes(Uint8List plain, String password) {
    final random = math.Random.secure();
    final salt = Uint8List.fromList(
        List<int>.generate(16, (_) => random.nextInt(256)));
    final keyStream = _deriveKeyStream(password, salt, plain.length);
    final cipher = Uint8List(plain.length);
    for (var i = 0; i < plain.length; i++) {
      cipher[i] = plain[i] ^ keyStream[i];
    }
    final out = BytesBuilder();
    out.add(_encryptedMagic);
    out.add(Uint8List(4)..buffer.asByteData().setInt32(0, salt.length, Endian.big));
    out.add(salt);
    out.add(cipher);
    return out.toBytes();
  }

  /// 解密：返回明文；密码错误或格式损坏返回 null。
  Uint8List? _decryptBytes(Uint8List raw, String password) {
    if (!_isEncryptedBytes(raw)) return null;
    final data = ByteData.sublistView(raw);
    final saltLen = data.getInt32(4, Endian.big);
    if (saltLen <= 0 || 8 + saltLen > raw.length) return null;
    final salt = Uint8List.sublistView(raw, 8, 8 + saltLen);
    final cipher = Uint8List.sublistView(raw, 8 + saltLen);
    final keyStream = _deriveKeyStream(password, salt, cipher.length);
    final plain = Uint8List(cipher.length);
    for (var i = 0; i < cipher.length; i++) {
      plain[i] = cipher[i] ^ keyStream[i];
    }
    return plain;
  }

  /// 是否为加密备份（魔数 "WNB1"）。
  bool _isEncryptedBytes(Uint8List raw) {
    if (raw.length < 8) return false;
    for (var i = 0; i < _encryptedMagic.length; i++) {
      if (raw[i] != _encryptedMagic[i]) return false;
    }
    return true;
  }

  /// 弹出密码输入框；返回 null 表示用户取消。
  Future<String?> _promptForPassword(BuildContext context) async {
    return showSingleTextFieldDialog(
      context: context,
      title: '输入密码',
      autofocus: true,
      obscureText: true,
      barrierDismissible: false,
      labelText: '备份密码',
      confirmText: '确定',
    );
  }

  Future<void> _loadLastImport() async {
    try {
      final raw =
          (await SharedPreferences.getInstance()).getString(_lastImportKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (mounted) setState(() => _lastImport = _ImportUndo.fromJson(decoded));
    } catch (_) {
      // 测试环境或 SharedPreferences 不可用时静默跳过。
    }
  }

  Future<void> _persistLastImport(_ImportUndo undo) async {
    await (await SharedPreferences.getInstance())
        .setString(_lastImportKey, jsonEncode(undo.toJson()));
  }

  @override
  Widget build(BuildContext context) {
    final questionsAsync = ref.watch(questionListProvider);
    final reviewLogsAsync = ref.watch(reviewLogListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('数据管理'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: questionsAsync.when(
        data: (questions) => ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            FilledButton.icon(
              onPressed: () => context.go('/settings/export-workbench'),
              icon: const Icon(CupertinoIcons.arrow_up_doc),
              label: const Text('打开导出工作台'),
            ),
            const SizedBox(height: 12),
            _BackupStatusCard(
              questionCount: questions.length,
              lastBackupLabel: _lastBackupLabel,
              onBackup: questions.isEmpty
                  ? null
                  : () => _exportQuestions(context, ref, questions),
              onRestore: () => _importQuestions(context, ref),
              onUndo: _lastImport == null
                  ? null
                  : () => _undoLastImport(context, ref),
              encryptBackup: _encryptBackup,
              onEncryptToggle: (v) {
                if (!v) _backupPasswordController.clear();
                setState(() => _encryptBackup = v);
              },
              passwordController: _backupPasswordController,
            ),
            const SizedBox(height: 12),
            _DataCard(
              icon: CupertinoIcons.chart_bar_alt_fill,
              iconColor: const Color(0xFF6366F1),
              title: '生成本周学情',
              subtitle: '聚合本周错题与复习数据，一键生成可预览 / 导出 / 分享的学情周报',
              onTap: () => context.go('/settings/weekly-report'),
            ),
            const SizedBox(height: 8),
            _DataCard(
              icon: CupertinoIcons.bolt_horizontal_circle,
              iconColor: const Color(0xFF0EA5E9),
              title: '学科能力雷达图',
              subtitle: '按学科掌握程度生成雷达图，定位薄弱学科',
              onTap: () => context.go('/settings/subject-radar'),
            ),
            const SizedBox(height: 8),
            _DataCard(
              icon: CupertinoIcons.square_grid_2x2,
              iconColor: const Color(0xFFEC4899),
              title: '错因趋势热力图',
              subtitle: '近 30 天错因分布热力图，发现高频错因与趋势',
              onTap: () => context.go('/settings/mistake-trend'),
            ),
            const SizedBox(height: 8),
            const Text('删除所有错题和复习记录，不可恢复',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            const SizedBox(height: 8),
            _DataCard(
              icon: CupertinoIcons.trash,
              iconColor: AppColors.danger,
              title: '清空所有数据',
              titleColor: AppColors.danger,
              subtitle: '删除所有错题和复习记录；建议先创建完整备份',
              onTap: () => _confirmClearAll(context, ref, questions.length),
            ),
            const SizedBox(height: 20),
            const _SectionTitle('存储概览'),
            const SizedBox(height: 8),
            _DataCard(
              icon: CupertinoIcons.tray,
              title: '题库总量',
              trailing: '${questions.length} 题',
            ),
            const SizedBox(height: 8),
            _DataCard(
              icon: CupertinoIcons.clock,
              title: '复习记录总量',
              trailingWidget: reviewLogsAsync.when(
                data: (logs) =>
                    Text('${logs.length} 条', style: _trailingStyle(context)),
                loading: () => const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                error: (_, __) =>
                    Text('加载失败', style: _subtitleStyle(context)),
              ),
            ),
            const SizedBox(height: 20),
            // Phase 12-2：缓存清理入口（独立于"清空所有数据"）。
            const _SectionTitle('缓存清理'),
            const SizedBox(height: 8),
            _DataCard(
              icon: CupertinoIcons.trash_circle,
              iconColor: const Color(0xFF0EA5E9),
              title: '清理临时预览文件',
              subtitle: '删除系统临时目录中超过 7 天的 HTML / PDF 预览文件',
              onTap: () => _cleanTempPreviews(context),
            ),
            const SizedBox(height: 8),
            _DataCard(
              icon: CupertinoIcons.photo,
              iconColor: const Color(0xFFEC4899),
              title: '清理孤立题图',
              subtitle: '扫描题图目录，删除不再被任何错题引用的图片文件',
              onTap: questions.isEmpty
                  ? null
                  : () => _cleanOrphanImages(context, ref, questions),
            ),
            const SizedBox(height: 20),
            const _SectionTitle('AI 诊断数据'),
            const SizedBox(height: 8),
            _DataCard(
              icon: CupertinoIcons.shield,
              iconColor: const Color(0xFF6366F1),
              title: '保存原始 AI 响应用于诊断',
              subtitle: _aiDiagnosticsRawEnabled
                  ? '已开启；仅在问题排查期间短期保留原始响应，建议完成诊断后及时关闭'
                  : '默认关闭；仅保存长度、指纹、修复策略与采集时间等安全摘要',
              trailingWidget: Switch.adaptive(
                value: _aiDiagnosticsRawEnabled,
                onChanged: _aiDiagnosticsBusy
                    ? null
                    : (value) => _setAiDiagnosticsRawEnabled(value),
              ),
            ),
            const SizedBox(height: 8),
            _DataCard(
              icon: CupertinoIcons.time,
              iconColor: const Color(0xFF0EA5E9),
              title: '原始响应保留天数',
              subtitle: '仅在开启原始响应留存时生效；超期会在打开本页时自动清理',
              trailing: '$_aiDiagnosticsRetentionDays 天',
              onTap: _aiDiagnosticsBusy
                  ? null
                  : () => _showAiDiagnosticsRetentionPicker(context),
            ),
            const SizedBox(height: 8),
            _DataCard(
              icon: CupertinoIcons.delete,
              iconColor: AppColors.danger,
              title: '清理 AI 原始响应',
              subtitle: '删除所有已保存的 raw response，仅保留安全摘要指纹',
              onTap: _aiDiagnosticsBusy
                  ? null
                  : () => _clearAiDiagnosticsRawResponses(context, questions),
            ),
            const SizedBox(height: 20),
          ],
        ),
        loading: () => const AppListSkeleton(),
        error: (e, _) => AppErrorState(
          error: e,
          onRetry: () => ref.invalidate(questionListProvider),
        ),
      ),
    );
  }

  Future<void> _showAiDiagnosticsRetentionPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const ListTile(
              title: Text('选择原始响应保留天数'),
              subtitle: Text('范围 1–30 天，默认 7 天'),
            ),
            for (final days in <int>[1, 3, 7, 14, 30])
              ListTile(
                title: Text('$days 天'),
                trailing: days == _aiDiagnosticsRetentionDays
                    ? const Icon(CupertinoIcons.check_mark)
                    : null,
                onTap: () => Navigator.of(ctx).pop(days),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await _setAiDiagnosticsRetentionDays(selected);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已将 AI 原始响应保留期设置为 $selected 天')),
    );
  }

  Future<void> _exportWithOptions(
    BuildContext context,
    List<QuestionRecord> questions, {
    required bool isPdf,
  }) async {
    final options = await showExportOptionsDialog(context, questions);
    if (options == null || !context.mounted) return;
    final watermark = options.studentInfo?.watermark;
    if (isPdf) {
      await PdfExportService.sharePdf(
        context,
        options.filtered,
        mode: options.mode,
        studentInfo: options.studentInfo,
        watermark: watermark,
        layoutOptions: options.layoutOptions,
      );
    } else {
      await HtmlExportService.shareHtml(
        context,
        options.filtered,
        mode: options.mode,
        studentInfo: options.studentInfo,
        watermark: watermark,
        templateType: options.templateType,
        layoutOptions: options.layoutOptions,
      );
    }
    // 分享完成后刷新导出历史列表（新生成的文件会出现）。
    await _reloadExports();
  }

  // --- 完整备份（.wnb zip 包：题目 + 复习记录 + 题图附件） ---

  Future<void> _exportQuestions(
    BuildContext context,
    WidgetRef ref,
    List<QuestionRecord> questions,
  ) async {
    final reviewLogs = await ref.read(reviewLogRepositoryProvider).listAll();
    final approved =
        await _showBackupPreview(context, questions, reviewLogs.length);
    if (approved != true || !context.mounted) return;
    // 启用加密时强制要求密码非空。
    final password = _encryptBackup ? _backupPasswordController.text : '';
    if (_encryptBackup && password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已勾选加密备份，请先填写密码')),
      );
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final exportDir = Directory('${dir.path}/exports');
      await exportDir.create(recursive: true);
      final now = DateTime.now();
      final attachments = await _buildAttachmentBackup(questions);
      // Phase 12-2（schema v6）：备份中包含知识点树和组卷草稿，便于
      // 跨设备恢复完整学习资料。两者都来自 SharedPreferences，向后兼容。
      final knowledgePoints =
          await ref.read(knowledgePointRepositoryProvider).loadAll();
      final knowledgeLinks =
          await ref.read(questionKnowledgeLinkRepositoryProvider).allLinks();
      final pendingKnowledgeMappings = await ref
          .read(pendingKnowledgePointMappingRepositoryProvider)
          .allMappings();
      final worksheetDrafts =
          await ref.read(worksheetDraftRepositoryProvider).loadAll();
      final attachmentIndex = attachments
          .map((item) => <String, dynamic>{
                'questionId': item['questionId'],
                'fileName': item['fileName'],
                'sha256': item['sha256'],
                'byteSize':
                    base64Decode(item['contentBase64'] as String).length,
              })
          .toList();
      final manifest = <String, dynamic>{
        'format': 'smart-wrong-notebook-backup',
        'schemaVersion': _backupSchemaVersion,
        'generatedAt': now.toIso8601String(),
        'questionCount': questions.length,
        'reviewLogCount': reviewLogs.length,
        'attachmentCount': attachments.length,
        'knowledgePointCount': knowledgePoints.length,
        'knowledgeLinkCount': knowledgeLinks.length,
        'pendingKnowledgeMappingCount': pendingKnowledgeMappings.length,
        'worksheetDraftCount': worksheetDrafts.length,
        'attachments': attachmentIndex,
        if (_encryptBackup) 'encrypted': true,
      };
      final archive = Archive();
      archive.addFile(ArchiveFile(
          'manifest.json', 0, utf8.encode(jsonEncode(manifest))));
      archive.addFile(ArchiveFile('questions.json', 0,
          utf8.encode(jsonEncode(questions.map(_questionToJson).toList()))));
      archive.addFile(ArchiveFile('review_logs.json', 0,
          utf8.encode(jsonEncode(reviewLogs.map(_reviewLogToJson).toList()))));
      // Phase 12-2：知识点树与组卷草稿。旧版本备份没有这两个文件，
      // 导入时按空列表处理。
      archive.addFile(ArchiveFile('knowledge_points.json', 0,
          utf8.encode(jsonEncode(knowledgePoints.map((kp) => kp.toJson()).toList()))));
      archive.addFile(ArchiveFile('question_knowledge_links.json', 0,
          utf8.encode(jsonEncode(knowledgeLinks.map((link) => link.toJson()).toList()))));
      archive.addFile(ArchiveFile('pending_knowledge_mappings.json', 0,
          utf8.encode(jsonEncode(pendingKnowledgeMappings.map((mapping) => mapping.toJson()).toList()))));
      archive.addFile(ArchiveFile('worksheet_drafts.json', 0,
          utf8.encode(jsonEncode(worksheetDrafts.map((d) => d.toJson()).toList()))));
      for (final attachment in attachments) {
        final content = attachment['contentBase64'] as String?;
        final questionId = attachment['questionId'] as String?;
        final fileName = attachment['fileName'] as String?;
        if (content == null || questionId == null || fileName == null) continue;
        archive.addFile(ArchiveFile(
            'attachments/${questionId}_$fileName',
            0,
            base64Decode(content)));
      }
      final encoded = ZipEncoder().encode(archive);
      if (encoded == null) throw const FileSystemException('无法创建备份包');
      final bytesToWrite = _encryptBackup
          ? _encryptBytes(Uint8List.fromList(encoded), password)
          : Uint8List.fromList(encoded);
      final file =
          File('${exportDir.path}/wrong-notebook-${now.millisecondsSinceEpoch}.wnb');
      await file.writeAsBytes(bytesToWrite, flush: true);
      await ExportHistoryService.add(ExportHistoryEntry(
        timestamp: now.millisecondsSinceEpoch,
        format: 'WNB',
        template: '完整备份',
        questionCount: questions.length,
        title: '错题本完整备份',
        fileName: file.uri.pathSegments.last,
      ));
      await _reloadExports();
      if (!mounted) return;
      setState(() => _lastBackupLabel =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} · ${questions.length} 题${_encryptBackup ? ' · 加密' : ''}');
      await AppShareService.shareFile(
        context,
        file.path,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份失败: $e')),
        );
      }
    }
  }

  Future<bool?> _showBackupPreview(
    BuildContext context,
    List<QuestionRecord> questions,
    int logCount,
  ) async {
    final attachments = await _buildAttachmentBackup(questions);
    // Phase 12-2：预览时也读取知识点树与组卷草稿条数，告知用户备份范围。
    final knowledgePoints =
        await ref.read(knowledgePointRepositoryProvider).loadAll();
    final knowledgeLinks =
        await ref.read(questionKnowledgeLinkRepositoryProvider).allLinks();
    final pendingKnowledgeMappings = await ref
        .read(pendingKnowledgePointMappingRepositoryProvider)
        .allMappings();
    final worksheetDrafts =
        await ref.read(worksheetDraftRepositoryProvider).loadAll();
    final metadataBytes = utf8
        .encode(jsonEncode(attachments.map((item) {
          final copy = Map<String, dynamic>.from(item)
            ..remove('contentBase64');
          return copy;
        }).toList()))
        .length;
    final bytes =
        utf8.encode(jsonEncode(questions.map(_questionToJson).toList())).length +
            metadataBytes +
            attachments.fold<int>(
                0, (sum, item) => sum + base64Decode(item['contentBase64'] as String).length);
    final estimate = _formatBytes(bytes);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('创建完整备份'),
        content: Text(
            '将创建可在新设备恢复的 .wnb 备份包：\n\n✓ ${questions.length} 道错题\n✓ $logCount 条复习记录\n✓ ${attachments.length} 张题图\n✓ ${knowledgePoints.length} 个知识点\n✓ ${knowledgeLinks.length} 条知识点关联\n✓ ${pendingKnowledgeMappings.length} 条待确认知识点\n✓ ${worksheetDrafts.length} 份组卷草稿\n预计大小：约 $estimate（压缩后可能更小）\n\n不会包含 API Key、临时导入会话和未确认的工作台草稿。'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('创建并保存')),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  Future<List<Map<String, dynamic>>> _buildAttachmentBackup(
    List<QuestionRecord> questions,
  ) async {
    final attachments = <Map<String, dynamic>>[];
    for (final question in questions) {
      if (question.imagePath.isEmpty) continue;
      final file = File(question.imagePath);
      if (!await file.exists()) continue;
      try {
        final bytes = await file.readAsBytes();
        attachments.add(<String, dynamic>{
          'questionId': question.id,
          'fileName': file.uri.pathSegments.isEmpty
              ? '${question.id}.jpg'
              : file.uri.pathSegments.last,
          'contentBase64': base64Encode(bytes),
          'sha256': BackupAttachmentIntegrity.sha256Hex(bytes),
        });
      } catch (_) {
        // 单张图片读不出来不应阻塞整个备份。
      }
    }
    return attachments;
  }

  Map<String, dynamic> _questionToJson(QuestionRecord q) => q.toJson();

  Map<String, dynamic> _reviewLogToJson(ReviewLog log) => <String, dynamic>{
        'id': log.id,
        'questionRecordId': log.questionRecordId,
        'reviewedAt': log.reviewedAt.toIso8601String(),
        'result': log.result,
        'masteryAfter': log.masteryAfter.name,
      };

  // --- 从备份恢复 ---

  Future<dynamic> _readBackupFile(File file) async {
    final rawBytes = Uint8List.fromList(await file.readAsBytes());
    // 加密备份：先弹密码框解密，再走原本的 zip 解析流程。
    if (_isEncryptedBytes(rawBytes)) {
      Uint8List? plain;
      while (plain == null) {
        final password = await _promptForPassword(context);
        if (password == null) {
          // 用户取消，返回特殊标记让上层中止恢复流程。
          throw const _RestoreCancelledException();
        }
        plain = _decryptBytes(rawBytes, password);
        if (plain == null) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('密码错误或备份已损坏，请重试')),
            );
          }
        }
      }
      return _decodeBackupBytes(plain);
    }
    if (!file.path.toLowerCase().endsWith('.wnb')) {
      return jsonDecode(utf8.decode(rawBytes));
    }
    return _decodeBackupBytes(rawBytes);
  }

  dynamic _decodeBackupBytes(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    String readText(String name) {
      final entry =
          archive.files.where((item) => item.name == name).firstOrNull;
      if (entry == null) throw const FormatException('备份包缺少必要文件');
      return utf8.decode(entry.content as List<int>);
    }

    /// 读取可选文件；旧版本备份（schema < 6）没有知识点树/组卷草稿文件，
    /// 视为空列表。文件存在但解析失败时也返回空列表，避免阻塞恢复流程。
    List<dynamic> readOptionalList(String name) {
      final entry =
          archive.files.where((item) => item.name == name).firstOrNull;
      if (entry == null || !entry.isFile) return const <dynamic>[];
      try {
        return jsonDecode(utf8.decode(entry.content as List<int>)) as List;
      } catch (_) {
        return const <dynamic>[];
      }
    }

    final manifest =
        Map<String, dynamic>.from(jsonDecode(readText('manifest.json')) as Map);
    final index = manifest['attachments'] is List
        ? manifest['attachments'] as List
        : const <dynamic>[];
    final attachments = <Map<String, dynamic>>[];
    var corrupt = 0;
    for (final item in index) {
      if (item is! Map) continue;
      final questionId = item['questionId'];
      final fileName = item['fileName'];
      if (questionId is! String || fileName is! String) continue;
      final entry = archive.files
          .where((file) => file.name == 'attachments/${questionId}_$fileName')
          .firstOrNull;
      if (entry == null || !entry.isFile) {
        corrupt++;
        continue;
      }
      final bytes = Uint8List.fromList(entry.content as List<int>);
      if (item['byteSize'] != bytes.length ||
          !BackupAttachmentIntegrity.matches(
              bytes, item['sha256'] as String?)) {
        corrupt++;
        continue;
      }
      attachments.add(<String, dynamic>{
        'questionId': questionId,
        'fileName': fileName,
        'contentBase64': base64Encode(bytes),
        'sha256': item['sha256'],
      });
    }
    return <String, dynamic>{
      ...manifest,
      'questions': jsonDecode(readText('questions.json')),
      'reviewLogs': jsonDecode(readText('review_logs.json')),
      'knowledgePoints': readOptionalList('knowledge_points.json'),
      'questionKnowledgeLinks': readOptionalList('question_knowledge_links.json'),
      'pendingKnowledgeMappings': readOptionalList('pending_knowledge_mappings.json'),
      'worksheetDrafts': readOptionalList('worksheet_drafts.json'),
      'attachments': attachments,
      'corruptAttachmentCount': corrupt,
    };
  }

  _BackupPreview _backupPreview(dynamic decoded) {
    final questions = _questionsFromBackup(decoded);
    final attachments = decoded is Map && decoded['attachments'] is List
        ? (decoded['attachments'] as List).length
        : 0;
    final logs = decoded is Map && decoded['reviewLogs'] is List
        ? (decoded['reviewLogs'] as List).length
        : 0;
    final corrupt = decoded is Map && decoded['corruptAttachmentCount'] is int
        ? decoded['corruptAttachmentCount'] as int
        : 0;
    final knowledgePoints = decoded is Map && decoded['knowledgePoints'] is List
        ? (decoded['knowledgePoints'] as List).length
        : 0;
    final knowledgeLinks = decoded is Map && decoded['questionKnowledgeLinks'] is List
        ? (decoded['questionKnowledgeLinks'] as List).length
        : 0;
    final pendingKnowledgeMappings = decoded is Map && decoded['pendingKnowledgeMappings'] is List
        ? (decoded['pendingKnowledgeMappings'] as List).length
        : 0;
    final worksheetDrafts = decoded is Map && decoded['worksheetDrafts'] is List
        ? (decoded['worksheetDrafts'] as List).length
        : 0;
    return _BackupPreview(
        questions.length,
        logs,
        attachments,
        corrupt,
        decoded is Map ? decoded['generatedAt'] as String? : null,
        knowledgePoints,
        knowledgeLinks,
        pendingKnowledgeMappings,
        worksheetDrafts);
  }

  Future<bool?> _showRestorePreview(
          BuildContext context, _BackupPreview preview) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认恢复备份'),
          content: Text(
              '备份内容：\n✓ ${preview.questions} 道错题\n✓ ${preview.logs} 条复习记录\n✓ ${preview.attachments} 张题图${preview.corruptAttachments == 0 ? '' : '\n⚠ ${preview.corruptAttachments} 张题图校验失败，将跳过'}\n✓ ${preview.knowledgePoints} 个知识点\n✓ ${preview.knowledgeLinks} 条知识点关联\n✓ ${preview.pendingKnowledgeMappings} 条待确认知识点\n✓ ${preview.worksheetDrafts} 份组卷草稿${preview.generatedAt == null ? '' : '\n\n创建时间：${preview.generatedAt}'}\n\n将以"合并"方式恢复；当前已有的同 ID 题目会跳过，不会清空现有题库。'),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('开始恢复')),
          ],
        ),
      );

  Future<void> _showRestoreResult(BuildContext context, int questions, int logs,
      int images, int skipped, int knowledgePoints, int knowledgeLinks,
      int pendingKnowledgeMappings, int worksheetDrafts) =>
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('恢复完成'),
          content: Text(
              '✓ 新增错题：$questions 道\n✓ 恢复复习记录：$logs 条\n✓ 恢复题图：$images 张\n✓ 恢复知识点：$knowledgePoints 个\n✓ 恢复知识点关联：$knowledgeLinks 条\n✓ 恢复待确认知识点：$pendingKnowledgeMappings 条\n✓ 恢复组卷草稿：$worksheetDrafts 份\n⊘ 跳过重复或无效记录：$skipped 条\n\n可在本页顶部撤销本次恢复。'),
          actions: <Widget>[
            FilledButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('完成')),
          ],
        ),
      );

  Future<void> _undoLastImport(BuildContext context, WidgetRef ref) async {
    final undo = _lastImport;
    if (undo == null) return;
    final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('撤销本次恢复？'),
                content: Text(
                    '将删除本次恢复的 ${undo.questionIds.length} 道题、${undo.reviewLogIds.length} 条复习记录及题图。'),
                actions: <Widget>[
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('撤销')),
                ]));
    if (yes != true) return;
    final repo = ref.read(questionRepositoryProvider);
    for (final id in undo.questionIds) {
      await repo.delete(id);
    }
    await ref.read(reviewLogRepositoryProvider).deleteByIds(undo.reviewLogIds);
    for (final path in undo.imagePaths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    if (mounted) setState(() => _lastImport = null);
    await (await SharedPreferences.getInstance()).remove(_lastImportKey);
    invalidateQuestionList(ref);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已撤销本次恢复')));
    }
  }

  Future<void> _importQuestions(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.platform
          .pickFiles(type: FileType.custom, allowedExtensions: ['json', 'wnb']);
      if (result == null || result.files.isEmpty) return;
      final file = File(result.files.first.path!);
      final decoded = await _readBackupFile(file);
      final preview = _backupPreview(decoded);
      final proceed = await _showRestorePreview(context, preview);
      if (proceed != true || !context.mounted) return;
      final list = _questionsFromBackup(decoded);
      final repo = ref.read(questionRepositoryProvider);
      final existingIds = (await repo.listAll()).map((q) => q.id).toSet();
      final importableIds = list
          .whereType<Map>()
          .map((item) => item['id'])
          .whereType<String>()
          .where((id) => id.isNotEmpty && !existingIds.contains(id))
          .toSet();
      final attachmentPaths =
          await _restoreAttachments(decoded, allowedIds: importableIds);
      int imported = 0;
      int skipped = 0;
      final importedIds = <String>{};
      final restoredImagePaths = <String>[];

      for (final item in list) {
        if (item is! Map) {
          skipped++;
          continue;
        }
        final record = _jsonToQuestion(Map<String, dynamic>.from(item));
        if (record == null ||
            record.id.isEmpty ||
            !existingIds.add(record.id)) {
          skipped++;
          continue;
        }
        final restoredPath = attachmentPaths[record.id];
        if (restoredPath != null) restoredImagePaths.add(restoredPath);
        await repo.saveDraft(restoredPath == null
            ? record
            : record.copyWith(imagePath: restoredPath));
        importedIds.add(record.id);
        imported++;
      }

      final restoredReviewLogIds = await _restoreReviewLogs(
        decoded,
        ref,
        allowedQuestionIds: importedIds,
      );
      // Phase 12-2：恢复知识点树和组卷草稿。两者都按"合并"策略，
      // 已有同 ID 记录会被覆盖（upsertAll / save 内部处理）。
      final restoredKnowledgePoints =
          await _restoreKnowledgePoints(decoded, ref);
      final restoredKnowledgeLinks =
          await _restoreQuestionKnowledgeLinks(decoded, ref);
      final restoredPendingKnowledgeMappings =
          await _restorePendingKnowledgeMappings(decoded, ref);
      final restoredWorksheetDrafts =
          await _restoreWorksheetDrafts(decoded, ref);
      final undo = _ImportUndo(
          importedIds, restoredReviewLogIds.toSet(), restoredImagePaths);
      await _persistLastImport(undo);
      if (mounted) setState(() => _lastImport = undo);
      invalidateQuestionList(ref);

      if (!context.mounted) return;
      await _showRestoreResult(
          context,
          imported,
          restoredReviewLogIds.length,
          restoredImagePaths.length,
          skipped,
          restoredKnowledgePoints,
          restoredKnowledgeLinks,
          restoredPendingKnowledgeMappings,
          restoredWorksheetDrafts);
    } on _RestoreCancelledException {
      // 用户在密码框取消，静默返回，不显示错误。
      return;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  /// Phase 12-2：恢复知识点树。按 ID 合并：备份中存在的节点会 upsert
  /// 到本地，已有同 ID 节点会被覆盖（保留备份版本），本地独有的节点
  /// 不受影响。返回实际写入的节点数。
  Future<int> _restoreKnowledgePoints(dynamic decoded, WidgetRef ref) async {
    if (decoded is! Map || decoded['knowledgePoints'] is! List) return 0;
    final repo = ref.read(knowledgePointRepositoryProvider);
    // loadAll 触发缓存加载，确保 upsertAll 能正确合并。
    await repo.loadAll();
    final toUpsert = <KnowledgePoint>[];
    for (final raw in decoded['knowledgePoints'] as List) {
      if (raw is! Map) continue;
      try {
        final kp = KnowledgePoint.fromJson(Map<String, dynamic>.from(raw));
        toUpsert.add(kp);
      } catch (_) {
        // 单个节点解析失败不应阻塞整体恢复。
      }
    }
    if (toUpsert.isEmpty) return 0;
    await repo.upsertAll(toUpsert);
    // 刷新知识点树快照，让 UI 立即看到恢复结果。
    ref.invalidate(knowledgePointTreeProvider);
    return toUpsert.length;
  }

  Future<int> _restoreQuestionKnowledgeLinks(dynamic decoded, WidgetRef ref) async {
    if (decoded is! Map || decoded['questionKnowledgeLinks'] is! List) return 0;
    final repo = ref.read(questionKnowledgeLinkRepositoryProvider);
    var restored = 0;
    for (final raw in decoded['questionKnowledgeLinks'] as List) {
      if (raw is! Map) continue;
      try {
        await repo.addLink(
          QuestionKnowledgeLink.fromJson(Map<String, dynamic>.from(raw)),
        );
        restored++;
      } catch (_) {
        // 单条关联解析失败不应阻塞整体恢复。
      }
    }
    if (restored > 0) invalidateQuestionList(ref);
    return restored;
  }

  Future<int> _restorePendingKnowledgeMappings(dynamic decoded, WidgetRef ref) async {
    if (decoded is! Map || decoded['pendingKnowledgeMappings'] is! List) return 0;
    final mappings = <PendingKnowledgePointMapping>[];
    for (final raw in decoded['pendingKnowledgeMappings'] as List) {
      if (raw is! Map) continue;
      try {
        mappings.add(PendingKnowledgePointMapping.fromJson(Map<String, dynamic>.from(raw)));
      } catch (_) {
        // 单条待确认记录解析失败不应阻塞整体恢复。
      }
    }
    if (mappings.isEmpty) return 0;
    await ref.read(pendingKnowledgePointMappingRepositoryProvider).upsertAll(mappings);
    invalidatePendingKnowledgePoints(ref);
    return mappings.length;
  }

  /// Phase 12-2：恢复组卷草稿。按 ID 合并：备份中的草稿会 save 到本地
  /// （同 ID 覆盖 updatedAt，新 ID 插入）。返回实际写入的草稿数。
  Future<int> _restoreWorksheetDrafts(dynamic decoded, WidgetRef ref) async {
    if (decoded is! Map || decoded['worksheetDrafts'] is! List) return 0;
    final repo = ref.read(worksheetDraftRepositoryProvider);
    var restored = 0;
    for (final raw in decoded['worksheetDrafts'] as List) {
      if (raw is! Map) continue;
      try {
        final draft =
            WorksheetDraft.fromJson(Map<String, dynamic>.from(raw));
        await repo.save(draft);
        restored++;
      } catch (_) {
        // 单个草稿解析失败不应阻塞整体恢复。
      }
    }
    if (restored > 0) {
      ref.invalidate(savedWorksheetDraftsProvider);
    }
    return restored;
  }

  Future<Map<String, String>> _restoreAttachments(
    dynamic decoded, {
    required Set<String> allowedIds,
  }) async {
    if (decoded is! Map || decoded['attachments'] is! List) {
      return const <String, String>{};
    }
    final documents = await getApplicationDocumentsDirectory();
    final staging = Directory(
        '${documents.path}/restore_staging_${DateTime.now().microsecondsSinceEpoch}');
    final attachmentDir = Directory('${documents.path}/imported_images');
    await staging.create(recursive: true);
    final restored = <String, String>{};
    try {
      for (final item in decoded['attachments'] as List) {
        if (item is! Map) continue;
        final questionId = item['questionId'];
        final content = item['contentBase64'];
        if (questionId is! String ||
            questionId.isEmpty ||
            !allowedIds.contains(questionId) ||
            content is! String) continue;
        final bytes = base64Decode(content);
        if (!BackupAttachmentIntegrity.matches(
            bytes, item['sha256'] as String?)) continue;
        final rawName =
            item['fileName'] is String ? item['fileName'] as String : 'image.jpg';
        final safeName = rawName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final staged = File('${staging.path}/${questionId}_$safeName');
        await staged.writeAsBytes(bytes, flush: true);
        restored[questionId] = staged.path;
      }
      await attachmentDir.create(recursive: true);
      final committed = <String, String>{};
      for (final entry in restored.entries) {
        final source = File(entry.value);
        final target =
            File('${attachmentDir.path}/${source.uri.pathSegments.last}');
        await source.rename(target.path);
        committed[entry.key] = target.path;
      }
      return committed;
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<List<String>> _restoreReviewLogs(
    dynamic decoded,
    WidgetRef ref, {
    required Set<String> allowedQuestionIds,
  }) async {
    if (decoded is! Map || decoded['reviewLogs'] is! List) {
      return const <String>[];
    }
    final repository = ref.read(reviewLogRepositoryProvider);
    final existingIds =
        (await repository.listAll()).map((log) => log.id).toSet();
    final restored = <String>[];
    for (final raw in decoded['reviewLogs'] as List) {
      if (raw is! Map) continue;
      final log = _jsonToReviewLog(Map<String, dynamic>.from(raw));
      if (log == null ||
          !allowedQuestionIds.contains(log.questionRecordId) ||
          !existingIds.add(log.id)) {
        continue;
      }
      await repository.insert(log);
      restored.add(log.id);
    }
    return restored;
  }

  ReviewLog? _jsonToReviewLog(Map<String, dynamic> json) {
    final id = json['id'];
    final questionId = json['questionRecordId'];
    final reviewedAt = json['reviewedAt'];
    final result = json['result'];
    final masteryName = json['masteryAfter'];
    if (id is! String ||
        id.isEmpty ||
        questionId is! String ||
        questionId.isEmpty ||
        reviewedAt is! String ||
        result is! String ||
        masteryName is! String) {
      return null;
    }
    final timestamp = DateTime.tryParse(reviewedAt);
    if (timestamp == null) return null;
    final mastery =
        MasteryLevel.values.where((level) => level.name == masteryName);
    if (mastery.isEmpty) return null;
    return ReviewLog(
      id: id,
      questionRecordId: questionId,
      reviewedAt: timestamp,
      result: result,
      masteryAfter: mastery.first,
    );
  }

  List<dynamic> _questionsFromBackup(dynamic decoded) {
    // 旧版 v1 导出是裸 list；v2+ 用 envelope 包了一层，方便后续演进。
    if (decoded is List) return decoded;
    if (decoded is! Map) throw const FormatException('备份文件格式不正确');
    final version = decoded['schemaVersion'];
    if (version is int && version > _backupSchemaVersion) {
      throw FormatException('备份版本 $version 高于当前应用支持的版本');
    }
    final questions = decoded['questions'];
    if (questions is! List) throw const FormatException('备份中没有题目数据');
    return questions;
  }

  QuestionRecord? _jsonToQuestion(Map<String, dynamic> map) {
    try {
      return QuestionRecord.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  // --- 清空数据 ---

  void _confirmClearAll(BuildContext context, WidgetRef ref, int count) {
    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('题库为空，无需清空')),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清空'),
        content: Text('确定要删除全部 $count 道错题及其复习记录吗？此操作不可恢复。'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _clearAllData(ref, context);
            },
            child: const Text('清空', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllData(WidgetRef ref, BuildContext context) async {
    final repo = ref.read(questionRepositoryProvider);
    final all = await repo.listAll();
    for (final q in all) {
      await repo.delete(q.id);
    }
    await ref.read(reviewLogRepositoryProvider).clear();
    invalidateQuestionList(ref);
    ref.read(currentQuestionProvider.notifier).state = null;

    var imageDeleteFailures = 0;
    for (final q in all) {
      try {
        final file = File(q.imagePath);
        if (await file.exists()) await file.delete();
      } catch (e) {
        imageDeleteFailures++;
        debugPrint('[DataManagement] 删除图片失败 ${q.imagePath}: $e');
      }
    }

    if (context.mounted) {
      final msg = imageDeleteFailures == 0
          ? '已清空 ${all.length} 道错题'
          : '已清空 ${all.length} 道错题；$imageDeleteFailures 张图片文件清理失败，可手动清理';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  // --- Phase 12-2：缓存清理 ---

  /// 清理临时目录中超过 7 天的 HTML / PDF 预览文件。
  ///
  /// 学情周报、错因趋势热力图、学科雷达图等模块在生成预览时会写入
  /// 系统临时目录，长期累积会占用空间。这里按修改时间过滤，删除 7 天
  /// 前的 .html / .pdf 文件，避免误删其他模块正在使用的临时文件。
  Future<void> _cleanTempPreviews(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理临时预览文件'),
        content: const Text('将删除系统临时目录中超过 7 天的 HTML / PDF 预览文件。该操作不会影响错题数据。'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('开始清理')),
        ],
      ),
    );
    if (confirmed != true) return;

    int deletedCount = 0;
    int freedBytes = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      if (!tempDir.existsSync()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('临时目录为空，无需清理')),
          );
        }
        return;
      }
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      final entities = tempDir.listSync(followLinks: false);
      for (final entity in entities) {
        if (entity is! File) continue;
        final lower = entity.path.toLowerCase();
        if (!lower.endsWith('.html') && !lower.endsWith('.pdf')) continue;
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            freedBytes += stat.size;
            await entity.delete();
            deletedCount++;
          }
        } catch (_) {
          // 单个文件失败不应阻塞整体清理。
        }
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(deletedCount == 0
              ? '没有需要清理的临时预览文件'
              : '已清理 $deletedCount 个临时预览文件，释放 ${_formatBytes(freedBytes)}'),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清理失败: $e')),
        );
      }
    }
  }

  /// 扫描题图目录，删除不再被任何错题引用的孤立图片文件。
  ///
  /// 题图存储路径为 `${appDir}/wrong_question_images`（见
  /// ImageStorageService）。删除错题时若图片文件未能同步删除，会留下
  /// 孤立文件。这里收集所有 QuestionRecord.imagePath，删除目录中不在
  /// 该集合内的文件。
  Future<void> _cleanOrphanImages(
    BuildContext context,
    WidgetRef ref,
    List<QuestionRecord> questions,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理孤立题图'),
        content: const Text('将扫描题图目录，删除不再被任何错题引用的图片文件。该操作不可恢复。'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('开始清理')),
        ],
      ),
    );
    if (confirmed != true) return;

    int deletedCount = 0;
    int freedBytes = 0;
    int scanCount = 0;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/wrong_question_images');
      if (!imagesDir.existsSync()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('题图目录不存在，无需清理')),
          );
        }
        return;
      }
      // 收集所有被错题引用的图片绝对路径（规范化以避免大小写/分隔符差异）。
      final referenced = <String>{};
      for (final q in questions) {
        if (q.imagePath.isEmpty) continue;
        referenced.add(File(q.imagePath).absolute.path);
      }
      final entities = imagesDir.listSync(followLinks: false);
      for (final entity in entities) {
        if (entity is! File) continue;
        scanCount++;
        try {
          final absolutePath = entity.absolute.path;
          if (referenced.contains(absolutePath)) continue;
          final stat = await entity.stat();
          freedBytes += stat.size;
          await entity.delete();
          deletedCount++;
        } catch (_) {
          // 单个文件失败不应阻塞整体清理。
        }
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(deletedCount == 0
              ? '扫描了 $scanCount 个文件，未发现孤立题图'
              : '已清理 $deletedCount 个孤立题图，释放 ${_formatBytes(freedBytes)}'),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清理失败: $e')),
        );
      }
    }
  }
}

class _ImportUndo {
  const _ImportUndo(this.questionIds, this.reviewLogIds, this.imagePaths);
  final Set<String> questionIds;
  final Set<String> reviewLogIds;
  final List<String> imagePaths;
  Map<String, dynamic> toJson() => <String, dynamic>{
        'questionIds': questionIds.toList(),
        'reviewLogIds': reviewLogIds.toList(),
        'imagePaths': imagePaths,
      };
  factory _ImportUndo.fromJson(Map<String, dynamic> json) => _ImportUndo(
        (json['questionIds'] as List? ?? const <dynamic>[])
            .whereType<String>()
            .toSet(),
        (json['reviewLogIds'] as List? ?? const <dynamic>[])
            .whereType<String>()
            .toSet(),
        (json['imagePaths'] as List? ?? const <dynamic>[])
            .whereType<String>()
            .toList(),
      );
}

class _BackupPreview {
  const _BackupPreview(
      this.questions,
      this.logs,
      this.attachments,
      this.corruptAttachments,
      this.generatedAt,
      this.knowledgePoints,
      this.knowledgeLinks,
      this.pendingKnowledgeMappings,
      this.worksheetDrafts);
  final int questions;
  final int logs;
  final int attachments;
  final int corruptAttachments;
  final String? generatedAt;
  final int knowledgePoints;
  final int knowledgeLinks;
  final int pendingKnowledgeMappings;
  final int worksheetDrafts;
}

/// 用户在加密备份恢复的密码框中取消时抛出，用于中止恢复流程。
class _RestoreCancelledException implements Exception {
  const _RestoreCancelledException();
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Text(label,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w700));
}

class _BackupStatusCard extends StatelessWidget {
  const _BackupStatusCard({
    required this.questionCount,
    required this.lastBackupLabel,
    this.onBackup,
    required this.onRestore,
    this.onUndo,
    this.encryptBackup = false,
    this.onEncryptToggle,
    this.passwordController,
  });
  final int questionCount;
  final String? lastBackupLabel;
  final VoidCallback? onBackup;
  final VoidCallback onRestore;
  final VoidCallback? onUndo;
  final bool encryptBackup;
  final ValueChanged<bool>? onEncryptToggle;
  final TextEditingController? passwordController;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(children: <Widget>[
                const Icon(CupertinoIcons.shield_lefthalf_fill,
                    color: Color(0xFF4F46E5)),
                const SizedBox(width: 10),
                Text('数据备份与迁移',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              Text(
                  lastBackupLabel == null
                      ? (questionCount == 0
                          ? '题库为空；保存错题后可创建完整备份。'
                          : '尚未在本次使用中创建备份，建议在导入大量题目后保存。')
                      : '最近备份：$lastBackupLabel',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.icon(
                      onPressed: onBackup,
                      icon: const Icon(CupertinoIcons.arrow_down_doc),
                      label: const Text('备份全部数据')),
                  OutlinedButton.icon(
                      onPressed: onRestore,
                      icon: const Icon(CupertinoIcons.arrow_up_doc),
                      label: const Text('从备份恢复')),
                  if (onUndo != null)
                    TextButton.icon(
                        onPressed: onUndo,
                        icon: const Icon(CupertinoIcons.arrow_uturn_left),
                        label: const Text('撤销本次恢复')),
                ],
              ),
              if (onEncryptToggle != null) ...<Widget>[
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Checkbox(
                      value: encryptBackup,
                      onChanged: (v) => onEncryptToggle!(v ?? false),
                    ),
                    const Expanded(
                      child: Text('加密备份（简易 XOR 加密，仅防偷窥）'),
                    ),
                  ],
                ),
                if (encryptBackup && passwordController != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: '密码',
                        hintText: '恢复时需要输入此密码',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
}

class _DataCard extends StatelessWidget {
  const _DataCard({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.trailingWidget,
    this.iconColor,
    this.titleColor,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final Widget? trailingWidget;
  final Color? iconColor;
  final Color? titleColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveIconColor = iconColor ?? colorScheme.onSurfaceVariant;

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 24, color: effectiveIconColor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: _titleStyle(context, color: titleColor)),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(subtitle!, style: _subtitleStyle(context)),
                    ],
                  ],
                ),
              ),
              if (trailingWidget != null)
                trailingWidget!
              else if (trailing != null)
                Text(trailing!, style: _trailingStyle(context))
              else if (onTap != null)
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 22,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle _titleStyle(BuildContext context, {Color? color}) {
  final colorScheme = Theme.of(context).colorScheme;
  return TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: color ?? colorScheme.onSurface);
}

TextStyle _subtitleStyle(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;
  return TextStyle(
      fontSize: 12, color: colorScheme.onSurfaceVariant, height: 1.35);
}

TextStyle _trailingStyle(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;
  return TextStyle(
      fontSize: 16, fontWeight: FontWeight.w600, color: colorScheme.onSurface);
}

/// 导出历史卡片：FutureBuilder + ListView.builder 加载 exports 目录文件，
/// 支持下拉刷新；每行显示文件名/大小/生成时间，提供分享/重命名/邮件/删除操作。
class _ExportHistoryCard extends StatelessWidget {
  const _ExportHistoryCard({
    required this.future,
    required this.onRefresh,
    required this.onShare,
    required this.onDelete,
    required this.onRename,
    required this.onEmail,
  });

  final Future<List<File>>? future;
  final Future<void> Function() onRefresh;
  final void Function(File file) onShare;
  final void Function(File file) onDelete;
  final void Function(File file) onRename;
  final void Function(File file) onEmail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FutureBuilder<List<File>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final files = snapshot.data ?? const <File>[];
            if (files.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    '暂无导出文件。导出 HTML/PDF 或创建备份后会在这里显示。',
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: onRefresh,
              child: ListView.builder(
                shrinkWrap: true,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: files.length,
                itemBuilder: (context, index) {
                  final file = files[index];
                  return _ExportFileTile(
                    file: file,
                    onShare: () => onShare(file),
                    onDelete: () => onDelete(file),
                    onRename: () => onRename(file),
                    onEmail: () => onEmail(file),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ExportFileTile extends StatelessWidget {
  const _ExportFileTile({
    required this.file,
    required this.onShare,
    required this.onDelete,
    required this.onRename,
    required this.onEmail,
  });

  final File file;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback onRename;
  final VoidCallback onEmail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final stat = file.statSync();
    final filename = file.uri.pathSegments.last;
    final sizeStr = _formatBytes(stat.size);
    final timeStr = DateFormat('yyyy-MM-dd HH:mm').format(stat.modified);
    final isPdf = filename.toLowerCase().endsWith('.pdf');
    final isHtml = filename.toLowerCase().endsWith('.html');
    final isBackup = filename.toLowerCase().endsWith('.wnb');
    final icon = isPdf
        ? CupertinoIcons.doc_richtext
        : isHtml
            ? CupertinoIcons.doc_text
            : isBackup
                ? CupertinoIcons.archivebox
                : CupertinoIcons.doc;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Icon(icon, color: colorScheme.primary),
      title: Text(
        filename,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '$sizeStr · $timeStr',
        style: TextStyle(
            fontSize: 12, color: colorScheme.onSurfaceVariant),
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(CupertinoIcons.ellipsis_circle, size: 22),
        tooltip: '操作',
        onSelected: (value) {
          switch (value) {
            case 'share':
              onShare();
              break;
            case 'email':
              onEmail();
              break;
            case 'rename':
              onRename();
              break;
            case 'delete':
              onDelete();
              break;
          }
        },
        itemBuilder: (ctx) => <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(
            value: 'share',
            child: ListTile(
              leading: Icon(CupertinoIcons.share),
              title: Text('重新分享'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
          const PopupMenuItem<String>(
            value: 'email',
            child: ListTile(
              leading: Icon(CupertinoIcons.envelope),
              title: Text('邮件发送'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
          const PopupMenuItem<String>(
            value: 'rename',
            child: ListTile(
              leading: Icon(CupertinoIcons.pencil),
              title: Text('重命名'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: 'delete',
            child: ListTile(
              leading: Icon(CupertinoIcons.delete, color: AppColors.danger),
              title: Text('删除',
                  style: TextStyle(color: AppColors.danger)),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

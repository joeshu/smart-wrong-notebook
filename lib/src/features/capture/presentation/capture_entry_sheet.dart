import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/capture_mode.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:uuid/uuid.dart';

import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_layout.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';


class CaptureEntrySheet extends ConsumerStatefulWidget {
  const CaptureEntrySheet({super.key, this.showCloseButton = true});

  /// 是否显示右上角关闭按钮。底部 sheet 场景为 true，
  /// 作为「添加」Tab 根页面时为 false（由 AppBar 提供返回）。
  final bool showCloseButton;

  @override
  ConsumerState<CaptureEntrySheet> createState() => _CaptureEntrySheetState();
}

class _CaptureEntrySheetState extends ConsumerState<CaptureEntrySheet> {
  bool _isLoading = false;
  String _loadingMessage = '正在处理...';
  String? _errorMessage;

  // 极速模式开关：拍照/选图后跳过裁剪与校对，直接进入 AI 解析。
  // 默认 false；启动时从 SettingsRepository 异步加载。
  bool _isQuickCaptureEnabled = false;
  bool _quickCaptureSettingLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadQuickCaptureSetting();
  }

  Future<void> _loadQuickCaptureSetting() async {
    try {
      final enabled = await ref
          .read(settingsRepositoryProvider)
          .isQuickCaptureEnabled();
      if (!mounted) return;
      setState(() {
        _isQuickCaptureEnabled = enabled;
        _quickCaptureSettingLoaded = true;
      });
    } catch (_) {
      // 在未初始化 SharedPreferences 的测试环境下读取可能抛出
      // MissingPluginException，这里默认关闭极速模式即可。
      if (!mounted) return;
      setState(() => _quickCaptureSettingLoaded = true);
    }
  }

  Future<void> _setQuickCaptureEnabled(bool enabled) async {
    setState(() => _isQuickCaptureEnabled = enabled);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .setQuickCaptureEnabled(enabled);
    } catch (_) {
      // 持久化失败时不阻塞 UI；用户切换仍生效到当前会话。
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pendingQuestion = ref.watch(currentQuestionProvider);
    final captureState = ref.watch(captureSessionProvider);
    const warning = AppColors.warningDark;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: AppPage(
        maxWidth: AppContentWidth.narrow,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.xl,
          vertical: AppSpace.xl,
        ),
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (widget.showCloseButton) ...<Widget>[
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: <Widget>[
                Text(
                  '录入错题',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (widget.showCloseButton)
                  IconButton(
                    icon: const Icon(CupertinoIcons.xmark, size: 20),
                    tooltip: '关闭',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            const AppTaskFlow(
              steps: <String>['拍一道错题', '确认识别', '查看错误定位', '开始练习'],
              currentStep: 0,
            ),
            const SizedBox(height: AppSpace.lg),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '拍照或从相册选择图片后，将使用当前 AI 模型进行识别与分析。',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: AppSpace.sm),
              leading: const Icon(CupertinoIcons.slider_horizontal_3),
              title: const Text('识别选项',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('印刷/手写模式与极速录入',
                  style: TextStyle(fontSize: 11)),
              children: <Widget>[
                _CaptureModeSelector(
                  mode: ref.watch(captureModeProvider),
                  onChanged: (mode) =>
                      ref.read(captureModeProvider.notifier).state = mode,
                ),
                _buildQuickCaptureSwitch(colorScheme),
              ],
            ),
            if (_isLoading)
              Container(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: <Widget>[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(_loadingMessage,
                        style: TextStyle(color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              )
            else ...<Widget>[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '从一道题开始',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '拍下或选择一张题目截图，先框选范围，再交给 AI 分析。',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              if (pendingQuestion != null && !captureState.isTerminal) ...<Widget>[
                _EntryOption(
                  icon: CupertinoIcons.play_circle_fill,
                  iconColor: AppColors.primary,
                  iconBg: AppColors.semanticContainer(
                    AppColors.primary,
                    isDark: isDark,
                  ),
                  label: '继续当前录题',
                  description: '已保存原图，完成 AI 配置后可从这里继续',
                  onTap: _resumeCurrentCapture,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _discardCurrentCapture,
                    icon: const Icon(CupertinoIcons.trash,
                        size: 14, color: AppColors.danger),
                    label: const Text('放弃当前任务',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.danger)),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              _EntryOption(
                icon: CupertinoIcons.camera,
                iconColor: AppColors.primary,
                iconBg: AppColors.semanticContainer(
                  AppColors.primary,
                  isDark: isDark,
                ),
                label: '拍照',
                description: '使用相机拍摄错题',
                onTap: () => _pickWithChoice(fromCamera: true),
              ),
              const SizedBox(height: 10),
              _EntryOption(
                icon: CupertinoIcons.photo,
                iconColor: AppColors.accentAmber,
                iconBg: AppColors.semanticContainer(
                  AppColors.accentAmber,
                  isDark: isDark,
                ),
                label: '相册',
                description: '从相册选择图片',
                onTap: () => _pickWithChoice(fromCamera: false),
              ),
              const SizedBox(height: AppSpace.md),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '其他方式',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              _EntryOption(
                icon: CupertinoIcons.doc_text,
                iconColor: AppColors.accentPurple,
                iconBg: AppColors.semanticContainer(
                  AppColors.accentPurple,
                  isDark: isDark,
                ),
                label: '复制粘贴录入',
                description: '直接粘贴题目文本，交给 AI 识别与分析',
                onTap: _pasteQuestionText,
              ),
              const SizedBox(height: 10),
              Text(
                'AI 会自动识别题目、错因和解题步骤。',
                style: TextStyle(fontSize: 12, height: 1.4, color: colorScheme.onSurfaceVariant),
              ),
            ],
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: AppColors.semanticContainer(
                    warning,
                    isDark: isDark,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  border: Border.all(
                    color: AppColors.semanticBorder(
                      warning,
                      isDark: isDark,
                    ),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(CupertinoIcons.exclamationmark_triangle,
                        size: 18, color: warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_errorMessage!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: warning,
                          ),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(CupertinoIcons.xmark, size: 16),
                      onPressed: () => setState(() => _errorMessage = null),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
  }

  Future<void> _pickWithChoice({required bool fromCamera}) async {
    final session = ref.read(captureSessionProvider.notifier);
    final sessionState = ref.read(captureSessionProvider);
    if (sessionState.imagePath != null && !sessionState.isTerminal) {
      setState(() => _errorMessage = '当前已有录入任务正在处理中，请先继续或取消后再录入。');
      return;
    }
    if (sessionState.isTerminal) session.endSession();
    final router = GoRouter.of(context);
    setState(() {
      _isLoading = true;
      _loadingMessage = fromCamera ? '正在打开相机...' : '正在打开相册...';
      _errorMessage = null;
    });
    try {
      final capture = ref.read(captureServiceProvider);
      final result = fromCamera
          ? await capture.pickFromCamera()
          : await capture.pickFromGallery();
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (result.isCancelled) return;
      if (result.errorMessage != null || result.record == null) {
        setState(() => _errorMessage = '获取图片失败：${result.errorMessage ?? '未返回图片'}');
        return;
      }
      final record = result.record!;

      session.selectImage(record.imagePath);
      session.setCurrentQuestion(record);
      try {
        await ref.read(questionRepositoryProvider).saveDraft(record);
      } catch (error) {
        await ref.read(captureServiceProvider).discardManagedImage(record.imagePath);
        session.endSession();
        if (!mounted) return;
        setState(() => _errorMessage = '保存录题草稿失败：$error');
        return;
      }

      final config = await ref.read(settingsRepositoryProvider).getAiProviderConfig();
      if (!mounted) return;
      if (config == null || config.baseUrl.isEmpty || config.apiKey.isEmpty || config.model.isEmpty) {
        await _showAiSetupDialog();
        return;
      }
      if (widget.showCloseButton) {
        Navigator.pop(context);
      }
      if (_isQuickCaptureEnabled) {
        router.go('/analysis/loading');
      } else {
        router.go('/capture/crop');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '操作失败: $e';
      });
    }
  }

  /// 放弃当前未完成的录入任务：删除草稿与托管图片，重置会话，
  /// 使「拍照/相册」等入口重新可用。
  Future<void> _discardCurrentCapture() async {
    debugPrint('[DISCARD] _discardCurrentCapture called, mounted=$mounted');
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('放弃当前录入任务？'),
        content: const Text('原图和当前草稿都会删除，且无法恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('继续录题'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('放弃并删除'),
          ),
        ],
      ),
    );
    debugPrint('[DISCARD] dialog closed, confirmed=$confirmed, mounted=$mounted');
    if (confirmed != true || !mounted) return;

    final question = ref.read(currentQuestionProvider);
    final session = ref.read(captureSessionProvider.notifier);
    debugPrint('[DISCARD] deleting question=${question?.id} '
        'repo=${ref.read(questionRepositoryProvider).runtimeType}');
    try {
      if (question != null) {
        await ref.read(questionRepositoryProvider).delete(question.id);
        debugPrint('[DISCARD] delete done');
        if (question.imagePath.isNotEmpty) {
          await ref
              .read(captureServiceProvider)
              .discardManagedImage(question.imagePath);
          debugPrint('[DISCARD] discard image done');
        }
      }
    } catch (error) {
      debugPrint('[CaptureEntry] discard current capture failed: $error');
    } finally {
      // 显式清空当前题目，避免丢弃后 currentQuestionProvider 仍持有已删除的草稿
      // （endSession 只终结 capture 会话，不会清 currentQuestionProvider）。
      ref.read(currentQuestionProvider.notifier).state = null;
      session.endSession();
      debugPrint('[DISCARD] endSession done, phase=${ref.read(captureSessionProvider).phase}');
      invalidateQuestionList(ref);
    }
    if (!mounted) return;
    setState(() => _errorMessage = null);
    debugPrint('[DISCARD] setState done');
  }

  Future<void> _resumeCurrentCapture() async {
    final question = ref.read(currentQuestionProvider);
    if (question == null) return;
    final config =
        await ref.read(settingsRepositoryProvider).getAiProviderConfig();
    if (!mounted) return;
    if (config == null ||
        config.baseUrl.isEmpty ||
        config.apiKey.isEmpty ||
        config.model.isEmpty) {
      await _showAiSetupDialog();
      return;
    }
    if (widget.showCloseButton) Navigator.pop(context);
    GoRouter.of(context).go(
      _isQuickCaptureEnabled ? '/analysis/loading' : '/capture/crop',
    );
  }

  /// 复制粘贴录入：直接粘贴题目文本，跳过图片识别，交给 AI 分析。
  ///
  /// 文本草稿不含图片（imagePath 为空），analysis_loading 会直接以
  /// [recognizedText] 作为题干进入 AI 识别→分析流程。
  Future<void> _pasteQuestionText() async {
    final config = await ref.read(settingsRepositoryProvider).getAiProviderConfig();
    if (!mounted) return;
    if (config == null ||
        config.baseUrl.isEmpty ||
        config.apiKey.isEmpty ||
        config.model.isEmpty) {
      await _showAiSetupDialog();
      return;
    }
    final text = await _showPasteDialog();
    if (!mounted) return;
    final trimmed = text?.trim() ?? '';
    if (trimmed.isEmpty) return;

    final record = QuestionRecord.draft(
      id: const Uuid().v4(),
      imagePath: '',
      subject: Subject.custom,
      recognizedText: trimmed,
    );
    final session = ref.read(captureSessionProvider.notifier);
    session.selectImage('');
    session.setCurrentQuestion(record);
    try {
      await ref.read(questionRepositoryProvider).saveDraft(record);
    } catch (error) {
      session.endSession();
      if (!mounted) return;
      setState(() => _errorMessage = '保存录题草稿失败：$error');
      return;
    }
    if (widget.showCloseButton) Navigator.pop(context);
    GoRouter.of(context).go('/analysis/loading');
  }

  /// 弹出粘贴文本框，返回用户提交的文本（取消返回 null）。
  Future<String?> _showPasteDialog() async {
    final controller = TextEditingController();
    if (!mounted) return null;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('复制粘贴录入'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 8,
            minLines: 4,
            decoration: const InputDecoration(
              hintText: '粘贴题目文本，交给 AI 识别与分析',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, null),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('开始分析'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _showAiSetupDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('AI 服务未配置'),
        content: const Text('请先配置 AI 地址、API Key 和模型名称，才能识别和分析错题。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('暂不设置'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.push('/settings/provider');
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  /// 构建极速模式开关。极速模式开启后，普通 AI 入口的拍照/选图会跳过
  /// 裁剪与校对页，直接进入 AI 解析加载页。
  Widget _buildQuickCaptureSwitch(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text(
          '极速模式',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: const Text(
          '拍照后直接 AI 解析，跳过裁剪与校对',
          style: TextStyle(fontSize: 11),
        ),
        value: _isQuickCaptureEnabled,
        onChanged: _quickCaptureSettingLoaded
            ? (value) => _setQuickCaptureEnabled(value)
            : null,
      ),
    );
  }



}

class _EntryOption extends StatelessWidget {
  const _EntryOption({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.description,
    required this.onTap,
    this.prominent = false,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String description;
  final VoidCallback onTap;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final radius = BorderRadius.circular(prominent ? AppRadius.large : AppRadius.medium);
    final background = prominent
        ? colorScheme.surfaceContainerLow
        : colorScheme.surface;

    return Semantics(
      button: true,
      label: '$label，$description',
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: EdgeInsets.all(prominent ? AppSpace.lg : 14),
          decoration: BoxDecoration(
            color: background,
            borderRadius: radius,
            border: Border.all(
              color: prominent
                  ? iconColor.withValues(alpha: 0.24)
                  : colorScheme.outlineVariant,
              width: prominent ? 1.2 : 1,
            ),
          ),
          child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, size: 22, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurface)),
                  const SizedBox(height: 2),
                  Text(description,
                      style: TextStyle(
                          fontSize: 12, color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right,
                size: 22,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
          ],
        ),
      ),
    ),
    );
  }
}



/// 录入模式选择器：决定 AI 识别时如何处理图片中的印刷与手写内容。
///
/// - [CaptureMode.printed]：只识别印刷题干，忽略手写批改（默认）
/// - [CaptureMode.handwritten]：忠实转录手写解答过程，包括错误步骤
/// - [CaptureMode.mixed]：同时识别印刷题干和手写批注
class _CaptureModeSelector extends StatelessWidget {
  const _CaptureModeSelector({required this.mode, required this.onChanged});

  final CaptureMode mode;
  final ValueChanged<CaptureMode> onChanged;

  String _description(CaptureMode mode) {
    switch (mode) {
      case CaptureMode.printed:
        return '只识别印刷题干，忽略手写批改痕迹、圈画、红叉等';
      case CaptureMode.handwritten:
        return '忠实转录手写解答过程，包括错误步骤';
      case CaptureMode.mixed:
        return '同时识别印刷题干和手写批注';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('本次录入的内容主要是？',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        SegmentedButton<CaptureMode>(
          segments: const <ButtonSegment<CaptureMode>>[
            ButtonSegment<CaptureMode>(
              value: CaptureMode.printed,
              label: Text('印刷题'),
              icon: Icon(CupertinoIcons.doc_text, size: 16),
            ),
            ButtonSegment<CaptureMode>(
              value: CaptureMode.handwritten,
              label: Text('手写解答'),
              icon: Icon(CupertinoIcons.pencil, size: 16),
            ),
            ButtonSegment<CaptureMode>(
              value: CaptureMode.mixed,
              label: Text('混合'),
              icon: Icon(CupertinoIcons.doc_richtext, size: 16),
            ),
          ],
          selected: <CaptureMode>{mode},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) onChanged(selection.first);
          },
          showSelectedIcon: true,
          style: const ButtonStyle(
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          _description(mode),
          style: TextStyle(
              fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

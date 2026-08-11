import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/capture_analysis_state.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_layout.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/shared/utils/image_quality_detector.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/cached_question_image.dart';

class QuestionCorrectionScreen extends ConsumerStatefulWidget {
  const QuestionCorrectionScreen({super.key});

  @override
  ConsumerState<QuestionCorrectionScreen> createState() =>
      _QuestionCorrectionScreenState();
}

class _QuestionCorrectionScreenState
    extends ConsumerState<QuestionCorrectionScreen> {
  ImageQualityResult? _qualityResult;
  String? _qualityError;
  bool _warningDismissed = false;
  bool _detecting = false;

  Future<void> _discardCapture() async {
    final current = ref.read(currentQuestionProvider);
    if (current == null) {
      if (mounted) context.go('/add');
      return;
    }
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('放弃本次录题？'),
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
    if (shouldDiscard != true) return;
    await ref.read(questionRepositoryProvider).delete(current.id);
    await ref.read(captureServiceProvider).discardManagedImage(current.imagePath);
    if (!mounted) return;
    ref.read(captureSessionProvider.notifier).endSession();
    context.go('/add');
  }

  Future<void> _retakeCapture() async {
    final current = ref.read(currentQuestionProvider);
    if (current == null) {
      if (mounted) context.go('/add');
      return;
    }
    await ref.read(questionRepositoryProvider).delete(current.id);
    await ref.read(captureServiceProvider).discardManagedImage(current.imagePath);
    if (!mounted) return;
    ref.read(captureSessionProvider.notifier).endSession();
    context.go('/add');
  }

  void _beginRecognition() {
    final session = ref.read(captureSessionProvider.notifier);
    final phase = ref.read(captureSessionProvider).phase;
    if (phase == CaptureAnalysisPhase.imageSelected ||
        phase == CaptureAnalysisPhase.cropping) {
      session.beginRecognition();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ref.read(captureSessionProvider.notifier).restoreDraft();
    _maybeDetectQuality();
  }

  Future<void> _maybeDetectQuality() async {
    if (_detecting || _qualityResult != null) return;
    final current = ref.read(currentQuestionProvider);
    final imagePath = current?.imagePath;
    if (imagePath == null || imagePath.isEmpty) {
      if (mounted) {
        setState(() => _qualityError = '未找到原图，请返回录题入口重新拍摄或选图。');
      }
      return;
    }
    if (!File(imagePath).existsSync()) {
      if (mounted) {
        setState(() => _qualityError = '原图文件已失效，请返回录题入口重新拍摄或选图。');
      }
      return;
    }

    setState(() {
      _detecting = true;
      _qualityError = null;
    });
    try {
      final result = await detectImageQuality(imagePath);
      if (!mounted) return;
      setState(() {
        _qualityResult = result;
        _detecting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _detecting = false;
        _qualityError = '无法完成图片质量检查：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(currentQuestionProvider);
    final imagePath = current?.imagePath;
    final showWarning = _qualityResult != null &&
        !_qualityResult!.isAcceptable &&
        !_warningDismissed;

    return Scaffold(
      appBar: AppBar(
        title: const Text('题目预览'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          tooltip: '返回录题入口',
          onPressed: () => context.go('/add'),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(CupertinoIcons.trash),
            tooltip: '放弃本次录题',
            onPressed: _discardCapture,
          ),
        ],
      ),
      body: AppPage(
        maxWidth: AppContentWidth.wide,
        padding: EdgeInsets.zero,
        child: Column(
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.md,
                AppSpace.lg,
                AppSpace.sm,
              ),
              child: AppTaskFlow(
                steps: <String>['拍摄质量', '题目切分', '文字确认', '开始分析'],
                currentStep: 0,
              ),
            ),
            _buildQualityOverview(),
            if (showWarning) _buildQualityWarning(_qualityResult!.issues),
            Expanded(
              child: imagePath != null && File(imagePath).existsSync()
                  ? Container(
                      margin: const EdgeInsets.fromLTRB(
                        AppSpace.lg,
                        AppSpace.sm,
                        AppSpace.lg,
                        AppSpace.md,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLow,
                        borderRadius: BorderRadius.circular(AppRadius.large),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Center(
                        child: InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 4.0,
                          child: CachedQuestionImage(
                            imagePath,
                            fit: BoxFit.contain,
                            highRes: true,
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        '未选择图片',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.go('/capture/crop'),
                  child: const Text('重新框选'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _detecting || _qualityResult == null ||
                          _qualityError != null ||
                          _qualityResult!.hasBlockingIssue
                      ? null
                      : () {
                          _beginRecognition();
                          context.go('/analysis/loading');
                        },
                  child: Text(_qualityResult?.hasBlockingIssue == true
                      ? '请先重拍'
                      : _qualityResult?.isAcceptable == true
                          ? '进入题目切分'
                          : '继续使用并切分'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQualityOverview() {
    final result = _qualityResult;
    final scheme = Theme.of(context).colorScheme;
    final checking = _detecting || result == null;
    final qualityUnavailable = _qualityError != null;
    final acceptable = result?.isAcceptable == true;
    final accent = checking
        ? scheme.primary
        : acceptable
            ? AppColors.success
            : AppColors.accentAmber;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  child: Icon(
                    checking
                        ? CupertinoIcons.viewfinder
                        : acceptable
                            ? CupertinoIcons.checkmark_shield_fill
                            : CupertinoIcons.exclamationmark_triangle_fill,
                    color: accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        qualityUnavailable
                            ? '质量检查失败'
                            : checking
                                ? '正在检查拍摄质量'
                                : acceptable
                                    ? '画面适合识别'
                                    : '建议先改善画面',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        qualityUnavailable
                            ? _qualityError!
                            : checking
                                ? '正在检查清晰度、光线、页面完整性和隐私风险。'
                                : acceptable
                                    ? '清晰度、光线与页面完整性均已通过。'
                                    : _warningSummary(result?.issues ?? const []),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                AppTag(
                  label: qualityUnavailable
                      ? '检查失败'
                      : checking
                          ? '检查中'
                          : acceptable
                              ? '可继续'
                              : '需注意',
                  useThemeTone: true,
                  themeTone: qualityUnavailable
                      ? AppTagTone.warning
                      : checking
                          ? AppTagTone.primary
                          : acceptable
                              ? AppTagTone.success
                              : AppTagTone.warning,
                ),
              ],
            ),
            if (result != null) ...<Widget>[
              const SizedBox(height: AppSpace.md),
              Row(
                children: <Widget>[
                  _QualityMetric(
                    label: '清晰度',
                    value: '${(result.sharpnessScore * 100).round()}%',
                  ),
                  _QualityMetric(
                    label: '亮度',
                    value: '${(result.brightnessScore * 100).round()}%',
                  ),
                  _QualityMetric(
                    label: '最短边',
                    value: '${result.minDimensionPixels}px',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQualityWarning(List<ImageQualityIssue> issues) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark
        ? AppColors.accentAmber.withValues(alpha: 0.14)
        : AppColors.accentAmberContainerLight;
    final borderColor = AppColors.accentAmber.withValues(alpha: 0.4);

    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, 0),
      padding: const EdgeInsets.fromLTRB(AppSpace.md, 10, AppSpace.sm, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(CupertinoIcons.exclamationmark_triangle,
                color: AppColors.accentAmber, size: 20),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ...issues.map((issue) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• ${_warningText(issue)}',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    )),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _retakeCapture,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      '重拍',
                      style: TextStyle(
                        color: AppColors.accentAmber,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 16,
              onPressed: () => setState(() => _warningDismissed = true),
              icon: Icon(
                CupertinoIcons.xmark,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _warningText(ImageQualityIssue? issue) {
    switch (issue) {
      case ImageQualityIssue.blurry:
        return '图片可能模糊，建议重拍以提升识别准确率';
      case ImageQualityIssue.tooDark:
        return '光线过暗，建议在明亮环境重拍';
      case ImageQualityIssue.tooBright:
        return '光线过亮/反光，建议调整角度重拍';
      case ImageQualityIssue.lowResolution:
        return '分辨率较低，可能识别不准，建议靠近拍摄';
      case ImageQualityIssue.glare:
        return '检测到局部反光，建议关闭闪光灯并调整拍摄角度';
      case ImageQualityIssue.unevenShadow:
        return '页面光照不均或有阴影，建议移开手部并从正上方补光';
      case ImageQualityIssue.perspectiveDistortion:
        return '页面透视变形明显，建议让镜头与纸面保持平行';
      case ImageQualityIssue.possiblePageCurvature:
        return '书页可能弯曲，建议压平页面后重拍';
      case ImageQualityIssue.occluded:
        return '题目主体可能被手指或物体遮挡，必须移开遮挡后重拍';
      case ImageQualityIssue.contentCutOff:
        return '文字或图形可能贴边截断，必须完整拍入题目后重拍';
      case ImageQualityIssue.possiblePersonalInfo:
        return '页眉可能含姓名、学校等信息，请检查并裁剪或遮盖';
      case null:
        return '';
    }
  }

  String _warningSummary(List<ImageQualityIssue> issues) {
    if (issues.isEmpty) return '';
    return issues.map(_warningText).join('；');
  }
}

class _QualityMetric extends StatelessWidget {
  const _QualityMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: <Widget>[
            Text(
              value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
}

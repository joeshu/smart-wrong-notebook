import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/capture_analysis_state.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/data/files/image_fingerprint.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

class ImageCropScreen extends ConsumerStatefulWidget {
  const ImageCropScreen({super.key});

  @override
  ConsumerState<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends ConsumerState<ImageCropScreen> {
  bool _cropping = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startCrop();
    });
  }

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

  Future<void> _startCrop() async {
    if (_starting || _cropping) return;
    final session = ref.read(captureSessionProvider.notifier);
    final current = session.restoreDraft() ?? ref.read(currentQuestionProvider);
    if (current == null) {
      if (mounted) context.go('/add');
      return;
    }

    if (ref.read(captureSessionProvider).phase ==
        CaptureAnalysisPhase.imageSelected) {
      session.beginCropping();
    }

    String? replacementPath;
    _starting = true;
    setState(() => _cropping = true);

    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: current.imagePath,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 82,
        maxWidth: 2048,
        maxHeight: 2048,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '框选题目',
            toolbarColor: const Color(0xFF6366F1),
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: '框选题目',
            cancelButtonTitle: '取消',
            doneButtonTitle: '完成',
          ),
        ],
      );

      if (!mounted) return;

      if (croppedFile == null) {
        // 取消裁剪不等于放弃录题：返回预览页，保留草稿供用户重试或明确删除。
        if (mounted) {
          setState(() {
            _cropping = false;
            _starting = false;
          });
          context.go('/capture/correction');
        }
        return;
      }

      // Save cropped image
      final storage = ref.read(imageStorageServiceProvider);
      final savedPath = await storage.saveImage(File(croppedFile.path));
      replacementPath = savedPath;
      final fingerprint =
          await ImageFingerprintCodec.fromFile(File(savedPath));
      final perceptual =
          await ImageFingerprintCodec.perceptualFromFile(File(savedPath));

      // Create new question with cropped image path. The original capture
      // fingerprint is intentionally replaced: model reuse must match the
      // final cropped region, not merely the full camera photo.
      final newRecord = QuestionRecord.draft(
        id: current.id,
        imagePath: savedPath,
        subject: current.subject,
        recognizedText: '',
      ).copyWith(
        contentStatus: ContentStatus.processing,
        tags: ImageFingerprintCodec.writePerceptual(
          ImageFingerprintCodec.write(current.tags, fingerprint),
          perceptual,
        ),
      );
      await ref.read(questionRepositoryProvider).saveDraft(newRecord);
      session.setCurrentQuestion(newRecord);
      // The managed full-frame capture is no longer referenced after the
      // cropped replacement succeeds.
      await ref.read(captureServiceProvider).discardManagedImage(current.imagePath);

      if (mounted) {
        context.go('/capture/correction');
      }
    } catch (e) {
      if (replacementPath != null) {
        await ref
            .read(captureServiceProvider)
            .discardManagedImage(replacementPath!);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('裁剪失败: $e')),
        );
        context.go('/capture/correction');
      }
    } finally {
      if (mounted) setState(() => _cropping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('框选题目'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          tooltip: '返回预览',
          onPressed: () => context.go('/capture/correction'),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(CupertinoIcons.trash),
            tooltip: '放弃本次录题',
            onPressed: _cropping ? null : _discardCapture,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: _cropping
              ? const AppLoadingState(label: '正在打开裁剪工具...')
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text('准备裁剪...'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _startCrop,
                        child: const Text('重新裁剪'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

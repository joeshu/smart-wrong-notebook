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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startCrop();
    });
  }

  Future<void> _startCrop() async {
    final session = ref.read(captureSessionProvider.notifier);
    final current = session.restoreDraft() ?? ref.read(currentQuestionProvider);
    if (current == null) {
      if (mounted) context.go('/');
      return;
    }

    if (ref.read(captureSessionProvider).phase ==
        CaptureAnalysisPhase.imageSelected) {
      session.beginCropping();
    }

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
        // Cancelling the native cropper is an explicit cancellation. Do not
        // silently submit the uncropped camera image for recognition.
        await ref.read(questionRepositoryProvider).delete(current.id);
        await ref.read(captureServiceProvider).discardManagedImage(current.imagePath);
        session.cancel();
        session.clearCurrentQuestion();
        if (mounted) context.go('/add');
        return;
      }

      // Save cropped image
      final storage = ref.read(imageStorageServiceProvider);
      final savedPath = await storage.saveImage(File(croppedFile.path));
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

      if (ref.read(captureSessionProvider).phase ==
          CaptureAnalysisPhase.cropping) {
        session.beginRecognition();
      }

      if (mounted) {
        context.go('/analysis/loading');
      }
    } catch (e) {
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
          onPressed: () => context.go('/'),
        ),
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

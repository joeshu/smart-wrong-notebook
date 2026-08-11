import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/data/files/image_fingerprint.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/capture_analysis_state.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_review.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_import_session.dart';
import 'package:smart_wrong_notebook/src/domain/services/ai_analysis_review_policy.dart';
import 'package:smart_wrong_notebook/src/domain/services/analysis_result_submission_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/recognition_confirmation_policy.dart';
import 'package:smart_wrong_notebook/src/shared/utils/composite_worksheet_detector.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_layout.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_motion.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/stage_indicator.dart';

class AnalysisLoadingScreen extends ConsumerStatefulWidget {
  const AnalysisLoadingScreen({super.key});

  @override
  ConsumerState<AnalysisLoadingScreen> createState() =>
      _AnalysisLoadingScreenState();
}

class _AnalysisLoadingScreenState extends ConsumerState<AnalysisLoadingScreen> {
  static const _boundaryCheckedTag = '__system_question_boundary_checked';
  String? _errorMessage;
  String? _debugInfo;
  int _step = 0;
  String? _progressText;
  // 是否由极速模式进入（拍照后跳过裁剪/校对直接进入解析）。
  // 失败时若为 true，则提供"重新裁剪 / 重新拍照 / 取消"按钮。
  bool _isQuickCapture = false;
  // 是否处于"超时可恢复"状态。Dio 自身超时会抛 AiAnalysisException 走通用失败路径；
  // 这里再加一层总超时保险，避免极端慢响应让加载页无限旋转。
  bool _isTimeout = false;
  Timer? _timeoutTimer;
  // Future 本身不一定支持取消；令牌让超时后的旧请求失去提交资格。
  int _analysisToken = 0;
  bool _analysisRunning = false;
  // 上层总超时阈值。超过 Dio receiveTimeout (240s) 即不合理，给一个更早的兜底。
  static const _analysisTimeout = Duration(seconds: 120);

  final _steps = const ['提取题目结构', '确认题目边界', '执行 AI 分析', '校验并保存'];

  @override
  void initState() {
    super.initState();
    // 先读取极速模式标记，再启动解析流程；避免 catch 块读到默认 false
    // 时显示错误的回退按钮组。
    _initQuickCaptureThenAnalyze();
  }

  Future<void> _initQuickCaptureThenAnalyze() async {
    await _loadQuickCaptureFlag();
    if (!mounted) return;
    await _runAnalysis();
  }

  Future<void> _loadQuickCaptureFlag() async {
    try {
      final enabled = await ref
          .read(settingsRepositoryProvider)
          .isQuickCaptureEnabled();
      if (!mounted) return;
      setState(() => _isQuickCapture = enabled);
    } catch (_) {
      // 读取失败时按非极速模式处理（默认 false）。
    }
  }

  void _reportStage(int step, String message) {
    if (!mounted) return;
    setState(() {
      _step = step.clamp(0, _steps.length - 1).toInt();
      _progressText = message;
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _analysisToken++;
    _analysisRunning = false;
    super.dispose();
  }

  void _cancelCaptureSession() {
    final phase = ref.read(captureSessionProvider).phase;
    const active = <CaptureAnalysisPhase>{
      CaptureAnalysisPhase.imageSelected,
      CaptureAnalysisPhase.cropping,
      CaptureAnalysisPhase.recognizing,
      CaptureAnalysisPhase.analyzing,
      CaptureAnalysisPhase.needsConfirmation,
      CaptureAnalysisPhase.retryable,
    };
    if (active.contains(phase)) {
      ref.read(captureSessionProvider.notifier).cancel();
    }
    _timeoutTimer?.cancel();
    _analysisToken++;
    _analysisRunning = false;
  }

  /// Leaves the loading route without discarding the current capture.
  ///
  /// A route change is not an explicit cancel: the image and the latest
  /// recognition/correction snapshot must remain available when the user
  /// comes back. The token still invalidates callbacks from the old request.
  void _leaveAnalysis(String route) {
    _clearTimeoutTimer();
    _analysisToken++;
    _analysisRunning = false;
    if (mounted) context.go(route);
  }

  /// Starts a genuinely new capture. This is deliberately different from
  /// leaving the page: the old request and its in-memory draft must not be
  /// allowed to win after the next photo is selected.
  void _replaceCaptureWithNewPhoto() {
    _cancelCaptureSession();
    ref.read(captureSessionProvider.notifier).endSession();
    if (mounted) context.go('/');
  }

  /// 启动总超时计时器。若超过 [_analysisTimeout] 仍未完成，强制进入
  /// 超时可恢复状态，避免 Dio 慢响应导致加载页无限旋转。
  void _startTimeoutTimer() {
    _timeoutTimer?.cancel();
    final token = _analysisToken;
    _timeoutTimer = Timer(_analysisTimeout, () {
      if (!mounted) return;
      // 已经在错误/成功态时不再覆盖。
      if (_errorMessage != null || token != _analysisToken) return;
      _handleTimeout(token);
    });
  }

  Future<void> _handleTimeout(int token) async {
    if (!mounted || token != _analysisToken) return;
    final timeoutToken = ++_analysisToken;
    _analysisRunning = false;
    const message = '识别超时，可重试当前引擎或切换到其他识别引擎。';
    final current = ref.read(currentQuestionProvider);
    if (current != null) {
      final failedDraft = current.copyWith(
        contentStatus: ContentStatus.analysisFailed,
        lastAnalysisError: message,
      );
      try {
        await ref.read(questionRepositoryProvider).saveDraft(failedDraft);
        if (mounted && timeoutToken == _analysisToken) {
          ref.read(captureSessionProvider.notifier).updateCurrentQuestion(failedDraft);
          _markRetryableCaptureSession(message, CaptureFailureKind.timeout);
          invalidateQuestionList(ref);
        }
      } catch (_) {
        // 页面仍保留恢复入口；持久化失败不应掩盖超时。
      }
    }
    if (!mounted) return;
    setState(() {
      _isTimeout = true;
      _errorMessage = '$message\n\n原图和已校对题干已保留，可重试、切换引擎，或稍后手动补充。';
    });
  }

  void _clearTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  /// Phase 4-C：把 AI 分析返回的知识点文本映射到受控知识点树。
  /// 匹配成功的会创建结构化关联；未匹配的进入待确认队列，供用户在
  /// 错题详情页手动映射。后台执行，失败仅记录日志，不阻塞分析流程。
  Future<void> _mapAnalysisKnowledgePoints(QuestionRecord question) async {
    if (question.aiKnowledgePoints.isEmpty) return;
    try {
      final mapping = ref.read(knowledgePointMappingServiceProvider);
      await mapping.createLinksForQuestion(
        questionId: question.id,
        knowledgePointTexts: question.aiKnowledgePoints,
      );
      invalidatePendingKnowledgePoints(ref);
    } catch (e) {
      debugPrint('[AnalysisLoading] map knowledge points failed: $e');
    }
  }

  Future<void> _runAnalysis() async {
    if (_analysisRunning) return;
    _analysisRunning = true;
    final token = ++_analysisToken;
    final current = ref.read(currentQuestionProvider);
    if (current == null) {
      _analysisRunning = false;
      if (mounted) context.go('/');
      return;
    }

    _advanceCaptureSessionToAnalysis();

    // The provider is navigation context, not restart recovery. Persist an
    // in-progress snapshot before the first OCR/AI await so a killed process
    // can be normalized on the next launch without losing corrected text.
    if (current.analysisResult == null &&
        current.contentStatus != ContentStatus.analysisFailed) {
      final processing = current.copyWith(
        contentStatus: ContentStatus.processing,
      );
      try {
        await ref.read(questionRepositoryProvider).saveDraft(processing);
        if (!mounted || token != _analysisToken) return;
      } catch (_) {
        // The failure path below still preserves the in-memory working snapshot.
      }
    }

    // 重置超时态并启动总超时计时器。
    if (_isTimeout || _errorMessage != null) {
      setState(() {
        _isTimeout = false;
        _errorMessage = null;
        _progressText = null;
        _step = 0;
      });
    }
    _startTimeoutTimer();

    if (current.analysisResult != null &&
        (current.contentStatus == ContentStatus.ready ||
            current.contentStatus == ContentStatus.needsConfirmation)) {
      try {
        final persisted = await AnalysisResultSubmissionService(
          ref.read(questionRepositoryProvider),
        ).submit(current);
        if (!mounted || token != _analysisToken) return;
        ref.read(captureSessionProvider.notifier).updateCurrentQuestion(persisted);
        _completeCaptureSession(persisted.contentStatus);
        _clearTimeoutTimer();
        context.go('/analysis/result');
      } catch (error) {
        if (!mounted || token != _analysisToken) return;
        _analysisRunning = false;
        _clearTimeoutTimer();
        setState(() => _errorMessage =
            '分析结果保存失败：$error\n\n可从“校验并保存”阶段继续。');
      }
      return;
    }

    var working = current;
    QuestionRecord? submitted;
    var debugInfo = '';
    try {
      final reusable = await _findReusableLocalAnalysis(current);
      if (!mounted || token != _analysisToken) return;
      if (reusable != null) {
        try {
          final persisted = await AnalysisResultSubmissionService(
            ref.read(questionRepositoryProvider),
          ).submit(reusable);
          submitted = persisted;
          if (!mounted || token != _analysisToken) return;
          ref.read(captureSessionProvider.notifier).updateCurrentQuestion(persisted);
          _completeCaptureSession(persisted.contentStatus);
          _clearTimeoutTimer();
          context.go('/analysis/result');
        } catch (error) {
          if (!mounted || token != _analysisToken) return;
          _analysisRunning = false;
          _clearTimeoutTimer();
          setState(() => _errorMessage = '复用结果保存失败：$error\n\n请重试保存；当前题目仍保留在本页。');
        }
        _analysisRunning = false;
        return;
      }

    // 检查配置并显示调试信息
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final config = await settingsRepo.getAiProviderConfig();
    if (!mounted || token != _analysisToken) return;

    debugInfo = '配置状态:\n';
    debugInfo += '- 配置对象: ${config != null ? "存在" : "为空"}\n';
    if (config != null) {
      debugInfo +=
          '- baseUrl: ${config.baseUrl.isNotEmpty ? config.baseUrl : "(空)"}\n';
      debugInfo +=
          '- model: ${config.model.isNotEmpty ? config.model : "(空)"}\n';
      debugInfo +=
          '- apiKey: ${config.apiKey.isNotEmpty ? "[已设置(${config.apiKey.length}字符)]" : "(空)"}\n';
    } else {
      debugInfo += '\n请到设置中配置 AI 服务';
    }

    setState(() => _debugInfo = debugInfo);

      final service = ref.read(aiAnalysisServiceProvider);

      final shouldAnalyzeImageDirectly = _shouldAnalyzeImageDirectly(working);
      if (working.normalizedQuestionText.isEmpty &&
          (!shouldAnalyzeImageDirectly ||
              working.tags.contains(RecognitionConfirmationPolicy.requiredTag))) {
        _reportStage(0, '正在从原图提取题干、选项与学生答案…');
        // 录入模式由 capture_entry_sheet 的模式选择器决定，默认 printed。
        final captureMode = ref.read(captureModeProvider);
        final extraction = await service.extractQuestionStructure(
          subjectName: working.subject.name,
          imagePath: working.imagePath,
          textHint: working.extractedQuestionText,
          mode: captureMode,
        );
        if (!mounted || token != _analysisToken) return;
        working = working.copyWith(
          extractedQuestionText: extraction.extractedQuestionText,
          normalizedQuestionText: extraction.normalizedQuestionText.isNotEmpty
              ? extraction.normalizedQuestionText
              : extraction.extractedQuestionText,
          subject: extraction.subject ?? working.subject,
          splitResult: extraction.splitResult,
          studentAnswer: extraction.studentAnswer,
        );
        try {
          await ref.read(questionRepositoryProvider).saveDraft(working);
          if (!mounted || token != _analysisToken) return;
        } catch (_) {
          // Keep the latest OCR snapshot for the retryable failure path.
        }
        ref.read(captureSessionProvider.notifier).updateCurrentQuestion(working);
      }

      // Recognition confirmation is a hard gate before problem solving. Worksheet
      // candidates have already passed the shared region workbench and therefore
      // continue through the automatic queue without a duplicate prompt.
      final worksheetAuto = ref.read(worksheetAutoAnalyzeProvider);
      if (working.analysisResult == null &&
          working.tags.contains(RecognitionConfirmationPolicy.requiredTag) &&
          working.contentStatus == ContentStatus.processing &&
          !worksheetAuto) {
        final autoConfirm = (await SharedPreferences.getInstance())
                .getBool('recognition_high_confidence_auto_confirm') ??
            false;
        final text = working.normalizedQuestionText.trim();
        final formulaMarkers = RegExp(r'\$').allMatches(text).length;
        final safeHighConfidence = autoConfirm &&
            (working.ocrConfidence ?? 0) >= .85 &&
            text.isNotEmpty &&
            formulaMarkers.isEven &&
            File(working.imagePath).existsSync();
        if (!safeHighConfidence) {
          final pending = working.copyWith(
            contentStatus: ContentStatus.needsConfirmation,
          );
          await ref.read(questionRepositoryProvider).saveDraft(pending);
          ref.read(currentQuestionProvider.notifier).state = pending;
          _markCaptureConfirmation();
          _clearTimeoutTimer();
          if (mounted) context.go('/capture/recognition-confirmation');
          return;
        }
        working = working.copyWith(
          contentStatus: ContentStatus.analyzing,
          tags: working.tags
              .where((tag) => tag != RecognitionConfirmationPolicy.requiredTag)
              .toList(growable: false),
        );
        ref.read(captureSessionProvider.notifier).updateCurrentQuestion(working);
      }

      // Mark the AI phase durably before any remote request. If the process is
      // killed during splitting or analysis, startup recovery can expose retry
      // instead of leaving a stale processing/analyzing record.
      if (working.analysisResult == null &&
          working.contentStatus != ContentStatus.analyzing) {
        working = working.copyWith(contentStatus: ContentStatus.analyzing);
        await ref.read(questionRepositoryProvider).saveDraft(working);
        if (!mounted || token != _analysisToken) return;
        ref.read(captureSessionProvider.notifier).updateCurrentQuestion(working);
      }

      if (!(working.splitResult?.hasMultipleCandidates ?? false) &&
          !working.tags.contains(_boundaryCheckedTag)) {
        _reportStage(1, '正在检查题目结构与多题边界…');
        final splitSeed = _splitSeedText(working);
        if (splitSeed.isNotEmpty) {
          final splitResult = await service.splitQuestionCandidates(
            text: splitSeed,
            subjectName: working.subject.name,
          );
          working = working.copyWith(
            splitResult: splitResult,
            tags: <String>{...working.tags, _boundaryCheckedTag}.toList(),
          );
          await ref.read(questionRepositoryProvider).saveDraft(working);
          if (!mounted || token != _analysisToken) return;
          ref.read(captureSessionProvider.notifier).updateCurrentQuestion(working);
        }
      }

      var candidateSnapshots = <CandidateAnalysisPayload>[];
      CandidateAnalysisPayload? firstSuccessfulCandidate;
      if (working.splitResult?.hasMultipleCandidates ?? false) {
        final totalCandidates = working.splitResult!.candidates.length;
        if (mounted) {
          setState(() {
                _progressText = '正在并行分析 $totalCandidates 道题...';
          });
        }
        candidateSnapshots = await service.analyzeSplitCandidates(
          questionId: working.id,
          subjectName: working.subject.name,
          splitResult: working.splitResult!,
          imagePath: working.imagePath,
          onProgress: (completed, total, {int failed = 0}) {
            if (mounted) {
              setState(() {
                final suffix = failed > 0 ? '（$failed题失败）' : '';
                _progressText = '已完成 $completed/$total题分析$suffix';
              });
            }
          },
        );
        if (!mounted || token != _analysisToken) return;
        firstSuccessfulCandidate = candidateSnapshots
            .where((payload) => payload.isSuccessful)
            .cast<CandidateAnalysisPayload?>()
            .firstWhere((payload) => payload != null, orElse: () => null);
        if (firstSuccessfulCandidate == null) {
          throw AiAnalysisException('多题解析全部失败，请重试；系统不会保存缺少解析的子题。');
        }
      }
      final shouldUseImageForAnalysis =
          shouldAnalyzeImageDirectly || _shouldUseImageForAnalysis(working);
      final textForAnalysis = shouldUseImageForAnalysis
          ? working.extractedQuestionText
          : working.correctedText;
      if (mounted && firstSuccessfulCandidate == null) {
        setState(() {
          _progressText = shouldUseImageForAnalysis
              ? '正在使用视觉模型理解题图...'
              : '正在使用文字模型分析题目...';
        });
      }

      AnalysisResult analysis;
      _reportStage(2, firstSuccessfulCandidate != null
          ? '正在汇总各题真实分析结果…'
          : '正在调用 AI 生成解析与错因…');
      if (firstSuccessfulCandidate != null) {
        analysis = firstSuccessfulCandidate.analysisResult!;
      } else {
        try {
          analysis = await service.analyzeExtractedQuestion(
            correctedText: textForAnalysis,
            subjectName: working.subject.name,
            imagePath: shouldUseImageForAnalysis ? working.imagePath : null,
            studentAnswer: working.studentAnswer ?? '',
          );
        } on AiAnalysisException {
          // 视觉模型失败时，已校对的文字题仍有可用价值。退回文本分析，
          // 既减少一次失败阻断，也避免为纯文本题反复发送原图。
          final fallbackText = working.correctedText.trim();
          if (!shouldUseImageForAnalysis || fallbackText.isEmpty) rethrow;
          if (mounted) {
            setState(() => _progressText = '图片分析失败，正在改用文字解析...');
          }
          analysis = await service.analyzeExtractedQuestion(
            correctedText: fallbackText,
            subjectName: working.subject.name,
            imagePath: null,
            studentAnswer: working.studentAnswer ?? '',
          );
        }
      }

      // AI 重构题干独立存到 aiReconstructedText，不再覆盖 normalizedQuestionText
      // （用户校对文本）。详情页据此展示三段对照：OCR 原文 / 用户校对 / AI 重构。
      // 保留 extractedQuestionText（OCR 原文）以便详情页展示 OCR vs 校对后对照。
      String? aiReconstructed;
      if (firstSuccessfulCandidate == null &&
          analysis.reconstructedQuestionText.trim().isNotEmpty) {
        aiReconstructed = analysis.reconstructedQuestionText;
      }

      final generatedExercises = firstSuccessfulCandidate?.savedExercises ??
          (analysis is ParsedAnalysisResult
              ? service.extractGeneratedExercisesFromContent(
                  analysis.rawContent,
                  questionId: working.id,
                  sourceQuestionText: working.correctedText,
                )
              : service.extractGeneratedExercises(
                  analysis,
                  questionId: working.id,
                  sourceQuestionText: working.correctedText,
                ));

      _reportStage(3, '正在校验字段置信度并写入安全结果…');
      const reviewPolicy = AiAnalysisReviewPolicy();
      final hasStudentAnswer = (working.studentAnswer ?? '').trim().isNotEmpty;
      var reviewDecision = reviewPolicy.evaluate(
        analysis,
        hasStudentAnswer: hasStudentAnswer,
      );

      final reviewedCandidates = candidateSnapshots.map((payload) {
        final candidateAnalysis = payload.analysisResult;
        if (candidateAnalysis == null) {
          return CandidateAnalysisSnapshot(
            candidateId: payload.candidateId,
            order: payload.order,
            questionText: payload.questionText,
            analysisResult: null,
            savedExercises: payload.savedExercises,
            subject: payload.subject,
            aiTags: payload.aiTags,
            aiKnowledgePoints: payload.aiKnowledgePoints,
            status: payload.status,
            errorMessage: payload.errorMessage,
          );
        }
        final decision = reviewPolicy.evaluate(
          candidateAnalysis,
          hasStudentAnswer: hasStudentAnswer,
        );
        final reviewed = candidateAnalysis.copyWith(
          reviewDecision: decision,
          pipeline: reviewPolicy.completedPipeline(decision),
        );
        return CandidateAnalysisSnapshot(
          candidateId: payload.candidateId,
          order: payload.order,
          questionText: payload.questionText,
          analysisResult: reviewed,
          savedExercises: payload.savedExercises,
          subject: payload.subject,
          aiTags: payload.aiTags,
          aiKnowledgePoints: payload.aiKnowledgePoints,
          status: payload.status,
          errorMessage: payload.errorMessage,
        );
      }).toList(growable: false);

      final candidateReviews = reviewedCandidates
          .map((candidate) => candidate.analysisResult?.reviewDecision)
          .whereType<AiAnalysisReviewDecision>()
          .where((decision) => decision.requiresConfirmation)
          .toList(growable: false);
      if (candidateReviews.isNotEmpty) {
        reviewDecision = AiAnalysisReviewDecision(
          disposition: AiAnalysisReviewDisposition.needsConfirmation,
          fields: <String>{
            ...reviewDecision.fields,
            for (final decision in candidateReviews) ...decision.fields,
          }.toList(growable: false)..sort(),
          reasons: <String>{
            ...reviewDecision.reasons,
            for (final decision in candidateReviews) ...decision.reasons,
          }.toList(growable: false),
          evaluatedAt: DateTime.now(),
        );
      }
      final reviewedAnalysis = analysis.copyWith(
        reviewDecision: reviewDecision,
        pipeline: reviewPolicy.completedPipeline(reviewDecision),
      );
      final contentStatus = reviewDecision.requiresConfirmation
          ? ContentStatus.needsConfirmation
          : ContentStatus.ready;

      // 总超时或页面重入后，旧请求不得覆盖当前重试结果。
      if (!mounted || token != _analysisToken) return;
      final updated = working
          .copyWith(
            contentStatus: contentStatus,
            analysisResult: reviewedAnalysis,
            savedExercises: generatedExercises,
            subject: reviewedAnalysis.subject ?? working.subject,
            aiTags: reviewedAnalysis.aiTags,
            aiKnowledgePoints: reviewedAnalysis.knowledgePoints,
            aiReconstructedText: aiReconstructed,
            candidateAnalyses: reviewedCandidates,
          )
          .withLastAnalysisError(null);
      // Persist the canonical result before replacing the queue item or
      // navigating away. A failed write must remain on this page so retry is
      // possible; provider state alone is not durable.
      try {
        submitted = await AnalysisResultSubmissionService(
          ref.read(questionRepositoryProvider),
        ).submit(updated);
      } catch (error) {
        if (!mounted || token != _analysisToken) return;
        ref.read(captureSessionProvider.notifier).updateCurrentQuestion(updated);
        _analysisRunning = false;
        _clearTimeoutTimer();
        setState(() => _errorMessage = '分析结果保存失败：$error\n\n请重试保存；当前结果仍保留在本页。');
        return;
      }
      if (!mounted || token != _analysisToken) return;
      final persisted = submitted!;
      ref.read(captureSessionProvider.notifier).updateCurrentQuestion(persisted);
      _completeCaptureSession(persisted.contentStatus);
      await _replaceWorksheetQueueItem(persisted);
      _clearTimeoutTimer();

      // Only trusted analyses enter the controlled knowledge tree automatically.
      // Low-confidence results stay isolated until the user confirms them.
      if (!reviewDecision.requiresConfirmation) {
        _mapAnalysisKnowledgePoints(persisted);
      }

      if (mounted) {
        final wasAutoQueue = ref.read(worksheetAutoAnalyzeProvider);
        if (_continueWorksheetQueue(persisted)) return;
        _analysisRunning = false;
        if (wasAutoQueue) {
          context.go('/worksheet/import');
          return;
        }
        context.go('/analysis/result');
      }
    } on AiAnalysisException catch (e) {
      if (token != _analysisToken) return;
      _analysisRunning = false;
      _clearTimeoutTimer();
      // AI 不可用时也必须保留原图和用户已校对的题干。saveDraft 是幂等
      // upsert，既覆盖同 ID 的处理中草稿，也兼容首次保存。
      // 用 analysisFailed 而非 failed，区分"识别失败"与"分析失败"，
      // 并持久化 friendlyAiErrorMessage 输出，让详情页能展示具体失败原因。
      final friendlyError = friendlyAiErrorMessage(e);
      final failedDraft = working
          .copyWith(
            contentStatus: ContentStatus.analysisFailed,
            lastAnalysisError: friendlyError,
          );
      try {
        await ref.read(questionRepositoryProvider).saveDraft(failedDraft);
        if (mounted && token == _analysisToken) {
          ref.read(captureSessionProvider.notifier).updateCurrentQuestion(failedDraft);
          _markRetryableCaptureSession(friendlyError, CaptureFailureKind.ai);
          await _replaceWorksheetQueueItem(failedDraft);
          invalidateQuestionList(ref);
        }
      } catch (_) {
        // 持久化异常不能掩盖原始 AI 错误；错误页仍保留重试入口。
      }
      if (mounted) {
        if (_continueWorksheetQueue(failedDraft)) return;
        // 极速模式下没有"已校对题干"，文案需调整；否则保留原文案。
        final suffix = _isQuickCapture
            ? '原图已保存到错题本，可重试、切换引擎，或重新裁剪/重新拍照。'
            : '原图和已校对题干已保存到错题本，可重试、切换引擎，或稍后手动补充。';
        setState(() {
          _isTimeout = false;
          _errorMessage = '$friendlyError\n\n$suffix';
          _debugInfo = debugInfo;
        });
      }
    } catch (error, stackTrace) {
      // OCR, file, parsing, and repository implementations can throw outside
      // the AI exception boundary. Keep those failures recoverable too, but do
      // not relabel a result that was already durably submitted.
      debugPrint('[AnalysisLoading] unexpected analysis failure: $error\n$stackTrace');
      if (token != _analysisToken) return;
      _analysisRunning = false;
      _clearTimeoutTimer();
      if (submitted != null) {
        if (mounted) {
          setState(() {
            _errorMessage = '分析结果已保存，但后续队列更新失败，请返回题库检查。';
            _debugInfo = debugInfo;
          });
        }
        return;
      }
      // Unknown parser/file/storage failures share the recovery surface, but
      // retain a truthful failure kind instead of pretending to be AI errors.
      const friendlyError = '分析过程发生异常，请重试';
      final failedDraft = working.copyWith(
        contentStatus: ContentStatus.analysisFailed,
        lastAnalysisError: friendlyError,
      );
      try {
        await ref.read(questionRepositoryProvider).saveDraft(failedDraft);
        if (mounted && token == _analysisToken) {
          ref.read(captureSessionProvider.notifier).updateCurrentQuestion(failedDraft);
          _markRetryableCaptureSession(friendlyError, CaptureFailureKind.unknown);
          await _replaceWorksheetQueueItem(failedDraft);
          invalidateQuestionList(ref);
        }
      } catch (persistenceError, persistenceStack) {
        debugPrint('[AnalysisLoading] failed to persist unexpected failure: '
            '$persistenceError\n$persistenceStack');
      }
      if (mounted && token == _analysisToken) {
        setState(() {
          _isTimeout = false;
          _errorMessage = '$friendlyError\n\n原图和已校对题干已保存到错题本，可重试、切换引擎，或稍后手动补充。';
          _debugInfo = debugInfo;
        });
      }
    }
    if (token == _analysisToken) _analysisRunning = false;
  }

  void _advanceCaptureSessionToAnalysis() {
    final notifier = ref.read(captureSessionProvider.notifier);
    final phase = ref.read(captureSessionProvider).phase;
    if (phase == CaptureAnalysisPhase.imageSelected) {
      notifier.beginRecognition();
      notifier.beginAnalysis();
    } else if (phase == CaptureAnalysisPhase.recognizing ||
        phase == CaptureAnalysisPhase.needsConfirmation ||
        phase == CaptureAnalysisPhase.failed ||
        phase == CaptureAnalysisPhase.retryable) {
      notifier.beginAnalysis();
    }
  }

  void _markCaptureConfirmation() {
    final notifier = ref.read(captureSessionProvider.notifier);
    if (ref.read(captureSessionProvider).phase == CaptureAnalysisPhase.analyzing) {
      notifier.requireConfirmation('识别结果需要确认');
    }
  }

  void _completeCaptureSession(ContentStatus contentStatus) {
    final notifier = ref.read(captureSessionProvider.notifier);
    if (ref.read(captureSessionProvider).phase == CaptureAnalysisPhase.analyzing) {
      if (contentStatus == ContentStatus.needsConfirmation) {
        notifier.requireConfirmation('分析结果需要确认');
      } else {
        notifier.complete();
      }
    }
  }

  void _markRetryableCaptureSession(
    String message,
    CaptureFailureKind kind,
  ) {
    final notifier = ref.read(captureSessionProvider.notifier);
    if (ref.read(captureSessionProvider).phase == CaptureAnalysisPhase.analyzing) {
      notifier.markRetryable(message, kind: kind);
    }
  }

  bool _continueWorksheetQueue(QuestionRecord completed) {
    if (!ref.read(worksheetAutoAnalyzeProvider)) return false;
    final worksheet = ref.read(currentWorksheetImportProvider);
    if (worksheet == null || worksheet.sourcePageIds.contains(completed.id)) {
      // 队列结束：把 autoAnalyze 持久化为 false，避免重启后误以为仍在批量分析。
      Future<void>.microtask(() => setWorksheetAutoAnalyze(ref, false));
      return false;
    }
    final next = worksheet.pages.where((item) =>
        !worksheet.sourcePageIds.contains(item.id) &&
        item.contentStatus == ContentStatus.processing &&
        item.id != completed.id).toList();
    if (next.isEmpty) {
      Future<void>.microtask(() => setWorksheetAutoAnalyze(ref, false));
      return false;
    }
    ref.read(captureSessionProvider.notifier).updateCurrentQuestion(next.first);
    context.go('/analysis/loading');
    return true;
  }

  Future<void> _replaceWorksheetQueueItem(QuestionRecord record) async {
    final worksheet = ref.read(currentWorksheetImportProvider);
    if (worksheet == null || worksheet.sourcePageIds.contains(record.id)) {
      return;
    }
    final next = worksheet.pages
        .map((item) => item.id == record.id ? record : item)
        .toList();
    await persistWorksheetImport(ref, worksheet.copyWith(pages: next));
  }

  Future<QuestionRecord?> _findReusableLocalAnalysis(QuestionRecord current) async {
    final fingerprint = ImageFingerprintCodec.read(current.tags);
    if (fingerprint == null || fingerprint.isEmpty) return null;
    final existing = await ref.read(questionRepositoryProvider).listAll();
    for (final item in existing) {
      if (item.id == current.id || item.contentStatus != ContentStatus.ready ||
          item.analysisResult == null ||
          ImageFingerprintCodec.read(item.tags) != fingerprint) {
        continue;
      }
      // Do not overwrite a user-corrected text variant with analysis from an
      // earlier version of the same image.
      if (current.correctedText.isNotEmpty &&
          current.correctedText != item.correctedText) {
        continue;
      }
      return current.copyWith(
        contentStatus: ContentStatus.ready,
        analysisResult: item.analysisResult,
        savedExercises: item.savedExercises,
        subject: item.subject,
        aiTags: item.aiTags,
        aiKnowledgePoints: item.aiKnowledgePoints,
        candidateAnalyses: item.candidateAnalyses,
      );
    }
    return null;
  }

  bool _shouldAnalyzeImageDirectly(QuestionRecord question) {
    final subject = question.subject;
    final text = question.correctedText.trim();
    if (subject == Subject.english ||
        subject == Subject.chinese ||
        subject == Subject.history ||
        subject == Subject.geography ||
        subject == Subject.politics) {
      return text.isEmpty ||
          isCompositeLanguageWorksheet(text, subject: subject);
    }
    return false;
  }

  bool _shouldUseImageForAnalysis(QuestionRecord question) {
    final text = question.correctedText.trim();
    final service = ref.read(aiAnalysisServiceProvider);
    if (service.isGraphicalQuestion(
      text,
      question.subject.name,
      imagePath: question.imagePath,
    )) {
      return true;
    }
    if (text.length < 20) return true;

    return RegExp(
      '如图|图中|图示|下图|上图|左图|右图|根据图|观察图|函数图像|坐标系|电路图|表格|统计图|示意图',
    ).hasMatch(text);
  }

  String _splitSeedText(QuestionRecord question) {
    final normalized = question.normalizedQuestionText.trim();
    if (normalized.isNotEmpty) return normalized;
    final extracted = question.extractedQuestionText.trim();
    if (extracted.isNotEmpty) return extracted;
    return question.correctedText.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 解析'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          // 返回只是离开处理页，不等于放弃；保留当前图片和识别文本。
          onPressed: () => _leaveAnalysis('/capture/correction'),
        ),
      ),
      body: AppPage(
        maxWidth: AppContentWidth.narrow,
        padding: EdgeInsets.zero,
        child: _errorMessage != null
            ? _buildRecoveryView()
            : _AnalysisPipelineView(
                step: _step,
                steps: _steps,
                progressText: _progressText,
              ),
      ),
    );
  }

  Widget _buildRecoveryView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const AppTaskFlow(
              steps: <String>['拍一道错题', '确认识别', '查看错误定位', '开始练习'],
              currentStep: 2,
            ),
            const SizedBox(height: AppSpace.xl),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.danger.withValues(alpha: 0.16)
                    : AppColors.dangerContainerLight,
                borderRadius: BorderRadius.circular(32),
              ),
              child: const Icon(
                CupertinoIcons.exclamationmark_circle,
                color: AppColors.danger,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.dangerDark),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('调试信息:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(_debugInfo ?? '',
                        style: const TextStyle(
                            fontSize: 12, fontFamily: 'monospace')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // 主操作行：重试 + 切换引擎。所有失败场景（含极速模式和超时态）
            // 都提供"重试"和"切换引擎"两个核心恢复入口。
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _retryCurrentStage,
                  icon: const Icon(CupertinoIcons.arrow_clockwise),
                  label: Text('从“${_steps[_step]}”继续'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(120, 40)),
                ),
                OutlinedButton.icon(
                  onPressed: _showEngineSwitchDialog,
                  icon: const Icon(CupertinoIcons.arrow_2_squarepath),
                  label: const Text('切换引擎'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 次要操作：极速模式给"重新裁剪/重新拍照"，非极速给"返回校对"。
            if (_isQuickCapture)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: <Widget>[
                  TextButton.icon(
                    onPressed: () => context.go('/capture/crop'),
                    icon: const Icon(CupertinoIcons.crop),
                    label: const Text('重新裁剪'),
                  ),
                  TextButton.icon(
                    onPressed: _replaceCaptureWithNewPhoto,
                    icon: const Icon(CupertinoIcons.camera),
                    label: const Text('重新拍照'),
                  ),
                ],
              ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                TextButton.icon(
                  onPressed: () => context.go('/capture/recognition-confirmation'),
                  icon: const Icon(CupertinoIcons.pencil),
                  label: const Text('手动录入'),
                ),
                TextButton.icon(
                  onPressed: () => context.go('/notebook'),
                  icon: const Icon(CupertinoIcons.doc),
                  label: const Text('保留草稿'),
                ),
                TextButton.icon(
                  onPressed: _abandonAndCleanup,
                  icon: const Icon(CupertinoIcons.trash),
                  label: const Text('放弃并清理'),
                  style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abandonAndCleanup() async {
    _cancelCaptureSession();
    final current = ref.read(currentQuestionProvider);
    if (current == null) {
      if (mounted) context.go('/');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('放弃并清理草稿？'),
        content: const Text('将删除当前题目的临时草稿；仅当裁剪图没有被其他题目引用时才删除图片。'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('确认清理')),
        ],
      ),
    );
    if (confirmed != true) return;
    final repository = ref.read(questionRepositoryProvider);
    final others = (await repository.listAll()).where((item) => item.id != current.id).toList();
    await repository.delete(current.id);
    final worksheet = ref.read(currentWorksheetImportProvider);
    if (worksheet != null && worksheet.pages.any((item) => item.id == current.id)) {
      await persistWorksheetImport(
        ref,
        worksheet.copyWith(
          pages: worksheet.pages.where((item) => item.id != current.id).toList(),
        ),
      );
    }
    if (current.imagePath.isNotEmpty &&
        !others.any((item) => item.imagePath == current.imagePath)) {
      final image = File(current.imagePath);
      if (await image.exists()) await image.delete();
    }
    ref.read(captureSessionProvider.notifier).clearCurrentQuestion();
    invalidateQuestionList(ref);
    if (mounted) context.go('/');
  }

  Future<void> _retryCurrentStage() async {
    if (_analysisRunning) return;
    final current = ref.read(currentQuestionProvider);
    if (current == null) return;
    if (current.analysisResult == null) {
      final persisted =
          await ref.read(questionRepositoryProvider).getById(current.id);
      if (persisted != null) {
        ref.read(captureSessionProvider.notifier).updateCurrentQuestion(persisted);
      }
    }
    final checkpoint = ref.read(currentQuestionProvider) ?? current;
    setState(() {
      _isTimeout = false;
      _errorMessage = null;
      _progressText = null;
      _step = _resumeStepFor(checkpoint);
    });
    await _runAnalysis();
  }

  int _resumeStepFor(QuestionRecord question) {
    if (question.analysisResult != null) return 3;
    if (question.normalizedQuestionText.trim().isEmpty) return 0;
    if (!(question.splitResult?.hasMultipleCandidates ?? false) &&
        !question.tags.contains(_boundaryCheckedTag)) {
      return 1;
    }
    return 2;
  }

  /// 弹出引擎选择器，让用户在普通 AI / PaddleOCR / MinerU 间切换。
  /// - 选 AI：等同 [_retryCurrentStage]（从最近断点继续当前 AI 服务）。
  /// - 选 PaddleOCR/MinerU：设置一次性 provider type，确保当前题目在
  ///   worksheet session 中，跳转 `/worksheet/regions` 走文档识别流程。
  Future<void> _showEngineSwitchDialog() async {
    final choice = await showModalBottomSheet<_EngineChoice>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('切换识别引擎',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                '当前题目识别失败或超时。可重试当前引擎，或切换到其他引擎继续识别。',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              ..._EngineChoice.values.map((item) => ListTile(
                    leading: Icon(item.icon),
                    title: Text(item.label),
                    subtitle: Text(item.description),
                    onTap: () => Navigator.pop(ctx, item),
                  )),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;

    switch (choice) {
      case _EngineChoice.ai:
        await _retryCurrentStage();
      case _EngineChoice.paddle:
        await _switchToWorksheetEngine(LayoutProviderType.paddleCloud);
      case _EngineChoice.mineru:
        await _switchToWorksheetEngine(LayoutProviderType.mineruCloud);
    }
  }

  /// 切换到 PaddleOCR/MinerU 文档识别流程。
  /// 若当前题目已在 worksheet session 中（典型：从 capture 进入），直接
  /// 复用；否则把当前题目加入现有 session（或新建一个），再跳转。
  Future<void> _switchToWorksheetEngine(LayoutProviderType type) async {
    final current = ref.read(currentQuestionProvider);
    if (current == null) {
      if (mounted) context.go('/');
      return;
    }
    ref.read(oneShotLayoutProviderTypeProvider.notifier).state = type;

    final existing = ref.read(currentWorksheetImportProvider);
    final alreadyInSession =
        existing != null && existing.pages.any((p) => p.id == current.id);
    if (!alreadyInSession) {
      // WorksheetImportSession 的 sourcePageIds 是 final，无法通过 copyWith
      // 修改，因此这里直接构造新会话。保留已有 pages 以避免丢历史草稿。
      final pages = <QuestionRecord>[
        ...?existing?.pages,
        current,
      ];
      final sourcePageIds = <String>{
        ...?existing?.sourcePageIds,
        current.id,
      };
      await persistWorksheetImport(
        ref,
        WorksheetImportSession(
          id: existing?.id ?? '',
          pages: pages,
          sourcePageIds: sourcePageIds,
          createdAt: existing?.createdAt ?? DateTime.now(),
        ),
      );
    }
    if (mounted) context.go('/worksheet/regions');
  }
}

enum _EngineChoice {
  ai('普通 AI', '重新调用当前 AI 服务重试'),
  paddle('PaddleOCR', '文档识别：文字、公式、表格、选项'),
  mineru('MinerU', 'VLM 文档理解：复杂公式、多栏试卷');

  const _EngineChoice(this.label, this.description);
  final String label;
  final String description;

  IconData get icon => switch (this) {
        _EngineChoice.ai => CupertinoIcons.sparkles,
        _EngineChoice.paddle => CupertinoIcons.doc_text_search,
        _EngineChoice.mineru => CupertinoIcons.doc_richtext,
      };
}

class _AnalysisPipelineView extends StatefulWidget {
  const _AnalysisPipelineView({
    required this.step,
    required this.steps,
    this.progressText,
  });

  final int step;
  final List<String> steps;
  final String? progressText;

  @override
  State<_AnalysisPipelineView> createState() => _AnalysisPipelineViewState();
}

class _AnalysisPipelineViewState extends State<_AnalysisPipelineView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppMotion.progressLoop,
      vsync: this,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = AppMotion.isReduced(context);
    if (_reduced == reduced && (_controller.isAnimating || reduced)) return;
    _reduced = reduced;
    if (reduced) {
      _controller
        ..stop()
        ..value = 0;
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    const accent = AppColors.primary;
    final hasProgress = widget.progressText != null;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const AppTaskFlow(
              steps: <String>['拍一道错题', '确认识别', '查看错误定位', '开始练习'],
              currentStep: 2,
            ),
            const SizedBox(height: AppSpace.xxl),
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.semanticContainer(
                  accent,
                  isDark: isDark,
                  lightAlpha: 0.08,
                  darkAlpha: 0.18,
                ),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (_, __) => Transform.rotate(
                  angle: _controller.value * 2 * 3.14159,
                  child: Icon(_stepIcon(widget.step),
                      size: 44, color: accent),
                ),
              ),
            ),
            const SizedBox(height: 28),
            const CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.primary,
            ),
            const SizedBox(height: 28),
            // 阶段进度条：4 个圆点 + 当前阶段高亮
            if (!hasProgress) ...<Widget>[
              StageIndicator(
                steps: widget.steps,
                current: widget.step,
                accent: accent,
                dimColor: colorScheme.outlineVariant,
              ),
              const SizedBox(height: 20),
            ],
            Text(
              hasProgress
                  ? widget.progressText!
                  : '阶段 ${widget.step + 1}/${widget.steps.length}：${widget.steps[widget.step]}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              hasProgress
                  ? '多题并行分析中，请稍候...'
                  : 'AI 正在生成学习分析，请稍候...',
              style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// 各阶段对应图标，让用户从图标就能判断当前在做什么。
  IconData _stepIcon(int step) {
    const icons = <IconData>[
      CupertinoIcons.doc_text_search,  // 识别题目
      CupertinoIcons.lightbulb,         // 理解题意
      CupertinoIcons.wand_stars,        // 生成解析
      CupertinoIcons.checkmark_seal,    // 即将完成
    ];
    return icons[step.clamp(0, icons.length - 1)];
  }
}

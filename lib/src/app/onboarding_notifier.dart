import 'package:flutter/foundation.dart';

/// 跟踪 onboarding 完成状态，作为 GoRouter 的 refreshListenable。
///
/// 之前的实现把 onboarding 检查放在 main.dart 的 PostFrameCallback 里，
/// 并且用 `catch (_) {}` 吞掉了所有异常，导致：
/// 1. 启动时存在闪烁（先渲染首页再跳转 onboarding）；
/// 2. settingsRepo 读取失败时静默忽略，用户可能反复看到 onboarding 或永远看不到。
///
/// 改用 ChangeNotifier + redirect 后，路由切换是声明式的，无闪烁；
/// 同时把读取错误显式记录到 [error]，便于排查。
class OnboardingNotifier extends ChangeNotifier {
  OnboardingNotifier({required bool initialDone})
      : _done = initialDone,
        _error = null;

  bool _done;
  Object? _error;

  /// onboarding 是否已完成。
  bool get done => _done;

  /// 最近一次读取/写入 settings 时发生的错误（如果有）。
  /// 路由 redirect 在 [error] 非 null 时不强制跳转，避免卡死用户。
  Object? get error => _error;

  /// 初始化时从 settingsRepo 读取 onboarding_done 标记。
  /// 读取失败时记录 error，但保持 [done] 为 false（默认引导用户走 onboarding）。
  Future<void> loadFromSettings(
      Future<String?> Function(String) getString) async {
    try {
      final value = await getString('onboarding_done');
      _done = value == 'true';
      _error = null;
    } catch (e, st) {
      _error = e;
      if (kDebugMode) {
        debugPrint('OnboardingNotifier.loadFromSettings failed: $e\n$st');
      }
    }
    notifyListeners();
  }

  /// onboarding 完成时调用。settings 写入失败也会记录 error。
  Future<void> markDone(
      Future<void> Function(String, String) setString) async {
    try {
      await setString('onboarding_done', 'true');
      _done = true;
      _error = null;
    } catch (e, st) {
      _error = e;
      if (kDebugMode) {
        debugPrint('OnboardingNotifier.markDone failed: $e\n$st');
      }
    }
    notifyListeners();
  }
}

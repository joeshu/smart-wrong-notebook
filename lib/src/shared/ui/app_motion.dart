import 'package:flutter/material.dart';

/// 统一的动效规范（Motion）。
///
/// 大厂级界面“不廉价”的关键之一是动效克制且一致：统一的时长档位、
/// 统一的缓动曲线、统一的方向。避免在各个页面硬编码 `Duration(milliseconds: 300)`。
abstract final class AppMotion {
  /// Instant state change used when the system requests reduced motion.
  static const Duration none = Duration.zero;

  static const bool isTest = bool.fromEnvironment('FLUTTER_TEST');

  /// Extremely fast feedback (switches, badges).
  static const Duration micro = isTest ? Duration.zero : Duration(milliseconds: 120);

  /// List and card entrances.
  static const Duration fast = Duration(milliseconds: 240);

  /// Page and large-container transitions.
  static const Duration medium = Duration(milliseconds: 360);

  /// Hero-level transitions. Avoid this for routine feedback.
  static const Duration slow = Duration(milliseconds: 520);

  static const Duration shimmer = Duration(milliseconds: 1200);
  static const Duration progressLoop = Duration(seconds: 3);
  static const Curve standard = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Duration staggerStep = Duration(milliseconds: 60);


  /// Honors both platform disableAnimations and accessibility navigation.
  static bool isReduced(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    return isTest ||
        media?.disableAnimations == true ||
        media?.accessibleNavigation == true;
  }

  /// Resolves a token duration against the platform reduced-motion setting.
  static Duration resolve(BuildContext context, Duration duration) =>
      isReduced(context) ? none : duration;
}

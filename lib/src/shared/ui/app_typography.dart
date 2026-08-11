import 'package:flutter/material.dart';

/// 全局字体层级（Typography Scale）。
///
/// 大厂级产品的“质感”有相当部分来自稳定的字阶与字重节奏：
/// 同一屏内字号档位收敛、字重对比明确（标题重、正文常规、辅助轻）。
///
/// 中文与西文默认使用系统字体栈，避免首次启动依赖网络下载字体。
/// 所有 TextStyle 经 [AppTextStyle.apply] 统一保留字阶和字重节奏。
abstract final class AppTextStyle {
  // ---------- Display：页面级大标题 / Hero 数字 ----------
  static const TextStyle display = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w800,
    height: 1.15,
    letterSpacing: -0.5,
  );

  // ---------- Headline：区块大标题 ----------
  static const TextStyle headline = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.3,
  );

  // ---------- Title：卡片标题 / 小节标题 ----------
  static const TextStyle title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.2,
  );

  // ---------- Subtitle：次级标题 ----------
  static const TextStyle subtitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: -0.1,
  );

  // ---------- Body：正文 ----------
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  // ---------- BodyStrong：强调正文 ----------
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.5,
  );

  // ---------- Label：标签 / 按钮文字 ----------
  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: 0.1,
  );

  // ---------- Caption：辅助说明 ----------
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
    letterSpacing: 0.1,
  );

  // ---------- Overline：极小标注 ----------
  static const TextStyle overline = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: 0.6,
  );

  /// 保留统一字阶与字重，字体家族交由系统选择，避免运行时网络依赖。
  static TextStyle apply(TextStyle base) => base;

  /// 便捷构造：在 [apply] 基础上覆盖颜色。
  static TextStyle colored(TextStyle base, Color color) =>
      apply(base).copyWith(color: color);
}

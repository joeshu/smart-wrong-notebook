import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

/// Shared responsive breakpoints. Pages must not invent local width thresholds.
abstract final class AppBreakpoints {
  static const double compact = 360;
  static const double medium = 600;
  static const double expanded = 900;
  static const double large = 1200;

  static AppWindowClass windowClass(double width) {
    if (width < medium) return AppWindowClass.compact;
    if (width < expanded) return AppWindowClass.medium;
    if (width < large) return AppWindowClass.expanded;
    return AppWindowClass.large;
  }
}

enum AppWindowClass { compact, medium, expanded, large }

extension AppWindowClassX on AppWindowClass {
  bool get isCompact => this == AppWindowClass.compact;
  bool get isAtLeastExpanded =>
      this == AppWindowClass.expanded || this == AppWindowClass.large;
}

/// Global content widths keep tablet and desktop layouts readable.
abstract final class AppContentWidth {
  static const double narrow = 640;
  static const double standard = 840;
  static const double wide = 1120;
}

/// Centers page content, applies shared gutters and enforces a readable max width.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.child,
    this.maxWidth = AppContentWidth.standard,
    this.padding,
    this.safeArea = true,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final bool safeArea;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final resolvedPadding = padding ??
        (width >= AppBreakpoints.expanded ? AppSpace.pageWide : AppSpace.page);
    Widget result = Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: resolvedPadding, child: child),
      ),
    );
    if (safeArea) result = SafeArea(child: result);
    return result;
  }
}

/// A shared one/two-column shell for task and detail pages.
class AppAdaptiveColumns extends StatelessWidget {
  const AppAdaptiveColumns({
    super.key,
    required this.primary,
    this.secondary,
    this.gap = AppSpace.xl,
    this.primaryFlex = 3,
    this.secondaryFlex = 2,
    this.secondaryBelowOnCompact = true,
  });

  final Widget primary;
  final Widget? secondary;
  final double gap;
  final int primaryFlex;
  final int secondaryFlex;
  final bool secondaryBelowOnCompact;

  @override
  Widget build(BuildContext context) {
    final side = secondary;
    if (side == null) return primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final window = AppBreakpoints.windowClass(constraints.maxWidth);
        if (!window.isAtLeastExpanded) {
          if (!secondaryBelowOnCompact) return primary;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[primary, SizedBox(height: gap), side],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(flex: primaryFlex, child: primary),
            SizedBox(width: gap),
            Expanded(flex: secondaryFlex, child: side),
          ],
        );
      },
    );
  }
}

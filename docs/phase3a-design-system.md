# Phase 3A — Design System convergence

Phase 3A establishes one shared visual and responsive contract before page migration.

## Token ownership

- `app_colors.dart`: brand, semantic, surface and elevation-shadow colors.
- `app_ui.dart`: spacing, radius, elevation and control-size tokens plus shared components.
- `app_typography.dart`: product type scale; page code should prefer `Theme.textTheme` or `AppTextStyle`.
- `app_motion.dart`: duration/curve tokens and the platform-aware Reduced Motion policy.
- `app_layout.dart`: responsive breakpoints, content widths, centered page shell and adaptive columns.
- `app_theme.dart`: light/dark Material defaults composed from the tokens above.

## Responsive contract

| Window class | Width |
| --- | ---: |
| compact | `< 600` |
| medium | `600–899` |
| expanded | `900–1199` |
| large | `≥ 1200` |

A `360` token remains available as the narrow-device hint, but it is not a separate layout class. Pages should use `AppPage` for shared gutters and maximum widths, and `AppAdaptiveColumns` for readable large-screen two-column layouts.

## State ownership

`AppEmptyState`, `AppErrorState` and `AppLoadingState` in `app_ui.dart` are the only generic state views. The unused legacy `common/widgets/state_views.dart` implementation and page-local generic empty-state widgets were removed. Task-specific states, such as the live AI pipeline and its recovery actions, remain feature components and are named accordingly.

## Reduced Motion

`AppMotion.isReduced(context)` honors `MediaQuery.disableAnimations` and `accessibleNavigation`. Shared entrance and shimmer animations stop under that policy. New motion must use `AppMotion` durations and check or resolve against this policy.

## Migration rules

1. Do not add raw hexadecimal colors to migrated pages.
2. Use semantic `ColorScheme` colors or `AppColors`.
3. Use spacing, radius, elevation, typography and motion tokens or Theme values.
4. Keep one clear primary action per task state.
5. Use `AppPage` maximum widths and only introduce two columns at the shared expanded breakpoint.
6. Large decorative gradients must not carry primary information.
7. Preserve existing routes and feature behavior while migrating page structure.

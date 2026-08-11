# Phase 3C — Learning loop pages

## Information hierarchy

The learning surfaces now follow the same order:

1. conclusion or current task state;
2. supporting evidence;
3. detailed reasoning collapsed by default;
4. risk feedback adjacent to the affected content;
5. one filled primary action for the current state.

## Page migration

- **Notebook**: shared wide content cap around search, filters, state views and list modes.
- **Question Detail**: shared wide content cap; the analysis tab promotes “错误定位” before the answer/evidence and retains solution steps as collapsed detail.
- **Review**: shared wide content cap and Reduced Motion-aware summary transition; existing rating workflow is unchanged.
- **Exercise**: shared standard readable width for exercise and completion states; semantic success color replaces local literals.
- **Settings**: shared standard width keeps grouped preferences readable on tablets and desktops.

Generic loading, empty and error states remain owned by `app_ui.dart`; feature-specific pipeline/recovery states remain explicit feature components.

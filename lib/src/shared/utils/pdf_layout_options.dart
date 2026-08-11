/// PDF 排版选项：控制 PDF 导出的纸张、方向、边距、字号及附加页。
///
/// 桌面端 [PdfExportService] 已接入全部字段（pageSize/margin/fontSize 等），
/// 移动端靠 HTML 模板的 `@page` CSS 控制纸张（`generateCss(layout)` 已读取
/// [pageSize]/[orientation]/[margin]），原生 `flutter_native_html_to_pdf` API
/// 仅作兜底（其 `PdfPageSize` 枚举仅支持 a4/a5，letter/b5 由 CSS 兜底）。
class PdfLayoutOptions {
  const PdfLayoutOptions({
    this.pageSize = PdfPageSize.a4,
    this.orientation = PdfOrientation.portrait,
    this.margin = PdfMargin.normal,
    this.fontSize = PdfFontSize.medium,
    this.includeCover = true,
    this.includeToc = false,
    this.includeHeader = true,
    this.includeFooter = true,
    this.footerText,
    this.headerText,
  });

  /// 默认排版选项：A4 纵向、正常边距、中字号，含封面/页眉/页脚。
  /// 服务层在 [PdfLayoutOptions] 为 null 时使用此值，保持与历史行为一致。
  static const PdfLayoutOptions defaults = PdfLayoutOptions();

  /// 纸张大小。
  final PdfPageSize pageSize;

  /// 页面方向。
  final PdfOrientation orientation;

  /// 页边距档位。
  final PdfMargin margin;

  /// 正文字号档位。
  final PdfFontSize fontSize;

  /// 是否生成封面页。
  final bool includeCover;

  /// 是否生成目录页。
  final bool includeToc;

  /// 是否添加页眉。
  final bool includeHeader;

  /// 是否添加页脚（含页码）。
  final bool includeFooter;

  /// 自定义页脚文本：非空时覆盖默认的 `第 X 页 / 共 Y 页` 计数器。
  /// 支持占位符：`{page}`、`{pages}`、`{date}`、`{studentName}`（也兼容 `{学生名}`）、
  /// `{knowledgePath}`（Phase 11-5，当前页主导知识点路径，调用方按页填充）。
  /// 为 null 或空串时使用默认计数器表达式。
  final String? footerText;

  /// 自定义页眉文本：非空时覆盖默认的标题页眉。
  /// 支持占位符同 [footerText]，`{knowledgePath}` 用于显示当前页所属学科/知识点。
  /// 为 null 或空串时使用默认标题（由导出标题填充）。
  final String? headerText;

  /// 解析页脚预览文本：供屏幕预览的占位 div 使用（实际打印时由 CSS
  /// @bottom-center counter 生成）。
  ///
  /// [footerText] 为 null/空时返回默认的 `第 {page} 页 / 共 {pages} 页`；
  /// 否则将 `footerText` 中的 `{page}` / `{pages}` / `{date}` / `{studentName}`
  /// / `{knowledgePath}` 占位符（以及中文别名 `{学生名}`、`{知识点路径}`）
  /// 替换为实际值后返回。
  static String resolveFooter(
    String? footerText,
    int page,
    int pages,
    String dateStr,
    String? studentName, {
    String? knowledgePath,
  }) {
    if (footerText == null || footerText.isEmpty) {
      return '第 $page 页 / 共 $pages 页';
    }
    return footerText
        .replaceAll('{page}', page.toString())
        .replaceAll('{pages}', pages.toString())
        .replaceAll('{date}', dateStr)
        .replaceAll('{studentName}', studentName ?? '')
        .replaceAll('{学生名}', studentName ?? '')
        .replaceAll('{knowledgePath}', knowledgePath ?? '')
        .replaceAll('{知识点路径}', knowledgePath ?? '');
  }

  /// 解析页眉预览文本（Phase 11-5）。
  ///
  /// [headerText] 为 null/空时返回 [defaultHeader]（导出标题）；
  /// 否则按占位符替换（同 [resolveFooter]）。
  static String resolveHeader(
    String? headerText,
    String defaultHeader, {
    String? knowledgePath,
    String? studentName,
  }) {
    if (headerText == null || headerText.isEmpty) {
      return defaultHeader;
    }
    return headerText
        .replaceAll('{studentName}', studentName ?? '')
        .replaceAll('{学生名}', studentName ?? '')
        .replaceAll('{knowledgePath}', knowledgePath ?? '')
        .replaceAll('{知识点路径}', knowledgePath ?? '');
  }

  PdfLayoutOptions copyWith({
    PdfPageSize? pageSize,
    PdfOrientation? orientation,
    PdfMargin? margin,
    PdfFontSize? fontSize,
    bool? includeCover,
    bool? includeToc,
    bool? includeHeader,
    bool? includeFooter,
    String? footerText,
    String? headerText,
  }) {
    return PdfLayoutOptions(
      pageSize: pageSize ?? this.pageSize,
      orientation: orientation ?? this.orientation,
      margin: margin ?? this.margin,
      fontSize: fontSize ?? this.fontSize,
      includeCover: includeCover ?? this.includeCover,
      includeToc: includeToc ?? this.includeToc,
      includeHeader: includeHeader ?? this.includeHeader,
      includeFooter: includeFooter ?? this.includeFooter,
      footerText: footerText ?? this.footerText,
      headerText: headerText ?? this.headerText,
    );
  }
}

/// PDF 纸张大小枚举。
enum PdfPageSize {
  a4,
  a5,
  letter,
  b5;

  String get label => switch (this) {
        PdfPageSize.a4 => 'A4',
        PdfPageSize.a5 => 'A5',
        PdfPageSize.letter => 'Letter',
        PdfPageSize.b5 => 'B5',
      };
}

/// PDF 页面方向枚举。
enum PdfOrientation {
  portrait,
  landscape;

  String get label => switch (this) {
        PdfOrientation.portrait => '纵向',
        PdfOrientation.landscape => '横向',
      };
}

/// PDF 页边距档位枚举。
enum PdfMargin {
  narrow,
  normal,
  wide;

  String get label => switch (this) {
        PdfMargin.narrow => '窄',
        PdfMargin.normal => '正常',
        PdfMargin.wide => '宽',
      };
}

/// PDF 正文字号档位枚举。
enum PdfFontSize {
  small,
  medium,
  large;

  String get label => switch (this) {
        PdfFontSize.small => '小',
        PdfFontSize.medium => '中',
        PdfFontSize.large => '大',
      };
}

/// 将 [PdfLayoutOptions] 解析为 HTML / CSS 可直接使用的字符串与数值。
///
/// 仅做枚举 → 字面量映射，方便模板与服务层共享同一套 CSS 计算逻辑。
extension PdfLayoutOptionsCss on PdfLayoutOptions {
  /// `@page size` 字面量，例如 `A4`、`A5 landscape`。
  String get cssPageWithOrientation {
    final sizeStr = pageSize.label;
    if (orientation == PdfOrientation.landscape) {
      return '$sizeStr landscape';
    }
    return sizeStr;
  }

  /// `@page margin` 字面量（上 右 下 左）。
  String get cssMarginBox => switch (margin) {
        PdfMargin.narrow => '14mm 14mm 14mm 14mm',
        PdfMargin.normal => '24mm 22mm 22mm 22mm',
        PdfMargin.wide => '32mm 30mm 28mm 30mm',
      };

  /// 桌面端原生 PDF 用的页边距（毫米）：返回 `(上下, 左右)`。
  /// 取上下各档的「上边距」、左右各档的「左边距」作为统一值，
  /// 与 [cssMarginBox] 的字面量保持同档位语义。
  (double, double) get cssMargin => switch (margin) {
        PdfMargin.narrow => (14.0, 14.0),
        PdfMargin.normal => (24.0, 22.0),
        PdfMargin.wide => (32.0, 30.0),
      };

  /// 基础正文字号（pt），驱动模板 CSS 中按比例缩放的字号层级。
  double get baseFontSizePt => switch (fontSize) {
        PdfFontSize.small => 10.0,
        PdfFontSize.medium => 11.0,
        PdfFontSize.large => 12.5,
      };

  /// 基础正文字号（px）：`pt * 96 / 72`。
  double get baseFontSize => baseFontSizePt * 96.0 / 72.0;
}

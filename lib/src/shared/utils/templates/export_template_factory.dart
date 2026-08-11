import 'package:smart_wrong_notebook/src/shared/utils/export_template.dart';
import 'package:smart_wrong_notebook/src/shared/utils/templates/error_card_template.dart';
import 'package:smart_wrong_notebook/src/shared/utils/templates/exam_paper_template.dart';
import 'package:smart_wrong_notebook/src/shared/utils/templates/mistake_report_template.dart';
import 'package:smart_wrong_notebook/src/shared/utils/templates/review_card_template.dart';
import 'package:smart_wrong_notebook/src/shared/utils/templates/study_report_template.dart';

/// 导出模板工厂：根据 [ExportTemplateType] 创建对应模板实例。
///
/// 服务层与 UI 通过本工厂解耦具体模板实现。
class ExportTemplateFactory {
  ExportTemplateFactory._();

  /// 根据 [type] 创建模板实例。
  static ExportTemplate create(ExportTemplateType type) {
    return switch (type) {
      ExportTemplateType.mistakeReport => MistakeReportTemplate(),
      ExportTemplateType.studyReport => StudyReportTemplate(),
      ExportTemplateType.reviewCard => ReviewCardTemplate(),
      ExportTemplateType.examPaper => ExamPaperTemplate(),
      ExportTemplateType.errorCard => ErrorCardTemplate(),
    };
  }

  /// 列出所有可用模板（用于 UI 模板选择列表）。
  static List<ExportTemplate> all() => <ExportTemplate>[
        MistakeReportTemplate(),
        StudyReportTemplate(),
        ReviewCardTemplate(),
        ExamPaperTemplate(),
        ErrorCardTemplate(),
      ];
}

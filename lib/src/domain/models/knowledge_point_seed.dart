import 'package:smart_wrong_notebook/src/domain/models/knowledge_point.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

/// 内置基础知识点目录。
///
/// Phase 4 基础模型：为常见学科预置章节—知识点两级目录，供首次启动时
/// 播种到 [KnowledgePointRepository]。用户可在此基础上增删改。
class KnowledgePointSeed {
  KnowledgePointSeed._();

  static final DateTime _seedTime = DateTime(2026, 1, 1);

  /// 生成全部内置知识点。
  static List<KnowledgePoint> builtins() {
    return <KnowledgePoint>[
      ..._math(),
      ..._physics(),
      ..._chemistry(),
    ];
  }

  static List<KnowledgePoint> _math() {
    const subject = Subject.math;
    return <KnowledgePoint>[
      // 章级节点
      KnowledgePoint(
        id: 'kp_math_algebra',
        name: '代数',
        parentId: null,
        subject: subject,
        grade: null,
        sortOrder: 1,
        createdAt: _seedTime,
        updatedAt: _seedTime,
      ),
      KnowledgePoint(
        id: 'kp_math_geometry',
        name: '几何',
        parentId: null,
        subject: subject,
        grade: null,
        sortOrder: 2,
        createdAt: _seedTime,
        updatedAt: _seedTime,
      ),
      KnowledgePoint(
        id: 'kp_math_functions',
        name: '函数',
        parentId: null,
        subject: subject,
        grade: null,
        sortOrder: 3,
        createdAt: _seedTime,
        updatedAt: _seedTime,
      ),
      // 代数 → 知识点
      KnowledgePoint(
        id: 'kp_math_algebra_equations',
        name: '方程与不等式',
        aliases: <String>['一元二次方程', '方程组', '不等式'],
        parentId: 'kp_math_algebra',
        subject: subject,
        sortOrder: 1,
        createdAt: _seedTime,
        updatedAt: _seedTime,
      ),
      KnowledgePoint(
        id: 'kp_math_algebra_polynomials',
        name: '多项式',
        aliases: <String>['因式分解', '整式乘法'],
        parentId: 'kp_math_algebra',
        subject: subject,
        sortOrder: 2,
        createdAt: _seedTime,
        updatedAt: _seedTime,
      ),
      // 几何 → 知识点
      KnowledgePoint(
        id: 'kp_math_geometry_triangle',
        name: '三角形',
        aliases: <String>['全等三角形', '相似三角形', '勾股定理'],
        parentId: 'kp_math_geometry',
        subject: subject,
        sortOrder: 1,
        createdAt: _seedTime,
        updatedAt: _seedTime,
      ),
      KnowledgePoint(
        id: 'kp_math_geometry_circle',
        name: '圆',
        aliases: <String>['圆的性质', '切线', '圆周角'],
        parentId: 'kp_math_geometry',
        subject: subject,
        sortOrder: 2,
        createdAt: _seedTime,
        updatedAt: _seedTime,
      ),
      // 函数 → 知识点
      KnowledgePoint(
        id: 'kp_math_functions_quadratic',
        name: '二次函数',
        aliases: <String>['抛物线', '顶点坐标'],
        parentId: 'kp_math_functions',
        subject: subject,
        sortOrder: 1,
        createdAt: _seedTime,
        updatedAt: _seedTime,
      ),
    ];
  }

  static List<KnowledgePoint> _physics() {
    const subject = Subject.physics;
    return <KnowledgePoint>[
      KnowledgePoint(
        id: 'kp_phys_mechanics',
        name: '力学',
        parentId: null,
        subject: subject,
        sortOrder: 1,
        createdAt: _seedTime,
        updatedAt: _seedTime,
      ),
      KnowledgePoint(
        id: 'kp_phys_mechanics_newton',
        name: '牛顿运动定律',
        aliases: <String>['牛顿第一定律', '牛顿第二定律', '惯性'],
        parentId: 'kp_phys_mechanics',
        subject: subject,
        sortOrder: 1,
        createdAt: _seedTime,
        updatedAt: _seedTime,
      ),
      KnowledgePoint(
        id: 'kp_phys_mechanics_kinematics',
        name: '运动学',
        aliases: <String>['匀速直线运动', '匀变速直线运动', '速度', '加速度'],
        parentId: 'kp_phys_mechanics',
        subject: subject,
        sortOrder: 2,
        createdAt: _seedTime,
        updatedAt: _seedTime,
      ),
    ];
  }

  static List<KnowledgePoint> _chemistry() {
    const subject = Subject.chemistry;
    return <KnowledgePoint>[
      KnowledgePoint(
        id: 'kp_chem_reactions',
        name: '化学反应',
        parentId: null,
        subject: subject,
        sortOrder: 1,
        createdAt: _seedTime,
        updatedAt: _seedTime,
      ),
      KnowledgePoint(
        id: 'kp_chem_reactions_equations',
        name: '化学方程式',
        aliases: <String>['配平', '化学方程式书写'],
        parentId: 'kp_chem_reactions',
        subject: subject,
        sortOrder: 1,
        createdAt: _seedTime,
        updatedAt: _seedTime,
      ),
      KnowledgePoint(
        id: 'kp_chem_reactions_types',
        name: '反应类型',
        aliases: <String>['化合反应', '分解反应', '置换反应', '复分解反应'],
        parentId: 'kp_chem_reactions',
        subject: subject,
        sortOrder: 2,
        createdAt: _seedTime,
        updatedAt: _seedTime,
      ),
    ];
  }
}

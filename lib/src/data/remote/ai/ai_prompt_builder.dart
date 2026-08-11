import 'dart:convert';

import 'package:smart_wrong_notebook/src/data/remote/ai/ai_provider_capabilities.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_contract.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_patch.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';

class AiPromptBuilder {
  const AiPromptBuilder();

  String buildAnalysisPrompt({
    required String subjectName,
    required String correctedText,
    String studentAnswer = '',
    String modelName = 'configured-model',
  }) {
    return '''请分析以下$subjectName科目的错题。

已确认题目：
$correctedText

学生作答：
${studentAnswer.trim().isEmpty ? '（未提供）' : studentAnswer}

${buildV2ContractInstruction(modelName: modelName)}''';
  }

  String buildV2ContractInstruction({required String modelName}) => '''
只返回一个 JSON 对象，不要输出 Markdown、代码围栏、解释性前缀或后缀。
schemaVersion 固定为 ${AiAnalysisSchema.currentVersion}。
promptVersion 固定为 "${AiAnalysisSchema.currentPromptVersion}"。
modelName 固定为 ${jsonEncode(modelName)}。

可靠性规则：
1. confidence.overall 和 confidence.fields 的分数范围都是 0 到 1。
2. confidence.fields 必须包含 normalizedQuestion、studentAnswer、standardAnswer、solutionSteps、knowledgePoints、generatedExercises。
3. 不确定内容必须写入 uncertainties，不得用确定语气补全看不清的信息。
4. evidence 必须引用原图、原题、用户确认文本、学生作答或解题步骤中的可核验证据。
5. studentAnswer 为空时，mistakeCategory 必须为 null，mistakeReason 必须为空字符串；不得推断“粗心”“马虎”或个人能力问题。
6. 给出错因时，evidence 至少包含一条 field="mistakeReason"、source="studentAnswer" 的学生原步骤引用。
7. generatedExercises 无法可靠生成时返回空数组，不得生成无关题目。
8. originalQuestion 保留输入题目；normalizedQuestion 只做必要的格式规范化，不得改变题意。

必须包含以下顶层字段：
schemaVersion, promptVersion, modelName, subject, confidence, uncertainties,
evidence, mistakeCategory, originalQuestion, normalizedQuestion, studentAnswer,
standardAnswer, solutionSteps, knowledgePoints, generatedExercises,
mistakeReason, studyAdvice, aiTags, reviewPlan, specializedAnalysis。

结构要求：
- confidence: {"overall": 0.0, "fields": {"字段名": 0.0}}
- uncertainties: [{"field": "", "description": "", "suggestedAction": ""}]
- evidence: [{"field": "", "source": "image|originalQuestion|normalizedQuestion|studentAnswer|solutionStep|modelInference", "quote": "", "explanation": "", "stepIndex": 0}]
- mistakeCategory: "concept|comprehension|calculation|strategy|format|careless" 或 null
- generatedExercises: [{"id":"", "difficulty":"简单|同级|提高", "question":"", "options":["A. ","B. ","C. ","D. "], "answer":"A|B|C|D", "explanation":"", "diagramData":null}]
- reviewPlan: {"reviewAfterDays": 0, "focus": [""], "reason": ""}
- specializedAnalysis: 普通题返回 null；方程、方程组、几何或证明题返回 {"profile":"algebraEquation|equationSystem|geometry|proofArgument","givens":[],"goal":"","entities":[],"relations":[],"constraints":[],"reasoningSteps":[{"index":1,"statement":"","basis":"","dependsOn":[]}],"verification":[],"risks":[],"isModelProvided":true}
- 方程必须在 verification 中给出代回原式的核对；几何步骤必须写定理依据；证明步骤 basis 为空时必须在 risks 标记依据缺失。
''';

  String buildFieldRepairPrompt({
    required AnalysisResult current,
    required Set<AiAnalysisField> fields,
    required String confirmedQuestion,
    required String studentAnswer,
    required String modelName,
  }) {
    final names = fields.map((field) => field.name).toList(growable: false);
    final currentValues = <String, dynamic>{
      for (final field in fields) field.name: current.toJson()[field.name],
    };
    return '''只修复指定的 AI 分析字段，不要重做或改写其他字段。
只返回一个 JSON 对象，不要使用 Markdown 代码围栏。

用户确认题目：
$confirmedQuestion

学生作答：
${studentAnswer.trim().isEmpty ? '（未提供）' : studentAnswer}

待修复字段：${names.join(', ')}
当前字段值：${jsonEncode(currentValues)}

返回结构：
{
  "schemaVersion": ${AiAnalysisSchema.currentVersion},
  "promptVersion": "${AiAnalysisSchema.currentPromptVersion}",
  "modelName": ${jsonEncode(modelName)},
  "fields": {"仅包含请求字段": "修复后的值"},
  "confidence": {"overall": 0.0, "fields": {"每个请求字段": 0.0}},
  "uncertainties": [],
  "evidence": []
}

规则：
1. fields 必须且只能包含：${names.join(', ')}。
2. 不确定项写入 uncertainties；不得猜测看不清的信息。
3. 修复 mistakeReason/mistakeCategory 时必须引用 studentAnswer 证据。
4. studentAnswer 为空时 mistakeCategory 必须为 null，mistakeReason 必须为空字符串。
5. evidence 和 uncertainties 使用 Contract V2 的对象结构。''';
  }

  Map<String, dynamic>? responseFormat(AiStructuredOutputMode mode) {
    switch (mode) {
      case AiStructuredOutputMode.jsonSchema:
        return <String, dynamic>{
          'type': 'json_schema',
          'json_schema': <String, dynamic>{
            'name': 'ai_wrong_notebook_analysis_v2',
            'strict': true,
            'schema': analysisJsonSchema,
          },
        };
      case AiStructuredOutputMode.jsonObject:
        return const <String, dynamic>{'type': 'json_object'};
      case AiStructuredOutputMode.jsonMimeType:
      case AiStructuredOutputMode.promptOnly:
        return null;
    }
  }

  static final Map<String, dynamic> analysisJsonSchema = <String, dynamic>{
    'type': 'object',
    'additionalProperties': false,
    'required': <String>[
      'schemaVersion',
      'promptVersion',
      'modelName',
      'subject',
      'confidence',
      'uncertainties',
      'evidence',
      'mistakeCategory',
      'originalQuestion',
      'normalizedQuestion',
      'studentAnswer',
      'standardAnswer',
      'solutionSteps',
      'knowledgePoints',
      'generatedExercises',
      'mistakeReason',
      'studyAdvice',
      'aiTags',
      'reviewPlan',
      'specializedAnalysis',
    ],
    'properties': <String, dynamic>{
      'schemaVersion': <String, dynamic>{'type': 'integer', 'const': 2},
      'promptVersion': <String, dynamic>{'type': 'string'},
      'modelName': <String, dynamic>{'type': 'string'},
      'subject': <String, dynamic>{'type': 'string'},
      'confidence': <String, dynamic>{
        'type': 'object',
        'additionalProperties': false,
        'required': <String>['overall', 'fields'],
        'properties': <String, dynamic>{
          'overall': _scoreSchema,
          'fields': <String, dynamic>{
            'type': 'object',
            'additionalProperties': _scoreSchema,
          },
        },
      },
      'uncertainties': <String, dynamic>{
        'type': 'array',
        'items': _objectSchema(
          required: const <String>['field', 'description', 'suggestedAction'],
          properties: <String, dynamic>{
            'field': _stringSchema,
            'description': _stringSchema,
            'suggestedAction': _stringSchema,
          },
        ),
      },
      'evidence': <String, dynamic>{
        'type': 'array',
        'items': _objectSchema(
          required: const <String>[
            'field',
            'source',
            'quote',
            'explanation',
            'stepIndex',
          ],
          properties: <String, dynamic>{
            'field': _stringSchema,
            'source': <String, dynamic>{
              'type': 'string',
              'enum': <String>[
                'image',
                'originalQuestion',
                'normalizedQuestion',
                'studentAnswer',
                'solutionStep',
                'modelInference',
              ],
            },
            'quote': _stringSchema,
            'explanation': _stringSchema,
            'stepIndex': <String, dynamic>{
              'anyOf': <Map<String, dynamic>>[
                <String, dynamic>{'type': 'integer'},
                <String, dynamic>{'type': 'null'},
              ],
            },
          },
        ),
      },
      'mistakeCategory': <String, dynamic>{
        'anyOf': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'string',
            'enum': <String>[
              'concept',
              'comprehension',
              'calculation',
              'strategy',
              'format',
              'careless',
            ],
          },
          <String, dynamic>{'type': 'null'},
        ],
      },
      for (final key in <String>[
        'originalQuestion',
        'normalizedQuestion',
        'studentAnswer',
        'standardAnswer',
        'mistakeReason',
        'studyAdvice',
      ])
        key: _stringSchema,
      for (final key in <String>[
        'solutionSteps',
        'knowledgePoints',
        'aiTags',
      ])
        key: <String, dynamic>{'type': 'array', 'items': _stringSchema},
      'generatedExercises': <String, dynamic>{
        'type': 'array',
        'items': _objectSchema(
          required: const <String>[
            'id',
            'difficulty',
            'question',
            'options',
            'answer',
            'explanation',
            'diagramData',
          ],
          properties: <String, dynamic>{
            'id': _stringSchema,
            'difficulty': _stringSchema,
            'question': _stringSchema,
            'options': <String, dynamic>{
              'type': 'array',
              'minItems': 4,
              'maxItems': 4,
              'items': _stringSchema,
            },
            'answer': _stringSchema,
            'explanation': _stringSchema,
            'diagramData': <String, dynamic>{},
          },
        ),
      },
      'reviewPlan': _objectSchema(
        required: const <String>['reviewAfterDays', 'focus', 'reason'],
        properties: <String, dynamic>{
          'reviewAfterDays': <String, dynamic>{
            'type': 'integer',
            'minimum': 0,
          },
          'focus': <String, dynamic>{'type': 'array', 'items': _stringSchema},
          'reason': _stringSchema,
        },
      ),
      'specializedAnalysis': <String, dynamic>{
        'anyOf': <Map<String, dynamic>>[
          _objectSchema(
            required: const <String>[
              'profile',
              'givens',
              'goal',
              'entities',
              'relations',
              'constraints',
              'reasoningSteps',
              'verification',
              'risks',
              'isModelProvided',
            ],
            properties: <String, dynamic>{
              'profile': <String, dynamic>{
                'type': 'string',
                'enum': <String>[
                  'algebraEquation',
                  'equationSystem',
                  'geometry',
                  'proofArgument',
                ],
              },
              for (final key in <String>[
                'givens',
                'entities',
                'relations',
                'constraints',
                'verification',
                'risks',
              ])
                key: <String, dynamic>{
                  'type': 'array',
                  'items': _stringSchema,
                },
              'goal': _stringSchema,
              'reasoningSteps': <String, dynamic>{
                'type': 'array',
                'items': _objectSchema(
                  required: const <String>[
                    'index',
                    'statement',
                    'basis',
                    'dependsOn',
                  ],
                  properties: <String, dynamic>{
                    'index': <String, dynamic>{'type': 'integer'},
                    'statement': _stringSchema,
                    'basis': _stringSchema,
                    'dependsOn': <String, dynamic>{
                      'type': 'array',
                      'items': <String, dynamic>{'type': 'integer'},
                    },
                  },
                ),
              },
              'isModelProvided': <String, dynamic>{'type': 'boolean'},
            },
          ),
          <String, dynamic>{'type': 'null'},
        ],
      },
    },
  };

  static const Map<String, dynamic> _scoreSchema = <String, dynamic>{
    'type': 'number',
    'minimum': 0,
    'maximum': 1,
  };
  static const Map<String, dynamic> _stringSchema = <String, dynamic>{
    'type': 'string',
  };

  static Map<String, dynamic> _objectSchema({
    required List<String> required,
    required Map<String, dynamic> properties,
  }) =>
      <String, dynamic>{
        'type': 'object',
        'additionalProperties': false,
        'required': required,
        'properties': properties,
      };
}

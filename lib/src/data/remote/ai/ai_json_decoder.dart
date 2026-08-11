import 'dart:convert';

import 'package:crypto/crypto.dart';

enum AiJsonRepairStrategy { none, invalidEscapes, flatFieldRecovery }

class AiJsonDecodeResult {
  const AiJsonDecodeResult({
    required this.value,
    required this.repairStrategy,
    required this.markdownWrapped,
    required this.contentLength,
    required this.contentFingerprint,
  });

  final Map<String, dynamic> value;
  final AiJsonRepairStrategy repairStrategy;
  final bool markdownWrapped;
  final int contentLength;
  final String contentFingerprint;

  String get diagnosticSummary =>
      'length=$contentLength, fingerprint=$contentFingerprint, '
      'markdownWrapped=$markdownWrapped, repair=${repairStrategy.name}, '
      'keys=${value.keys.toList(growable: false)}';
}

class AiJsonDecodingException implements Exception {
  const AiJsonDecodingException(this.inner);

  final Object inner;

  @override
  String toString() => 'AI JSON decode failed: $inner';
}

/// Dependency-light decoder for model JSON.
///
/// It never logs or exposes the raw response through diagnostics. Repair is
/// deliberately limited to JSON string newlines/LaTeX escapes and a final
/// flat-field recovery path for legacy V1 payloads.
class AiJsonDecoder {
  const AiJsonDecoder();

  AiJsonDecodeResult decode(String content) {
    final stripped = _stripJsonFence(content);
    final fingerprint = sha256.convert(utf8.encode(content)).toString().substring(0, 12);

    try {
      return _result(
        _decodeMap(stripped.json),
        content: content,
        fingerprint: fingerprint,
        markdownWrapped: stripped.markdownWrapped,
        strategy: AiJsonRepairStrategy.none,
      );
    } catch (firstError) {
      final repaired = _repairInvalidJsonStringEscapes(stripped.json);
      if (repaired != stripped.json) {
        try {
          return _result(
            _decodeMap(repaired),
            content: content,
            fingerprint: fingerprint,
            markdownWrapped: stripped.markdownWrapped,
            strategy: AiJsonRepairStrategy.invalidEscapes,
          );
        } catch (_) {
          // Continue to the conservative legacy flat-field recovery below.
        }
      }

      final recovered = _recoverFlatJsonFields(repaired);
      if (recovered.isNotEmpty) {
        return _result(
          recovered,
          content: content,
          fingerprint: fingerprint,
          markdownWrapped: stripped.markdownWrapped,
          strategy: AiJsonRepairStrategy.flatFieldRecovery,
        );
      }
      throw AiJsonDecodingException(firstError);
    }
  }

  AiJsonDecodeResult _result(
    Map<String, dynamic> value, {
    required String content,
    required String fingerprint,
    required bool markdownWrapped,
    required AiJsonRepairStrategy strategy,
  }) {
    return AiJsonDecodeResult(
      value: _normalizeParsedJsonStrings(value),
      repairStrategy: strategy,
      markdownWrapped: markdownWrapped,
      contentLength: content.length,
      contentFingerprint: fingerprint,
    );
  }

  Map<String, dynamic> _decodeMap(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      throw const FormatException('AI JSON 顶层必须是对象');
    }
    return Map<String, dynamic>.from(decoded);
  }

  _StrippedJson _stripJsonFence(String content) {
    final trimmed = content.trim();
    final match = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    return _StrippedJson(
      json: match?.group(1)?.trim() ?? trimmed,
      markdownWrapped: match != null,
    );
  }

  Map<String, dynamic> _recoverFlatJsonFields(String jsonText) {
    final result = <String, dynamic>{};
    final keyPattern = RegExp(r'"([^"\\]+)"\s*:');
    final matches = keyPattern.allMatches(jsonText).toList();

    for (var index = 0; index < matches.length; index++) {
      final key = matches[index].group(1)!;
      final valueStart = matches[index].end;
      final valueEnd = index + 1 < matches.length
          ? matches[index + 1].start
          : jsonText.lastIndexOf('}');
      if (valueEnd <= valueStart) continue;

      final rawValue = jsonText
          .substring(valueStart, valueEnd)
          .trim()
          .replaceFirst(RegExp(r',$'), '')
          .trim();
      if (rawValue.startsWith('"')) {
        result[key] = _recoverJsonStringValue(rawValue);
      } else if (rawValue.startsWith('[')) {
        result[key] = _recoverJsonStringArray(rawValue);
      }
    }
    return result;
  }

  String _recoverJsonStringValue(String rawValue) {
    final start = rawValue.indexOf('"');
    final end = rawValue.lastIndexOf('"');
    if (start < 0 || end <= start) return '';
    return rawValue
        .substring(start + 1, end)
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r');
  }

  List<String> _recoverJsonStringArray(String rawValue) {
    final items = <String>[];
    final pattern = RegExp(r'"((?:\\.|[^"\\])*)"', dotAll: true);
    for (final match in pattern.allMatches(rawValue)) {
      items.add(
        match.group(1)!.replaceAll(r'\n', '\n').replaceAll(r'\r', '\r'),
      );
    }
    return items;
  }

  Map<String, dynamic> _normalizeParsedJsonStrings(Map<String, dynamic> map) =>
      map.map(
        (key, value) => MapEntry(key, _normalizeParsedJsonValue(value)),
      );

  dynamic _normalizeParsedJsonValue(dynamic value) {
    if (value is String) return _normalizeLatexControlEscapes(value);
    if (value is List) return value.map(_normalizeParsedJsonValue).toList();
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key, _normalizeParsedJsonValue(item)),
      );
    }
    return value;
  }

  String _normalizeLatexControlEscapes(String value) => value
      .replaceAll(r'\\', r'\')
      .replaceAll('\b', r'\b')
      .replaceAll('\f', r'\f')
      .replaceAll('\t', r'\t');

  String _repairInvalidJsonStringEscapes(String jsonText) {
    final buffer = StringBuffer();
    var inString = false;
    var escapeRun = 0;

    for (var index = 0; index < jsonText.length; index++) {
      final char = jsonText[index];
      final escaped = escapeRun.isOdd;

      if (char == '"' && !escaped) {
        inString = !inString;
        buffer.write(char);
        escapeRun = 0;
        continue;
      }
      if (inString && (char == '\n' || char == '\r')) {
        buffer.write(char == '\n' ? r'\n' : r'\r');
        escapeRun = 0;
        continue;
      }
      if (char == r'\') {
        if (inString) {
          if (escaped) {
            buffer.write(char);
            escapeRun++;
            continue;
          }
          final next = index + 1 < jsonText.length ? jsonText[index + 1] : '';
          final nextNext =
              index + 2 < jsonText.length ? jsonText[index + 2] : '';
          if (next.isEmpty || !_isValidJsonEscape(next, nextNext)) {
            buffer.write(r'\\');
            escapeRun = 0;
            continue;
          }
        }
        buffer.write(char);
        escapeRun++;
        continue;
      }
      buffer.write(char);
      escapeRun = 0;
    }
    return buffer.toString();
  }

  bool _isValidJsonEscape(String next, String nextNext) {
    if ('"\\/u'.contains(next)) return true;
    return 'bfnrt'.contains(next) && !_isAsciiLetter(nextNext);
  }

  bool _isAsciiLetter(String value) {
    if (value.isEmpty) return false;
    final code = value.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }
}

class _StrippedJson {
  const _StrippedJson({required this.json, required this.markdownWrapped});

  final String json;
  final bool markdownWrapped;
}

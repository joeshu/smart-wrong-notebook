import 'dart:convert';
import 'dart:io';

/// 安全写入导出文件：临时文件完成后再替换正式文件，避免留下半成品。
class ExportFileWriter {
  const ExportFileWriter._();

  static Future<File> writeTextAtomic(
    File target,
    String content, {
    Encoding encoding = utf8,
  }) async {
    final temp = File('${target.path}.tmp');
    try {
      await temp.writeAsString(content, flush: true, encoding: encoding);
      if (await target.exists()) await target.delete();
      return await temp.rename(target.path);
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  static Future<File> writeBytesAtomic(File target, List<int> bytes) async {
    final temp = File('${target.path}.tmp');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      if (await target.exists()) await target.delete();
      return await temp.rename(target.path);
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  static Future<File> uniqueTarget(Directory directory, String fileName) async {
    await directory.create(recursive: true);
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final extension = dot > 0 ? fileName.substring(dot) : '';
    var candidate = File('${directory.path}/$fileName');
    var index = 2;
    while (await candidate.exists()) {
      candidate = File('${directory.path}/${stem}_$index$extension');
      index++;
    }
    return candidate;
  }
}

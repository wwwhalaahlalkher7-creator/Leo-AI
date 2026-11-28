import 'dart:convert';

/// Shared validation for model-proposed workspace writes.
///
/// Alpha v0.22 intentionally supports a single file directly under a folder
/// explicitly selected by the user. Nested paths, deletion, arbitrary commands
/// and directory creation are deferred until their own threat review.
class WorkspaceWritePolicy {
  const WorkspaceWritePolicy._();

  static const int maxRelativePathBytes = 160;
  static const int maxContentBytes = 16 * 1024;
  static const int maxContentCharacters = 10000;

  static String? validate({
    required String relativePath,
    required String content,
  }) {
    final name = relativePath;
    if (name != name.trim() ||
        name.isEmpty ||
        utf8.encode(name).length > maxRelativePathBytes) {
      return 'اسم الملف فارغ أو يتجاوز الحد المسموح.';
    }
    if (name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\\') ||
        name.contains(':') ||
        name.endsWith('.') ||
        name.endsWith(' ')) {
      return 'يسمح Leo باسم ملف واحد داخل المجلد المختار، دون مسارات فرعية أو انتقال بين المجلدات.';
    }
    if (name.runes.any((rune) => rune < 0x20 || rune == 0x7f) ||
        RegExp(r'[<>:"|?*]').hasMatch(name)) {
      return 'اسم الملف يحتوي على رموز غير مسموح بها.';
    }
    final deviceName = name.split('.').first.toUpperCase();
    if (const {
      'CON',
      'PRN',
      'AUX',
      'NUL',
      'COM1',
      'COM2',
      'COM3',
      'COM4',
      'COM5',
      'COM6',
      'COM7',
      'COM8',
      'COM9',
      'LPT1',
      'LPT2',
      'LPT3',
      'LPT4',
      'LPT5',
      'LPT6',
      'LPT7',
      'LPT8',
      'LPT9',
    }.contains(deviceName)) {
      return 'اسم الملف محجوز في Windows ولا يمكن استخدامه بأمان على النظامين.';
    }
    if (content.runes.length > maxContentCharacters) {
      return 'عدد أحرف المحتوى يتجاوز 10,000 حرف في إصدار Alpha الحالي.';
    }
    if (content.contains('\u0000')) {
      return 'لا يسمح بمحتوى ثنائي أو محرف NUL في ملفات النصوص.';
    }
    if (utf8.encode(content).length > maxContentBytes) {
      return 'حجم المحتوى يتجاوز 16 KiB في إصدار Alpha الحالي.';
    }
    if (content.runes.any(
      (rune) =>
          rune == 0x7f ||
          (rune < 0x20 && rune != 0x09 && rune != 0x0a && rune != 0x0d),
    )) {
      return 'المحتوى يحتوي على محارف تحكم غير مسموح بها.';
    }
    return null;
  }

  /// A bounded, line-oriented preview. The native adapter independently checks
  /// the expected file hash immediately before applying the write.
  static String buildDiff({
    required String before,
    required String after,
    int maxChangedLines = 80,
  }) {
    if (before == after) return 'لا توجد تغييرات.';
    final oldLines = before.isEmpty ? <String>[] : before.split('\n');
    final newLines = after.isEmpty ? <String>[] : after.split('\n');
    var prefix = 0;
    while (prefix < oldLines.length &&
        prefix < newLines.length &&
        oldLines[prefix] == newLines[prefix]) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < oldLines.length - prefix &&
        suffix < newLines.length - prefix &&
        oldLines[oldLines.length - 1 - suffix] ==
            newLines[newLines.length - 1 - suffix]) {
      suffix++;
    }

    final output = <String>[];
    final removedLineCount = oldLines.length - prefix - suffix;
    final addedLineCount = newLines.length - prefix - suffix;
    final changedLinesTruncated =
        removedLineCount > maxChangedLines || addedLineCount > maxChangedLines;
    final contextStart = (prefix - 3).clamp(0, prefix).toInt();
    for (var i = contextStart; i < prefix; i++) {
      output.add('  ${oldLines[i]}');
    }
    output.addAll(
      oldLines
          .skip(prefix)
          .take(oldLines.length - prefix - suffix)
          .take(maxChangedLines)
          .map((line) => '- $line'),
    );
    output.addAll(
      newLines
          .skip(prefix)
          .take(newLines.length - prefix - suffix)
          .take(maxChangedLines)
          .map((line) => '+ $line'),
    );
    final suffixStartOld = oldLines.length - suffix;
    final suffixStart = suffixStartOld.clamp(0, oldLines.length).toInt();
    final suffixCount = suffix.clamp(0, 3).toInt();
    for (var i = suffixStart; i < suffixStart + suffixCount; i++) {
      if (i < oldLines.length) output.add('  ${oldLines[i]}');
    }
    final outputWasTruncated = output.length > maxChangedLines * 2 + 6;
    if (outputWasTruncated) {
      output.removeRange(maxChangedLines * 2 + 6, output.length);
    }
    if (changedLinesTruncated || outputWasTruncated) {
      output.add('… تم اقتطاع بقية المعاينة.');
    }
    if (output.isEmpty) return 'لا توجد تغييرات.';
    return output.join('\n');
  }
}

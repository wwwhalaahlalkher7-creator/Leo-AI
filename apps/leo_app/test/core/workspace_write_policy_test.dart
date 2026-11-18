import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:leo_app/core/tools/workspace_write_policy.dart';

void main() {
  group('WorkspaceWritePolicy', () {
    test('accepts a simple UTF-8 text file', () {
      expect(
        WorkspaceWritePolicy.validate(
          relativePath: 'ملخص المحاضرة.md',
          content: '# ملاحظات\nمحتوى آمن\n',
        ),
        isNull,
      );
    });

    test('rejects absolute paths, traversal and nested paths', () {
      for (final name in [
        '../secret.txt',
        '..',
        '.',
        '/tmp/file.txt',
        r'C:\Users\leo\file.txt',
        'folder/file.txt',
        r'folder\file.txt',
      ]) {
        expect(
          WorkspaceWritePolicy.validate(relativePath: name, content: 'text'),
          isNotNull,
          reason: 'Rejected unsafe path: $name',
        );
      }
    });

    test('rejects Windows device names and reserved filename characters', () {
      for (final name in ['CON', 'nul.txt', 'LPT1.log', 'file:stream', 'bad?.txt', 'trailing.']) {
        expect(
          WorkspaceWritePolicy.validate(relativePath: name, content: 'text'),
          isNotNull,
          reason: 'Rejected unsafe name: $name',
        );
      }
    });

    test('enforces the UTF-8 byte cap, not the Dart character count', () {
      final tooLarge = 'ع' * (WorkspaceWritePolicy.maxContentBytes ~/ 2 + 1);
      expect(utf8.encode(tooLarge).length, greaterThan(WorkspaceWritePolicy.maxContentBytes));
      expect(
        WorkspaceWritePolicy.validate(relativePath: 'large.txt', content: tooLarge),
        isNotNull,
      );
    });

    test('rejects NUL and prohibited control characters but allows newlines', () {
      expect(
        WorkspaceWritePolicy.validate(relativePath: 'bad.txt', content: 'a\u0000b'),
        isNotNull,
      );
      expect(
        WorkspaceWritePolicy.validate(relativePath: 'bad.txt', content: 'a\u0001b'),
        isNotNull,
      );
      expect(
        WorkspaceWritePolicy.validate(relativePath: 'good.txt', content: 'a\tb\r\nc'),
        isNull,
      );
    });


    test('accepts the exact UTF-8 byte boundary when character count is lower', () {
      final content = 'ع' * (WorkspaceWritePolicy.maxContentBytes ~/ 2);
      expect(utf8.encode(content).length, WorkspaceWritePolicy.maxContentBytes);
      expect(content.runes.length, lessThan(WorkspaceWritePolicy.maxContentCharacters));
      expect(
        WorkspaceWritePolicy.validate(relativePath: 'arabic.txt', content: content),
        isNull,
      );
    });

    test('rejects a code-point count above the limit even when bytes are small', () {
      final content = 'a' * (WorkspaceWritePolicy.maxContentCharacters + 1);
      expect(utf8.encode(content).length, lessThan(WorkspaceWritePolicy.maxContentBytes));
      expect(
        WorkspaceWritePolicy.validate(relativePath: 'long.txt', content: content),
        isNotNull,
      );
    });

    test('rejects whitespace-padded and UTF-8 byte-overlong filenames', () {
      for (final name in [' leading.txt', 'trailing.txt ', 'ع' * 81]) {
        expect(
          WorkspaceWritePolicy.validate(relativePath: name, content: 'text'),
          isNotNull,
          reason: 'Rejected unsafe filename: $name',
        );
      }
    });

    test('truncates long diff previews and clearly marks the truncation', () {
      final before = List.generate(200, (index) => 'old-$index').join('\n');
      final after = List.generate(200, (index) => 'new-$index').join('\n');
      final diff = WorkspaceWritePolicy.buildDiff(before: before, after: after);
      expect(diff, contains('تم اقتطاع بقية المعاينة'));
      expect(diff.split('\n').length, lessThanOrEqualTo(WorkspaceWritePolicy.maxContentCharacters));
    });

    test('diff preview shows removed and added lines with context', () {
      final diff = WorkspaceWritePolicy.buildDiff(
        before: 'first\nold value\nlast',
        after: 'first\nnew value\nlast',
      );
      expect(diff, contains('  first'));
      expect(diff, contains('- old value'));
      expect(diff, contains('+ new value'));
      expect(diff, contains('  last'));
    });
  });
}

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/a11y/ui_copy_lint.dart';

void main() {
  group('UI-copy dash lint (Task 29, NFR-10, AT-24)', () {
    test('flags an em-dash inside a string literal', () {
      const src = "const label = 'Replies unavailable \u2014 try later';";
      final v = scanSource(src, filePath: 'sample.dart');
      expect(v, hasLength(1));
      expect(v.single.character, '\u2014');
      expect(v.single.line, 1);
    });

    test('flags an en-dash inside a string literal', () {
      const src = 'const label = "Open 9\u20135";';
      final v = scanSource(src, filePath: 'sample.dart');
      expect(v, hasLength(1));
      expect(v.single.character, '\u2013');
    });

    test('passes clean ASCII copy', () {
      const src = "const label = 'Please leave it at the door';";
      expect(scanSource(src), isEmpty);
    });

    test('a spaced hyphen is allowed', () {
      const src = "const label = 'Replies unavailable - see captions';";
      expect(scanSource(src), isEmpty);
    });

    test('ignores an em-dash in a line comment (comments are not UI copy)', () {
      const src = '// This comment has an em-dash \u2014 and is fine\nconst x = 1;';
      expect(scanSource(src), isEmpty);
    });

    test('ignores an em-dash in a block comment', () {
      const src = '/* block \u2014 comment */\nconst x = 1;';
      expect(scanSource(src), isEmpty);
    });

    test('handles escaped quotes inside strings without losing track', () {
      const src = "const s = 'it\\'s fine \u2014 here';";
      final v = scanSource(src);
      expect(v, hasLength(1));
    });

    test('reports multiple violations across lines with positions', () {
      const src = "const a = 'x\u2014y';\nconst b = 'p\u2013q';";
      final v = scanSource(src);
      expect(v, hasLength(2));
      expect(v[0].line, 1);
      expect(v[1].line, 2);
    });

    test('the real lib/ tree contains no forbidden dashes (AT-24)', () {
      // Resolve lib/ relative to the package root regardless of the test CWD.
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue, reason: 'run from the app package root');
      final violations = scanDirectory(libDir);
      expect(
        violations,
        isEmpty,
        reason: violations.map((v) => v.toString()).join('\n'),
      );
    });
  });
}

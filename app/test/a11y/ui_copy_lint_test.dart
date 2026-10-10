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

    test('flags an em-dash inside a single-line triple-quoted string (P2-6)', () {
      const src = "const s = '''Replies unavailable \u2014 try later''';";
      final v = scanSource(src, filePath: 'sample.dart');
      expect(v, hasLength(1));
      expect(v.single.character, '\u2014');
    });

    test('flags an en-dash on a later line of a MULTI-LINE triple-quoted string (P2-6)', () {
      // The old line-by-line scanner reset string tracking at each newline and
      // missed a dash on line 2+ of a triple-quoted body.
      const src = "const s = '''\nOpen hours\n9\u20135 daily\n''';";
      final v = scanSource(src, filePath: 'sample.dart');
      expect(v, hasLength(1));
      expect(v.single.character, '\u2013');
      expect(v.single.line, 3); // the dash is on the third line
    });

    test('flags an em-dash inside a double triple-quoted string (P2-6)', () {
      const src = 'const s = """done \u2014 here""";';
      final v = scanSource(src, filePath: 'sample.dart');
      expect(v, hasLength(1));
      expect(v.single.character, '\u2014');
    });

    test('flags a dash inside a raw string (raw copy is still UI copy, P2-6)', () {
      const src = "const s = r'path \u2014 raw';";
      final v = scanSource(src, filePath: 'sample.dart');
      expect(v, hasLength(1));
      expect(v.single.character, '\u2014');
    });

    test('a backslash in a raw string does not swallow a following dash (P2-6)', () {
      // In a raw string the backslash is literal, so the dash after it must
      // still be flagged (the non-raw escape logic must not apply here).
      const src = "const s = r'a\\\u2014b';";
      final v = scanSource(src, filePath: 'sample.dart');
      expect(v, hasLength(1));
      expect(v.single.character, '\u2014');
    });

    test('a clean triple-quoted string passes (P2-6)', () {
      const src = "const s = '''\nAll good here.\nSpaced - hyphen fine.\n''';";
      expect(scanSource(src), isEmpty);
    });

    test('flags a dash written as a \\uXXXX escape (MED-10)', () {
      // The old scanner skipped the escaped char without decoding it, so a dash
      // written as \u2014 bypassed the lint entirely.
      const src = r"const s = 'Replies unavailable \u2014 try later';";
      final v = scanSource(src, filePath: 'sample.dart');
      expect(v, hasLength(1));
      expect(v.single.character, '\u2014');
    });

    test('flags a dash written as a \\u{XXXX} braced escape (MED-10)', () {
      const src = r"const s = 'Open 9\u{2013}5';";
      final v = scanSource(src, filePath: 'sample.dart');
      expect(v, hasLength(1));
      expect(v.single.character, '\u2013');
    });

    test('a non-dash unicode escape still passes (MED-10)', () {
      // A normal escaped character must not be falsely flagged.
      const src = r"const s = 'line one\u000Aline two';";
      expect(scanSource(src), isEmpty);
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

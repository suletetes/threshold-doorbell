// UI-copy dash lint (Task 29, NFR-10; AT-24). Scans Dart source for em-dash and
// en-dash characters inside string literals, which are forbidden in any
// user-facing string (steering/structure.md). This is the shared engine used by
// both the runnable CLI (tool/lint_ui_copy.dart) and the unit test, so CI and the
// test enforce exactly the same rule.

import 'dart:io';

/// Forbidden dash characters (NFR-10). Em-dash, en-dash, figure dash, horizontal bar.
const List<String> kForbiddenDashes = <String>['\u2014', '\u2013', '\u2012', '\u2015'];

/// A single lint finding.
class DashViolation {
  DashViolation({
    required this.filePath,
    required this.line,
    required this.column,
    required this.character,
    required this.snippet,
  });

  final String filePath;
  final int line; // 1-based
  final int column; // 1-based
  final String character;
  final String snippet;

  @override
  String toString() =>
      '$filePath:$line:$column found forbidden dash "${_name(character)}" in: $snippet';

  static String _name(String ch) {
    switch (ch) {
      case '\u2014':
        return 'em-dash';
      case '\u2013':
        return 'en-dash';
      case '\u2012':
        return 'figure-dash';
      case '\u2015':
        return 'horizontal-bar';
      default:
        return 'dash';
    }
  }
}

/// Scan a single unit of Dart [source] for forbidden dashes that appear inside
/// string literals. A best-effort literal scanner tracks single/double quotes
/// and skips line and block comments (comments are not UI copy, per the scope
/// note in structure.md). Returns all violations.
List<DashViolation> scanSource(String source, {String filePath = '<memory>'}) {
  final violations = <DashViolation>[];
  final lines = source.split('\n');

  var inBlockComment = false;
  for (var li = 0; li < lines.length; li++) {
    final line = lines[li];
    var col = 0;
    String? quote; // active string delimiter: "'" or '"' or null
    var inLineComment = false;

    while (col < line.length) {
      final ch = line[col];
      final next = col + 1 < line.length ? line[col + 1] : '';

      if (inBlockComment) {
        if (ch == '*' && next == '/') {
          inBlockComment = false;
          col += 2;
          continue;
        }
        col++;
        continue;
      }

      if (inLineComment) break; // rest of line is a comment

      if (quote == null) {
        // Not inside a string: look for comment starts or string starts.
        if (ch == '/' && next == '/') {
          inLineComment = true;
          break;
        }
        if (ch == '/' && next == '*') {
          inBlockComment = true;
          col += 2;
          continue;
        }
        if (ch == "'" || ch == '"') {
          quote = ch;
          col++;
          continue;
        }
        col++;
        continue;
      }

      // Inside a string literal.
      if (ch == r'\') {
        // Skip the escaped character.
        col += 2;
        continue;
      }
      if (ch == quote) {
        quote = null;
        col++;
        continue;
      }
      if (kForbiddenDashes.contains(ch)) {
        violations.add(
          DashViolation(
            filePath: filePath,
            line: li + 1,
            column: col + 1,
            character: ch,
            snippet: line.trim(),
          ),
        );
      }
      col++;
    }
  }
  return violations;
}

/// Recursively scan all `.dart` files under [root], excluding generated and
/// tooling directories and the lint's own source (which necessarily names the
/// forbidden characters). Returns all violations across the tree.
List<DashViolation> scanDirectory(
  Directory root, {
  Set<String> excludeDirNames = const <String>{
    '.dart_tool',
    'build',
    '.git',
    'ios',
    'android',
    'linux',
    'macos',
    'windows',
    'web',
  },
  Set<String> excludeFileNames = const <String>{
    'ui_copy_lint.dart',
    'ui_copy_lint_test.dart',
  },
}) {
  final violations = <DashViolation>[];
  if (!root.existsSync()) return violations;
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.dart')) continue;
    final segments = entity.uri.pathSegments;
    if (segments.any(excludeDirNames.contains)) continue;
    final name = segments.isNotEmpty ? segments.last : '';
    if (excludeFileNames.contains(name)) continue;
    violations.addAll(scanSource(entity.readAsStringSync(), filePath: entity.path));
  }
  return violations;
}

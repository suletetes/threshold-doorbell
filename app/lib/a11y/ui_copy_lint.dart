// UI-copy dash lint (Task 29, NFR-10; AT-24). Scans Dart source for em-dash and
// en-dash characters inside string literals, which are forbidden in any
// user-facing string (steering/structure.md). This is the shared engine used by
// both the runnable CLI (tool/lint_ui_copy.dart) and the unit test, so CI and the
// test enforce exactly the same rule.

import 'dart:io';

/// Forbidden dash characters (NFR-10). Em-dash, en-dash, figure dash, horizontal bar.
const List<String> kForbiddenDashes = <String>[
  '\u2014',
  '\u2013',
  '\u2012',
  '\u2015'
];

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
/// string literals. A best-effort literal scanner that models:
///   * single- and double-quoted strings ('...' and "..."),
///   * triple-quoted strings ('''...''' and """...""") including MULTI-LINE
///     bodies (a dash on any line of a triple-quoted string is flagged),
///   * raw strings (r'...', r"...", r'''...''', r"""...""") where backslashes
///     are literal so escapes are NOT consumed,
/// and skips line (`//`) and block (`/* */`) comments (comments are not UI copy,
/// per the scope note in structure.md). Returns all violations. The scan runs
/// over the whole source (not line-by-line) so multi-line strings are tracked
/// across newlines.
List<DashViolation> scanSource(String source, {String filePath = '<memory>'}) {
  final violations = <DashViolation>[];

  // Track 1-based line/column as we walk the source.
  var line = 1;
  var col = 1;
  var i = 0;
  final n = source.length;

  String at(int k) => (k >= 0 && k < n) ? source[k] : '';

  // Advance one character, maintaining line/column.
  void advance([int by = 1]) {
    for (var k = 0; k < by && i < n; k++) {
      if (source[i] == '\n') {
        line++;
        col = 1;
      } else {
        col++;
      }
      i++;
    }
  }

  while (i < n) {
    final ch = source[i];
    final next = at(i + 1);

    // Comments (only outside strings, which is where we are here).
    if (ch == '/' && next == '/') {
      // Skip to end of line.
      while (i < n && source[i] != '\n') {
        advance();
      }
      continue;
    }
    if (ch == '/' && next == '*') {
      advance(2);
      while (i < n && !(source[i] == '*' && at(i + 1) == '/')) {
        advance();
      }
      advance(2); // consume the closing */
      continue;
    }

    // String start? Detect an optional raw prefix `r` immediately before a quote.
    var raw = false;
    var quoteStart = i;
    if (ch == 'r' && (next == "'" || next == '"')) {
      raw = true;
      quoteStart = i + 1;
    }
    final q = at(quoteStart);
    if (q == "'" || q == '"') {
      // Triple-quoted when three identical quotes appear together.
      final triple = at(quoteStart + 1) == q && at(quoteStart + 2) == q;
      // Consume the raw prefix (if any) and the opening delimiter.
      if (raw) advance(); // the 'r'
      advance(triple ? 3 : 1); // opening quote(s)
      _consumeStringBody(
        source: source,
        quote: q,
        triple: triple,
        raw: raw,
        // The body scanner needs mutable position; pass via closure state.
        onDash: (dashLine, dashCol, dashCh, snippet) {
          violations.add(DashViolation(
            filePath: filePath,
            line: dashLine,
            column: dashCol,
            character: dashCh,
            snippet: snippet,
          ));
        },
        getIndex: () => i,
        setIndex: (v) => i = v,
        getLine: () => line,
        setLine: (v) => line = v,
        getCol: () => col,
        setCol: (v) => col = v,
        sourceLength: n,
      );
      continue;
    }

    advance();
  }
  return violations;
}

/// Consume a string body starting at the current index (just past the opening
/// delimiter) until the matching closing delimiter, reporting any forbidden dash
/// via [onDash]. Handles raw strings (no escape processing) and triple-quoted
/// (multi-line, closes on three delimiters). Position/line/col are threaded via
/// the getter/setter closures so the outer scanner stays in sync.
void _consumeStringBody({
  required String source,
  required String quote,
  required bool triple,
  required bool raw,
  required void Function(int line, int col, String ch, String snippet) onDash,
  required int Function() getIndex,
  required void Function(int) setIndex,
  required int Function() getLine,
  required void Function(int) setLine,
  required int Function() getCol,
  required void Function(int) setCol,
  required int sourceLength,
}) {
  var i = getIndex();
  var line = getLine();
  var col = getCol();
  final n = sourceLength;

  String at(int k) => (k >= 0 && k < n) ? source[k] : '';

  void step([int by = 1]) {
    for (var k = 0; k < by && i < n; k++) {
      if (source[i] == '\n') {
        line++;
        col = 1;
      } else {
        col++;
      }
      i++;
    }
  }

  String snippetFor(int idx) {
    // The trimmed source line containing index [idx], for readable reports.
    var start = idx;
    while (start > 0 && source[start - 1] != '\n') {
      start--;
    }
    var end = idx;
    while (end < n && source[end] != '\n') {
      end++;
    }
    return source.substring(start, end).trim();
  }

  while (i < n) {
    final ch = source[i];
    // Escapes: only in non-raw strings. DECODE unicode escapes and check the
    // decoded character, so a forbidden dash written as `\u2014` or `\u{2014}`
    // cannot bypass the lint (MED-10). Other escapes (for example `\n`) skip the
    // escaped char as before.
    if (!raw && ch == r'\') {
      final decoded = _decodeUnicodeEscape(source, i, n);
      if (decoded != null) {
        if (kForbiddenDashes.contains(decoded.char)) {
          onDash(line, col, decoded.char, snippetFor(i));
        }
        step(decoded.length);
        continue;
      }
      step(2); // a non-unicode escape: skip the backslash and the escaped char
      continue;
    }
    // Closing delimiter?
    if (ch == quote) {
      if (triple) {
        if (at(i + 1) == quote && at(i + 2) == quote) {
          step(3);
          break;
        }
        // A lone quote inside a triple-quoted string is literal content.
      } else {
        step(1);
        break;
      }
    }
    if (kForbiddenDashes.contains(ch)) {
      onDash(line, col, ch, snippetFor(i));
    }
    step();
  }

  setIndex(i);
  setLine(line);
  setCol(col);
}

/// A decoded unicode escape: the resulting [char] and the [length] of the whole
/// escape sequence in the source (including the leading backslash).
class _DecodedEscape {
  const _DecodedEscape(this.char, this.length);
  final String char;
  final int length;
}

/// Decode a Dart unicode escape starting at [i] (which points at a backslash),
/// supporting `\uXXXX` (exactly four hex digits) and `\u{X...}` (one to six hex
/// digits). Returns null when the sequence at [i] is not a unicode escape, so
/// the caller falls back to the plain two-character escape skip (MED-10).
_DecodedEscape? _decodeUnicodeEscape(String source, int i, int n) {
  String at(int k) => (k >= 0 && k < n) ? source[k] : '';
  if (at(i) != r'\' || at(i + 1) != 'u') return null;
  // Braced form: \u{...}
  if (at(i + 2) == '{') {
    var j = i + 3;
    final hex = StringBuffer();
    while (j < n && source[j] != '}') {
      hex.write(source[j]);
      j++;
    }
    if (j >= n || source[j] != '}') return null; // unterminated
    final code = int.tryParse(hex.toString(), radix: 16);
    if (code == null) return null;
    // length spans \u{...}
    return _DecodedEscape(String.fromCharCode(code), (j - i) + 1);
  }
  // Fixed form: \uXXXX (exactly four hex digits).
  final hex = source.substring(i + 2, (i + 6) <= n ? i + 6 : n);
  if (hex.length < 4) return null;
  final code = int.tryParse(hex, radix: 16);
  if (code == null) return null;
  return _DecodedEscape(String.fromCharCode(code), 6);
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
    violations
        .addAll(scanSource(entity.readAsStringSync(), filePath: entity.path));
  }
  return violations;
}

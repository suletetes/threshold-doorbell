// Runnable UI-copy dash lint (Task 29, NFR-10; AT-24). CI runs this to fail the
// build when an em-dash or en-dash appears in a UI string. Usage:
//
//   dart run tool/lint_ui_copy.dart [path]
//
// Defaults to scanning lib/. Exits 0 when clean, 1 when any violation is found.

import 'dart:io';
import 'package:threshold/a11y/ui_copy_lint.dart';

void main(List<String> args) {
  final target = args.isNotEmpty ? args.first : 'lib';
  final dir = Directory(target);
  if (!dir.existsSync()) {
    stderr.writeln('lint_ui_copy: path not found: $target');
    exit(2);
  }

  final violations = scanDirectory(dir);
  if (violations.isEmpty) {
    stdout.writeln('lint_ui_copy: OK, no forbidden dashes in $target');
    exit(0);
  }

  stderr.writeln(
      'lint_ui_copy: ${violations.length} forbidden dash violation(s):');
  for (final v in violations) {
    stderr.writeln('  $v');
  }
  exit(1);
}

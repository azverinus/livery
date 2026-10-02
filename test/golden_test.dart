import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/golden.dart';

void main() {
  final fixtures =
      Directory(goldensDir).listSync().whereType<Directory>().map((dir) => p.basename(dir.path)).toList()..sort();

  for (final run in fixtures.expand(goldenRuns)) {
    test('golden tree: ${run.description}', () => expectGoldenRun(run));
  }
}

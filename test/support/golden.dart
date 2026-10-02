import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_project.dart';

/// Directory holding one subdirectory per golden fixture.
final goldensDir = p.join('test', 'goldens');

/// Set to `1` to rewrite every golden tree from the current output.
const updateGoldensVariable = 'LIVERY_UPDATE_GOLDENS';

/// Runs the fixture [name] through the CLI and compares the files it generates
/// with the checked-in golden tree.
///
/// A fixture is `<name>/project/`, copied into a scratch directory and run with
/// no arguments from its root, and `<name>/expected/`, every file the run
/// generates. Input files are not part of the expected tree.
void expectGoldenTree(String name) {
  final fixture = p.join(goldensDir, name);
  final project = TestProject.create();
  final inputs = _copyTree(p.join(fixture, 'project'), project.root);

  final result = project.run(const <String>[]);
  expect(result.exitCode, 0, reason: '$result');

  final generated = <String, String>{
    for (final relative in project.files().difference(inputs)) relative: project.read(relative)!,
  };
  final expectedDir = p.join(fixture, 'expected');
  if (Platform.environment[updateGoldensVariable] == '1') {
    _writeTree(expectedDir, generated);
    return;
  }

  expect(Directory(expectedDir).existsSync(), isTrue, reason: 'run with $updateGoldensVariable=1 to create it');
  final expected = <String, String>{
    for (final file in Directory(expectedDir).listSync(recursive: true).whereType<File>())
      p.relative(file.path, from: expectedDir): file.readAsStringSync(),
  };
  expect(generated.keys.toSet(), expected.keys.toSet(), reason: 'generated file set');
  for (final MapEntry(:key, :value) in expected.entries) {
    expect(generated[key], value, reason: key);
  }
}

/// Copies [from] into [to], returning the copied files relative to [to].
Set<String> _copyTree(String from, String to) {
  final copied = <String>{};
  for (final file in Directory(from).listSync(recursive: true).whereType<File>()) {
    final relative = p.relative(file.path, from: from);
    final target = File(p.join(to, relative))..parent.createSync(recursive: true);
    file.copySync(target.path);
    copied.add(relative);
  }

  return copied;
}

void _writeTree(String dir, Map<String, String> files) {
  final directory = Directory(dir);
  if (directory.existsSync()) {
    directory.deleteSync(recursive: true);
  }
  for (final MapEntry(:key, :value) in files.entries) {
    File(p.join(dir, key))
      ..createSync(recursive: true)
      ..writeAsStringSync(value);
  }
}

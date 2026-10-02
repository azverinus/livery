import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'test_project.dart';

/// Directory holding one subdirectory per golden fixture.
final goldensDir = p.join('test', 'goldens');

/// Set to `1` to rewrite every golden tree from the current output.
const updateGoldensVariable = 'LIVERY_UPDATE_GOLDENS';

/// One run of a golden fixture: the arguments it passes and the tree it is
/// expected to generate.
class GoldenRun {
  const GoldenRun._({required this.fixture, required this.name, required this.args});

  final String fixture;

  /// The case name from `runs.yaml`, or `null` for a fixture without one.
  final String? name;
  final List<String> args;

  String get description => name == null ? fixture : '$fixture ($name)';

  String get _expectedDir => p.joinAll(<String>[goldensDir, fixture, 'expected', if (name case final name?) name]);
}

/// The runs of the fixture [fixture].
///
/// A fixture is `<fixture>/project/`, copied into a scratch directory and run
/// from its root, and the files every run generates. Input files are not part
/// of an expected tree.
///
/// Without `<fixture>/runs.yaml` the fixture runs once with no arguments and
/// `<fixture>/expected/` holds its files. `runs.yaml` maps case names to argument
/// lists, and `<fixture>/expected/<case>/` holds the files of each case.
List<GoldenRun> goldenRuns(String fixture) {
  final runsFile = File(p.join(goldensDir, fixture, 'runs.yaml'));
  if (!runsFile.existsSync()) {
    return <GoldenRun>[GoldenRun._(fixture: fixture, name: null, args: const <String>[])];
  }

  final runs = loadYaml(runsFile.readAsStringSync()) as YamlMap;

  return <GoldenRun>[
    for (final MapEntry(:key, :value) in runs.entries)
      GoldenRun._(fixture: fixture, name: key as String, args: <String>[...(value as YamlList).cast<String>()]),
  ];
}

/// Runs [run] through the CLI and compares the files it generates with the
/// checked-in golden tree.
void expectGoldenRun(GoldenRun run) {
  final project = TestProject.create();
  final inputs = _copyTree(p.join(goldensDir, run.fixture, 'project'), project.root);

  final result = project.run(run.args);
  expect(result.exitCode, 0, reason: '$result');

  final generated = <String, String>{
    for (final relative in project.files().difference(inputs)) relative: project.read(relative)!,
  };
  final expectedDir = run._expectedDir;
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

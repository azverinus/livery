import 'dart:io';

import 'package:livery/src/cli_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// What one in-process run of the CLI produced.
class CliResult {
  const CliResult({required this.exitCode, required this.out, required this.err});

  final int exitCode;
  final String out;
  final String err;

  @override
  String toString() => 'exit $exitCode\n--- out\n$out--- err\n$err';
}

/// Scratch project directory, deleted when the test that created it ends.
class TestProject {
  TestProject._(this.root);

  factory TestProject.create() {
    final directory = Directory.systemTemp.createTempSync('livery_test_');
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });

    return TestProject._(directory.resolveSymbolicLinksSync());
  }

  final String root;

  String path(String relative) => p.join(root, relative);

  /// Writes [contents] to [relative], creating parent directories.
  void write(String relative, String contents) {
    File(path(relative))
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);
  }

  void writeManifest(String contents) => write('livery.yaml', contents);

  String? read(String relative) {
    final file = File(path(relative));

    return file.existsSync() ? file.readAsStringSync() : null;
  }

  bool exists(String relative) => FileSystemEntity.typeSync(path(relative)) != FileSystemEntityType.notFound;

  /// Every file under the project, as root-relative paths.
  Set<String> files() =>
      Directory(
        root,
      ).listSync(recursive: true).whereType<File>().map((file) => p.relative(file.path, from: root)).toSet();

  /// Runs the CLI in process with [workingDirectory] relative to the project
  /// root, and an environment holding only [environment].
  CliResult run(
    List<String> args, {
    String workingDirectory = '.',
    Map<String, String> environment = const <String, String>{},
  }) {
    final out = StringBuffer();
    final err = StringBuffer();
    final exitCode = CliRunner(
      out: out,
      err: err,
      environment: environment,
      workingDirectory: p.normalize(path(workingDirectory)),
    ).run(args);

    return CliResult(exitCode: exitCode, out: out.toString(), err: err.toString());
  }
}

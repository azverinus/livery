import 'dart:io';

import 'package:livery/src/cli_runner.dart';

void main(List<String> args) {
  exitCode = CliRunner(
    out: stdout,
    err: stderr,
    environment: Platform.environment,
    workingDirectory: Directory.current.path,
  ).run(args);
}

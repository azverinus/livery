import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'generator.dart';
import 'livery_exception.dart';
import 'manifest.dart';

/// The `livery` command.
///
/// Everything it touches from the outside world comes in through the
/// constructor, so tests run it in process against a scratch directory.
class CliRunner {
  const CliRunner({
    required StringSink out,
    required StringSink err,
    required this.environment,
    required this.workingDirectory,
  }) : _out = out,
       _err = err;

  /// Exit code of a successful run.
  static const success = 0;

  /// Exit code of a run that failed on the manifest or the file system.
  static const failure = 1;

  /// Exit code of a run with bad arguments, as in BSD `sysexits.h`.
  static const usageError = 64;

  static const _usageHeader =
      'Usage: livery [options]\n'
      '\n'
      'Generates build-time config files from a livery.yaml manifest.\n';

  final StringSink _out;
  final StringSink _err;

  /// Process environment the run sees.
  final Map<String, String> environment;

  /// Absolute directory relative paths on the command line resolve against.
  final String workingDirectory;

  static ArgParser _parser() =>
      ArgParser()
        ..addOption(
          'config',
          abbr: 'c',
          help: 'Path to the manifest. Defaults to the nearest ${Manifest.fileName}, searched upwards.',
          valueHelp: 'path',
        )
        ..addOption(
          'root',
          abbr: 'r',
          help: 'Directory output paths resolve against. Defaults to the manifest `root`.',
          valueHelp: 'path',
        )
        ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

  /// Runs the command and returns its exit code.
  int run(List<String> args) {
    final parser = _parser();
    final ArgResults options;
    try {
      options = parser.parse(args);
      if (options.rest.isNotEmpty) {
        throw FormatException('unexpected argument `${options.rest.first}`');
      }
    } on FormatException catch (error) {
      _err
        ..writeln(error.message)
        ..writeln()
        ..writeln(_usageHeader)
        ..writeln(parser.usage);

      return usageError;
    }

    if (options.flag('help')) {
      _out
        ..writeln(_usageHeader)
        ..writeln(parser.usage);

      return success;
    }

    try {
      final manifest = Manifest.load(_manifestPath(options), explicitRoot: _absolute(options.option('root')));
      write(generate(manifest));

      return success;
    } on LiveryException catch (error) {
      _err.writeln('livery: $error');

      return failure;
    }
  }

  String _manifestPath(ArgResults options) {
    final explicit = _absolute(options.option('config'));
    if (explicit != null) {
      return explicit;
    }

    final found = Manifest.find(workingDirectory);
    if (found == null) {
      throw LiveryException('no ${Manifest.fileName} in $workingDirectory or its parents; pass --config');
    }

    return found;
  }

  String? _absolute(String? path) => path == null ? null : p.normalize(p.join(workingDirectory, path));
}

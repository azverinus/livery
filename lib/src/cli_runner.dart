import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'define_sources.dart';
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
        ..addMultiOption(
          'define',
          abbr: 'D',
          // A value may hold a comma, so one option is always one pair.
          splitCommas: false,
          help: 'Define value, repeatable. Wins over every other source.',
          valueHelp: 'KEY=VALUE',
        )
        ..addOption(
          'dart-defines',
          help: 'Encoded dart-defines as the Flutter tool passes them. Wins over \$$dartDefinesVariable.',
          valueHelp: 'base64,...',
        )
        ..addMultiOption(
          'only',
          help: 'Generate only this output, repeatable. Every output is still checked.',
          valueHelp: 'output',
        )
        ..addFlag('dry-run', negatable: false, help: 'Print what would be generated instead of writing files.')
        ..addFlag('verbose', abbr: 'v', negatable: false, help: 'Report the resolved defines and every file written.')
        ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

  /// Runs the command and returns its exit code.
  int run(List<String> args) {
    final parser = _parser();
    final ArgResults options;
    final Map<String, String> assignments;
    try {
      options = parser.parse(args);
      if (options.rest.isNotEmpty) {
        throw FormatException('unexpected argument `${options.rest.first}`');
      }
      assignments = parseAssignments(options.multiOption('define'));
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
      final defineInput = collectDefineInput(
        dartDefinesFile: manifest.dartDefinesFile,
        environment: environment,
        dartDefinesFlag: options.option('dart-defines'),
        assignments: assignments,
      );
      final generation = generate(manifest, defineInput: defineInput, only: options.multiOption('only').toSet());
      final dryRun = options.flag('dry-run');
      final verbose = options.flag('verbose');
      if (dryRun || verbose) {
        _reportResolved(manifest, generation);
      }
      if (dryRun) {
        _printFiles(manifest, generation.files);

        return success;
      }

      final written = write(generation.files);
      if (verbose) {
        _reportWritten(manifest, generation.files, written: written);
      }

      return success;
    } on LiveryException catch (error) {
      _err.writeln('livery: $error');

      return failure;
    }
  }

  /// Prints the manifest, the defines that have a value and the config file
  /// the generation read.
  void _reportResolved(Manifest manifest, Generation generation) {
    final defines = <String>[
      for (final define in generation.defines)
        if (define.value case final value?) '${define.name}=$value',
    ];
    _out
      ..writeln('manifest: ${manifest.path}')
      ..writeln('defines:  ${defines.isEmpty ? '(none)' : defines.join(' ')}');
    if (generation.configFile case final configFile?) {
      _out.writeln('config:   $configFile');
    }
  }

  /// Prints every file's path, format and contents.
  void _printFiles(Manifest manifest, List<GeneratedFile> files) {
    for (final file in files) {
      _out
        ..writeln()
        ..writeln('--- ${p.relative(file.path, from: manifest.rootDir)} (${file.format})')
        ..write(file.contents);
    }
  }

  /// Prints whether each file was [written] or left unchanged.
  void _reportWritten(Manifest manifest, List<GeneratedFile> files, {required Set<String> written}) {
    for (final file in files) {
      final status = written.contains(file.path) ? 'wrote    ' : 'unchanged';
      _out.writeln('$status ${p.relative(file.path, from: manifest.rootDir)}');
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

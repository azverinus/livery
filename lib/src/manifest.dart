import 'dart:io';

import 'package:path/path.dart' as p;

import 'config.dart';
import 'define.dart';
import 'format/formats.dart';
import 'format/output_format.dart';
import 'livery_exception.dart';
import 'yaml_reader.dart';

/// The parsed `livery.yaml`: the defines, where the config is and which
/// outputs to generate.
class Manifest {
  const Manifest._({
    required this.path,
    required this.rootDir,
    required this.defines,
    required this.dartDefinesFile,
    required this.config,
    required this.outputs,
  });

  /// Reads and validates the manifest at the absolute [path].
  ///
  /// [explicitRoot], an absolute path, replaces the manifest's `root`.
  factory Manifest.load(String path, {String? explicitRoot}) {
    final String content;
    try {
      content = File(path).readAsStringSync();
    } on FileSystemException catch (error) {
      throw LiveryException('cannot read the manifest: ${describeFileSystemError(error)}', source: path);
    }

    final reader = YamlReader.parse(content, source: path)..expectKeys(_keys);
    final versionNode = reader.child('version');
    if (versionNode.isNull) {
      throw reader.error('the manifest declares no `version`; add `version: $supportedVersion`', at: 'version');
    }
    final version = versionNode.asInt(orElse: supportedVersion);
    if (version != supportedVersion) {
      throw reader.error(
        'unsupported manifest version $version, livery reads version $supportedVersion',
        at: 'version',
      );
    }

    final root = reader.child('root').asStringOrNull() ?? '.';
    final rootDir = explicitRoot ?? p.normalize(p.join(p.dirname(path), root));
    final dartDefinesFile = reader.child('dart_defines_file').asStringOrNull();

    final defines = _parseDefines(reader.child('defines'));

    return Manifest._(
      path: path,
      rootDir: rootDir,
      defines: defines,
      dartDefinesFile: dartDefinesFile == null ? null : p.normalize(p.join(rootDir, dartDefinesFile)),
      config: Config.parse(config: reader.child('config'), overrides: reader.child('overrides'), defines: defines),
      outputs: _parseOutputs(reader.child('outputs')),
    );
  }

  static const fileName = 'livery.yaml';
  static const supportedVersion = 1;

  static const _keys = <String>{'version', 'root', 'defines', 'dart_defines_file', 'config', 'overrides', 'outputs'};

  /// Absolute path of the manifest file.
  final String path;

  /// Absolute directory output paths resolve against.
  final String rootDir;

  /// Declared defines, in declaration order.
  final List<Define> defines;

  /// Absolute path of the `Generated.xcconfig` define values are read from
  /// first, or `null` when the manifest names none.
  final String? dartDefinesFile;

  /// The base config sections and their overrides.
  final Config config;
  final List<Output> outputs;

  /// The nearest [fileName] in [directory] or one of its parents.
  static String? find(String directory) {
    var current = p.normalize(directory);
    while (true) {
      final candidate = p.join(current, fileName);
      if (FileSystemEntity.isFileSync(candidate)) {
        return candidate;
      }

      final parent = p.dirname(current);
      if (parent == current) {
        return null;
      }
      current = parent;
    }
  }

  static List<Define> _parseDefines(YamlReader reader) => <Define>[
    for (final name in reader.asMap().keys) Define.parse(name, reader.child(name)),
  ];

  static List<Output> _parseOutputs(YamlReader reader) {
    final names = reader.asMap().keys;
    if (names.isEmpty) {
      throw reader.error('the manifest declares no `outputs`');
    }

    return <Output>[for (final name in names) Output._parse(name, reader.child(name))];
  }
}

/// One entry under `outputs`: which sections to merge, in which format, into
/// which files.
class Output {
  const Output._({
    required this.name,
    required this.merge,
    required this.files,
    required this.includeDefines,
    required this.format,
  });

  factory Output._parse(String name, YamlReader reader) {
    final formatId = reader.child('format').asStringOrNull() ?? defaultFormatId;
    final format = formats[formatId];
    if (format == null) {
      throw reader.error('unknown format `$formatId`, known formats are ${formats.keys.join(', ')}', at: 'format');
    }

    reader.expectKeys(<String>{..._keys, ...format.optionKeys});
    final files = reader.child('files').asStringList();
    if (files.isEmpty) {
      throw reader.error('output `$name` declares no `files`', at: 'files');
    }
    final merge = reader.child('merge');

    return Output._(
      name: name,
      merge: merge.isNull ? format.defaultMerge(name) : merge.asStringList(),
      files: files,
      includeDefines: reader.child('include_defines').asBool(orElse: format.includesDefinesByDefault),
      format: format.bind(reader),
    );
  }

  /// Keys every output accepts, whatever its format.
  static const _keys = <String>{'merge', 'format', 'files', 'include_defines'};

  final String name;

  /// Config sections merged left to right; a later section wins.
  final List<String> merge;

  /// Destination paths as written in the manifest, relative to the root.
  final List<String> files;

  /// Whether the output includes the defines, rendered the format's way.
  final bool includeDefines;
  final BoundFormat<Object?> format;
}

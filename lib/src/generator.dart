import 'dart:io';

import 'package:path/path.dart' as p;

import 'format/output_format.dart';
import 'livery_exception.dart';
import 'manifest.dart';
import 'yaml_reader.dart';

/// One file a generation is about to write.
class GeneratedFile {
  const GeneratedFile({required this.path, required this.contents});

  /// Absolute destination path.
  final String path;
  final String contents;
}

/// Renders every output of [manifest] without touching the disk, with the
/// defines resolved from [defineInput], the merged input of every source.
///
/// Everything that can fail on the manifest or the define input fails here, so
/// a failed generation never leaves a half-written set of files behind.
List<GeneratedFile> generate(Manifest manifest, {required Map<String, String> defineInput}) {
  final defines = <ResolvedDefine>[];
  for (final define in manifest.defines) {
    try {
      defines.add(define.resolve(defineInput));
    } on LiveryException catch (error) {
      throw error.located(source: manifest.path, path: 'defines.${define.name}');
    }
  }
  final files = <GeneratedFile>[];
  final firstWriter = <String, String>{};
  for (final output in manifest.outputs) {
    final String contents;
    try {
      contents = output.format.render(
        entries: _entries(manifest, output),
        defines: defines,
        includeDefines: output.includeDefines,
      );
    } on LiveryException catch (error) {
      throw error.located(source: manifest.path, path: 'outputs.${output.name}');
    }

    for (final (index, relative) in output.files.indexed) {
      final location = 'outputs.${output.name}.files[$index]';
      final path = _confine(relative, manifest: manifest, location: location);
      final previous = firstWriter[path];
      if (previous != null) {
        throw LiveryException(
          '`$previous` and `$location` both write to `${p.relative(path, from: manifest.rootDir)}`',
          source: manifest.path,
          path: location,
        );
      }
      firstWriter[path] = location;
      files.add(GeneratedFile(path: path, contents: contents));
    }
  }

  return files;
}

/// Writes [files], leaving a file whose content is already up to date
/// untouched so build systems do not see a spurious change.
void write(List<GeneratedFile> files) {
  for (final file in files) {
    final target = File(file.path);
    try {
      if (target.existsSync() && target.readAsStringSync() == file.contents) {
        continue;
      }
      target
        ..createSync(recursive: true)
        ..writeAsStringSync(file.contents);
    } on FileSystemException catch (error) {
      throw LiveryException('cannot write ${file.path}: ${describeFileSystemError(error)}');
    }
  }
}

/// The absolute path of [relative], which must stay inside the root.
String _confine(String relative, {required Manifest manifest, required String location}) {
  if (p.isAbsolute(relative)) {
    throw LiveryException(
      '`$relative` is absolute; output paths are relative to the root',
      source: manifest.path,
      path: location,
    );
  }

  final path = p.normalize(p.join(manifest.rootDir, relative));
  if (!p.isWithin(manifest.rootDir, path)) {
    throw LiveryException(
      '`$relative` points outside the root ${manifest.rootDir}',
      source: manifest.path,
      path: location,
    );
  }

  return path;
}

/// The sections [output] merges, deep-merged left to right and flattened to
/// leaves.
List<ConfigEntry> _entries(Manifest manifest, Output output) {
  final merged = <String, Object?>{};
  for (final name in output.merge) {
    final section = manifest.config[name];
    if (section == null) {
      throw LiveryException('output `${output.name}` merges section `$name`, which the config does not define');
    }
    _deepMerge(merged, section);
  }

  return <ConfigEntry>[..._flatten(merged, const <String>[])];
}

/// Merges [overlay] into [target]: mappings merge key by key, anything else,
/// lists included, is replaced.
void _deepMerge(YamlTree target, YamlTree overlay) {
  for (final MapEntry(:key, :value) in overlay.entries) {
    final current = target[key];
    if (current is YamlTree && value is YamlTree) {
      _deepMerge(current, value);
    } else {
      target[key] = value is YamlTree ? _copy(value) : value;
    }
  }
}

YamlTree _copy(YamlTree tree) {
  final copy = <String, Object?>{};
  _deepMerge(copy, tree);

  return copy;
}

Iterable<ConfigEntry> _flatten(YamlTree tree, List<String> prefix) sync* {
  for (final MapEntry(:key, :value) in tree.entries) {
    final path = <String>[...prefix, key];
    if (value is YamlTree) {
      yield* _flatten(value, path);
    } else {
      yield ConfigEntry(path: path, kind: _kindOf(value), value: value);
    }
  }
}

ValueKind _kindOf(Object? value) => switch (value) {
  null => ValueKind.none,
  String() => ValueKind.string,
  int() => ValueKind.int,
  double() => ValueKind.double,
  bool() => ValueKind.bool,
  List<Object?>() => ValueKind.list,
  _ => throw StateError('YAML produced an unexpected ${value.runtimeType}'),
};

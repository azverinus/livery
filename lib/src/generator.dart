import 'dart:io';

import 'package:path/path.dart' as p;

import 'config.dart';
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
  final config = manifest.configSource.select(defines);
  final sections = config.resolve(defines);
  final files = <GeneratedFile>[];
  final firstWriter = <String, String>{};
  for (final output in manifest.outputs) {
    final String contents;
    try {
      contents = output.format.render(
        entries: _entries(config.sections, sections, output),
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

/// The [sections] [output] merges, deep-merged left to right and flattened to
/// leaves.
///
/// A key that two of the sections hold must have the same kind in both. The
/// check reads the [base] sections, so its outcome never depends on the
/// defines; overrides cannot change a kind.
List<ConfigEntry> _entries(Map<String, YamlTree> base, Map<String, YamlTree> sections, Output output) {
  final merged = <String, Object?>{};
  final firstSeen = <String, (ValueKind, String)>{};
  for (final name in output.merge) {
    final section = sections[name];
    if (section == null) {
      throw LiveryException('output `${output.name}` merges section `$name`, which the config does not define');
    }

    for (final (path, kind) in _kinds(base[name]!, const <String>[])) {
      final dotted = dottedPath(path);
      final (firstKind, firstSection) = firstSeen.putIfAbsent(dotted, () => (kind, name));
      if (firstKind != kind) {
        throw LiveryException(
          '`$dotted` is ${firstKind.described} in section `$firstSection` but ${kind.described} in section `$name`',
        );
      }
    }
    deepMerge(merged, section);
  }

  return <ConfigEntry>[..._flatten(merged, const <String>[])];
}

/// The key path and kind of every value in [tree], mappings included, parents
/// before their children.
Iterable<(List<String>, ValueKind)> _kinds(YamlTree tree, List<String> prefix) sync* {
  for (final MapEntry(:key, :value) in tree.entries) {
    final path = <String>[...prefix, key];
    yield (path, valueKindOf(value));
    if (value is YamlTree) {
      yield* _kinds(value, path);
    }
  }
}

Iterable<ConfigEntry> _flatten(YamlTree tree, List<String> prefix) sync* {
  for (final MapEntry(:key, :value) in tree.entries) {
    final path = <String>[...prefix, key];
    if (value is YamlTree) {
      yield* _flatten(value, path);
    } else {
      yield ConfigEntry(path: path, kind: valueKindOf(value), value: value);
    }
  }
}

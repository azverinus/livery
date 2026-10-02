import 'package:yaml/yaml.dart';

import 'livery_exception.dart';

/// A plain YAML mapping: string keys, values made of [String], [int],
/// [double], [bool], `null`, [List] and nested mappings.
typedef YamlTree = Map<String, Object?>;

/// Typed, breadcrumb-carrying access to one node of a parsed YAML document.
///
/// Every failure is a [LiveryException] carrying the file and the path inside
/// it, so an error points straight at the offending key.
class YamlReader {
  const YamlReader(this.node, {required this.source, this.path = ''});

  /// Parses [content] read from [source] into plain Dart collections.
  factory YamlReader.parse(String content, {required String source}) {
    final Object? root;
    try {
      root = loadYaml(content, sourceUrl: Uri.file(source));
    } on YamlException catch (error) {
      throw LiveryException('invalid YAML: ${error.message}', source: source);
    }

    return YamlReader(_convert(root, source: source, path: ''), source: source);
  }

  final Object? node;
  final String source;

  /// Dotted location of [node], empty for the document root.
  final String path;

  bool get isNull => node == null;

  LiveryException error(String message, {String? at}) =>
      LiveryException(message, source: source, path: _location(_join(path, at)));

  YamlReader child(String key) => YamlReader(asMap()[key], source: source, path: _join(path, key)!);

  /// Fails on the first key of this mapping that is not in [accepted], naming
  /// it and listing the accepted keys.
  void expectKeys(Iterable<String> accepted) {
    final allowed = accepted.toSet();
    for (final key in asMap().keys) {
      if (!allowed.contains(key)) {
        throw error('unknown key `$key`, accepted keys are ${(allowed.toList()..sort()).join(', ')}', at: key);
      }
    }
  }

  YamlTree asMap() {
    final value = node;
    if (value == null) {
      return const <String, Object?>{};
    }
    if (value is! YamlTree) {
      throw error('expected a mapping, got ${_describe(value)}');
    }

    return value;
  }

  /// Accepts a bare string as well as a list of strings, always returning a
  /// list, so `files: a.txt` works like `files: [a.txt]`.
  List<String> asStringList() {
    final value = node;
    if (value == null) {
      return const <String>[];
    }
    if (value is String) {
      return <String>[value];
    }
    if (value is! List<Object?>) {
      throw error('expected a string or a list of strings, got ${_describe(value)}');
    }

    return <String>[
      for (final (index, item) in value.indexed)
        if (item is String) item else throw error('expected a string, got ${_describe(item)}', at: '[$index]'),
    ];
  }

  String asString() {
    final value = node;
    if (value is! String) {
      throw error('expected a string, got ${_describe(value)}');
    }

    return value;
  }

  String? asStringOrNull() => isNull ? null : asString();

  bool asBool({required bool orElse}) {
    final value = node;
    if (value == null) {
      return orElse;
    }
    if (value is! bool) {
      throw error('expected true or false, got ${_describe(value)}');
    }

    return value;
  }

  int asInt({required int orElse}) {
    final value = node;
    if (value == null) {
      return orElse;
    }
    if (value is! int) {
      throw error('expected an integer, got ${_describe(value)}');
    }

    return value;
  }

  /// Turns `package:yaml` nodes into plain collections, rejecting mapping keys
  /// that are not strings.
  static Object? _convert(Object? value, {required String source, required String path}) {
    if (value is YamlMap) {
      final result = <String, Object?>{};
      for (final MapEntry(:key, value: item) in value.entries) {
        if (key is! String) {
          throw LiveryException(
            'mapping keys must be strings, got ${_describe(key)}',
            source: source,
            path: _location(path),
          );
        }
        result[key] = _convert(item, source: source, path: _join(path, key)!);
      }

      return result;
    }
    if (value is YamlList) {
      return <Object?>[
        for (final (index, item) in value.indexed) _convert(item, source: source, path: '$path[$index]'),
      ];
    }

    return value;
  }

  /// [path] as a breadcrumb, naming the document root when it is empty.
  static String _location(String? path) => path == null || path.isEmpty ? '<root>' : path;

  static String? _join(String prefix, String? key) {
    if (key == null) {
      return prefix.isEmpty ? null : prefix;
    }
    if (key.startsWith('[')) {
      return '$prefix$key';
    }

    return prefix.isEmpty ? key : '$prefix.$key';
  }

  static String _describe(Object? value) => switch (value) {
    null => 'nothing',
    Map<Object?, Object?>() => 'a mapping',
    List<Object?>() => 'a list',
    _ => '`$value`',
  };
}

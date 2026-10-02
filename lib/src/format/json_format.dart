import 'dart:convert';

import '../livery_exception.dart';
import '../yaml_reader.dart';
import 'key_value.dart';
import 'output_format.dart';

/// A JSON object, indented by two spaces, with every value as its JSON type.
///
/// JSON has no comments, so the file has no generated header.
final class JsonFormat extends OutputFormat<KeyValueOptions> {
  const JsonFormat();

  @override
  String get id => 'json';

  @override
  Set<String> get optionKeys => KeyValueOptions.keys;

  @override
  List<String> defaultMerge(String outputName) => <String>[outputName];

  @override
  bool get includesDefinesByDefault => false;

  @override
  KeyValueOptions parseOptions(YamlReader output) => KeyValueOptions.parse(output, flattenByDefault: false);

  @override
  String render(RenderInput<KeyValueOptions> input) {
    final root = <String, Object?>{};
    if (input.options.flatten) {
      for (final (:key, :entry) in flatEntries(input)) {
        root[key] = _checked(entry);
      }
    } else {
      for (final entry in keyValuePayload(input)) {
        var parent = root;
        for (final segment in entry.path.take(entry.path.length - 1)) {
          parent = parent.putIfAbsent(segment, () => <String, Object?>{})! as Map<String, Object?>;
        }
        parent[entry.path.last] = _checked(entry);
      }
    }

    return '${const JsonEncoder.withIndent('  ').convert(root)}\n';
  }

  /// The value of [entry], which must not be or hold a double JSON has no
  /// literal for.
  static Object? _checked(ConfigEntry entry) {
    void check(Object? value) {
      switch (value) {
        case double(isNaN: true):
          throw LiveryException('config key `${dottedPath(entry.path)}` is NaN, which JSON cannot hold');
        case double(isInfinite: true):
          throw LiveryException('config key `${dottedPath(entry.path)}` is infinite, which JSON cannot hold');
        case List<Object?>():
          value.forEach(check);
      }
    }

    check(entry.value);

    return entry.value;
  }
}

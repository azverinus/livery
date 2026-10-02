import '../livery_exception.dart';
import '../yaml_reader.dart';
import 'output_format.dart';

/// Options of a key-value output: whether and how nested keys are joined.
class KeyValueOptions {
  const KeyValueOptions({required this.flatten, required this.separator});

  /// Reads `flatten` and `separator` from [output].
  factory KeyValueOptions.parse(YamlReader output, {required bool flattenByDefault}) => KeyValueOptions(
    flatten: output.child('flatten').asBool(orElse: flattenByDefault),
    separator: output.child('separator').asStringOrNull() ?? '_',
  );

  /// The output keys these options are read from.
  static const keys = <String>{'flatten', 'separator'};

  /// Whether nested keys are joined into one key.
  final bool flatten;

  /// Joins the segments of a nested key.
  final String separator;
}

/// The payload of a key-value format: [RenderInput.entries], followed by the
/// resolved defines as top-level string entries when the output includes them.
///
/// Throws when a declared define has the name of a top-level config key, so
/// one never silently replaces the other.
List<ConfigEntry> keyValuePayload(RenderInput<Object?> input) {
  if (!input.includeDefines) {
    return input.entries;
  }

  final configKeys = <String>{for (final entry in input.entries) entry.path.first};
  for (final define in input.defines) {
    if (configKeys.contains(define.name)) {
      throw LiveryException('define `${define.name}` has the same name as a config key; rename one of them');
    }
  }

  return <ConfigEntry>[
    ...input.entries,
    for (final ResolvedDefine(:name, :value) in input.defines)
      if (value != null) ConfigEntry(path: <String>[name], kind: ValueKind.string, value: value),
  ];
}

/// One entry of a key-value payload with the single key a flat format writes
/// it under.
typedef FlatEntry = ({String key, ConfigEntry entry});

/// The [keyValuePayload] of [input], each entry under one key: its path joined
/// as the options say, then passed through [mapKey].
///
/// Throws when two entries end up under the same key, and, for an output with
/// `flatten: false`, when an entry is nested.
List<FlatEntry> flatEntries(RenderInput<KeyValueOptions> input, {String Function(String key) mapKey = _unchanged}) {
  final options = input.options;
  final firstSource = <String, String>{};
  final flat = <FlatEntry>[];
  for (final entry in keyValuePayload(input)) {
    if (!options.flatten && entry.path.length > 1) {
      throw LiveryException(
        '`${entry.path.first}` is a mapping, which an output with `flatten: false` cannot write; '
        'set `flatten: true`',
      );
    }

    final key = mapKey(entry.path.join(options.separator));
    final source = dottedPath(entry.path);
    final previous = firstSource[key];
    if (previous != null) {
      throw LiveryException(
        'config keys `$previous` and `$source` both become `$key`; rename one of them or change `separator`',
      );
    }
    firstSource[key] = source;
    flat.add((key: key, entry: entry));
  }

  return flat;
}

/// The [flatEntries] of [input] for a format whose keys must be identifiers,
/// such as build setting or shell variable names: a dot in a key becomes
/// `__`, and the key must then match `[A-Za-z_][A-Za-z0-9_]*`.
///
/// Throws for any other key. [format] names the format in that error.
List<FlatEntry> identifierEntries(RenderInput<KeyValueOptions> input, {required String format}) {
  final flat = flatEntries(input, mapKey: (key) => key.replaceAll('.', '__'));
  for (final (:key, :entry) in flat) {
    if (!_identifier.hasMatch(key)) {
      final source = dottedPath(entry.path);
      final becomes = source == key ? '' : ' becomes `$key`, which';
      throw LiveryException(
        'config key `$source`$becomes is not a valid $format key; a key must match `[A-Za-z_][A-Za-z0-9_]*`',
      );
    }
  }

  return flat;
}

/// [value] as the text of a line format: `null` becomes empty and a list
/// becomes comma-joined text.
String flatText(Object? value) => switch (value) {
  null => '',
  List<Object?>() => value.map(flatText).join(','),
  _ => '$value',
};

final _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

String _unchanged(String key) => key;

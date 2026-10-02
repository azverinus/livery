import 'define.dart';
import 'format/output_format.dart';
import 'yaml_reader.dart';

/// The config of an app: base sections plus the overrides that apply to them.
///
/// ```yaml
/// config:
///   android: {api_url: https://dev.example.com}
/// overrides:
///   - when: {ENV: production}
///     set:
///       android: {api_url: https://example.com}
/// ```
///
/// A key's value kind comes from the base config. No override can add a key
/// or change a kind, so every combination of defines yields the same shape.
class Config {
  const Config._({required this.sections, required this.overrides});

  /// Reads the base sections from [config] and the overrides from
  /// [overrides], checking every override against [defines] and the base,
  /// whether or not it would match.
  factory Config.parse({required YamlReader config, required YamlReader overrides, required List<Define> defines}) {
    final result = Config._(
      sections: <String, YamlTree>{
        for (final name in config.asMap().keys)
          name: switch (config.child(name)) {
            final section when section.node is YamlTree => section.asMap(),
            final section => throw section.error('a config section must be a mapping'),
          },
      },
      overrides: <Override>[for (final item in overrides.asList()) Override._parse(item, defines: defines)],
    );

    final problems = <String>[
      for (final override in result.overrides)
        for (final problem in _shapeProblems(result.sections, override.set, const <String>[]))
          '  ${override.location}: $problem',
    ];
    if (problems.isNotEmpty) {
      throw overrides.error(
        'overrides must only set keys of the base config, with the same value types:\n${problems.join('\n')}',
      );
    }

    return result;
  }

  /// Section name to section contents, before any override.
  final Map<String, YamlTree> sections;

  /// Overrides in declaration order.
  final List<Override> overrides;

  /// The sections with every override that matches [defines] merged in, in
  /// declaration order.
  Map<String, YamlTree> resolve(List<ResolvedDefine> defines) {
    final values = <String, String?>{for (final define in defines) define.name: define.value};
    final resolved = deepCopy(sections);
    for (final override in overrides) {
      if (override.matches(values)) {
        deepMerge(resolved, override.set);
      }
    }

    return <String, YamlTree>{for (final MapEntry(:key, :value) in resolved.entries) key: value! as YamlTree};
  }

  /// Why [overlay], found at [path], cannot be merged over [base]: each key
  /// must exist in [base] with a value of the same kind.
  static Iterable<String> _shapeProblems(YamlTree base, YamlTree overlay, List<String> path) sync* {
    for (final MapEntry(:key, :value) in overlay.entries) {
      final keyPath = <String>[...path, key];
      if (!base.containsKey(key)) {
        yield '`${dottedPath(keyPath)}` is not in the base config';
        continue;
      }

      final current = base[key];
      final expected = valueKindOf(current);
      final actual = valueKindOf(value);
      if (expected != actual) {
        yield '`${dottedPath(keyPath)}` is ${expected.described} in the base config, '
            'got ${actual.described}${_hint(expected, value)}';
      } else if (current is YamlTree && value is YamlTree) {
        yield* _shapeProblems(current, value, keyPath);
      }
    }
  }

  /// How to write [value] as [expected], where YAML makes that a matter of
  /// spelling.
  static String _hint(ValueKind expected, Object? value) => switch ((expected, value)) {
    (ValueKind.double, final int value) => '; write `${value.toDouble()}`',
    (ValueKind.int, final double value) when value.isFinite && value == value.truncateToDouble() =>
      '; write `${value.toInt()}`',
    (ValueKind.string, int() || double() || bool()) => '; quote it',
    _ => '',
  };
}

/// One entry under `overrides`: values merged over the base config when every
/// selector in `when` matches the resolved defines.
class Override {
  const Override._({required this.when, required this.set, required this.location});

  factory Override._parse(YamlReader reader, {required List<Define> defines}) {
    reader.expectKeys(_keys);
    final when = reader.child('when');
    final set = reader.child('set');

    return Override._(
      when: <String, List<String>>{
        for (final name in when.asMap().keys) name: _parseSelector(when.child(name), name: name, defines: defines),
      },
      set: set.asMap(),
      location: set.path,
    );
  }

  static const _keys = <String>{'when', 'set'};

  /// Define name to the values that select this override. An empty map
  /// selects every generation.
  final Map<String, List<String>> when;

  /// Values merged over the base config, keyed by section.
  final YamlTree set;

  /// Where [set] is in the manifest, such as `overrides[2].set`.
  final String location;

  /// Whether every selector holds a value of its define in [defines], where
  /// an unresolved define has none and matches nothing.
  bool matches(Map<String, String?> defines) =>
      when.entries.every((selector) => selector.value.contains(defines[selector.key]));

  static List<String> _parseSelector(YamlReader reader, {required String name, required List<Define> defines}) {
    final define = defines.where((define) => define.name == name).firstOrNull;
    if (define == null) {
      throw reader.error(
        defines.isEmpty
            ? '`$name` is not a declared define; the manifest declares no defines'
            : '`$name` is not a declared define; declared defines are ${defines.map((define) => define.name).join(', ')}',
      );
    }

    final values = reader.asStringList();
    if (values.isEmpty) {
      throw reader.error('the selector on `$name` lists no values');
    }
    for (final (index, value) in values.indexed) {
      if (!define.accepts(value)) {
        throw reader.error(
          '`$value` is not a value of define `$name`, expected one of ${define.allowed}',
          at: reader.node is List<Object?> ? '[$index]' : null,
        );
      }
    }

    return values;
  }
}

/// Merges [overlay] into [target]: mappings merge key by key, anything else,
/// lists included, is replaced. A key [target] already holds keeps its place.
void deepMerge(YamlTree target, YamlTree overlay) {
  for (final MapEntry(:key, :value) in overlay.entries) {
    final current = target[key];
    if (current is YamlTree && value is YamlTree) {
      deepMerge(current, value);
    } else {
      target[key] = value is YamlTree ? deepCopy(value) : value;
    }
  }
}

/// A copy of [tree] whose mappings can be merged into without touching
/// [tree].
YamlTree deepCopy(YamlTree tree) {
  final copy = <String, Object?>{};
  deepMerge(copy, tree);

  return copy;
}

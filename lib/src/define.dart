import 'format/output_format.dart';
import 'livery_exception.dart';
import 'yaml_reader.dart';

/// One entry under `defines`: a named string input, optionally limited to a
/// closed set of values, with an optional default.
///
/// ```yaml
/// defines:
///   ENV: {values: [dev, production], default: dev}
///   FLAVOR: [free, paid]   # shorthand for values
///   BUILD_TAG:             # free-form
/// ```
class Define {
  const Define._({
    required this.name,
    required this.values,
    required this.defaultValue,
    required this.required,
    required this.dartClass,
  });

  factory Define.parse(String name, YamlReader reader) {
    if (reader.isNull) {
      return Define._(name: name, values: null, defaultValue: null, required: false, dartClass: null);
    }
    if (reader.node is List<Object?>) {
      return Define._(name: name, values: reader.asStringList(), defaultValue: null, required: false, dartClass: null);
    }

    reader.expectKeys(_keys);
    final valuesNode = reader.child('values');
    final define = Define._(
      name: name,
      values: valuesNode.isNull ? null : valuesNode.asStringList(),
      defaultValue: reader.child('default').asStringOrNull(),
      required: reader.child('required').asBool(orElse: false),
      dartClass: reader.child('dart_class').asStringOrNull(),
    );

    final fallback = define.defaultValue;
    if (fallback != null && !define.accepts(fallback)) {
      throw reader.error('default `$fallback` is not one of ${define.allowed}', at: 'default');
    }

    return define;
  }

  static const _keys = <String>{'values', 'default', 'required', 'dart_class'};

  final String name;

  /// Allowed values in declaration order, or `null` when any value goes.
  final List<String>? values;
  final String? defaultValue;
  final bool required;

  /// Name of the enum the Dart output generates for this define.
  final String? dartClass;

  /// The value of this define given the merged [input] of every source.
  ///
  /// Names and values match exactly, as `String.fromEnvironment` matches them.
  /// A value is trimmed, and an empty one counts as absent.
  ResolvedDefine resolve(Map<String, String> input) {
    final given = input[name]?.trim();
    final value = given == null || given.isEmpty ? defaultValue : given;
    if (value == null) {
      if (required) {
        throw LiveryException('missing required define `$name`${values == null ? '' : ' (one of $allowed)'}');
      }

      return ResolvedDefine(name: name, value: null);
    }
    if (!accepts(value)) {
      throw LiveryException('define `$name` has invalid value `$value`, expected one of $allowed');
    }

    return ResolvedDefine(name: name, value: value);
  }

  /// Whether [value] is one of [values], or any value for a free-form define.
  bool accepts(String value) => values?.contains(value) ?? true;

  /// The accepted values, as an error message lists them. Only for a define
  /// that declares [values].
  String get allowed => values!.join(', ');
}

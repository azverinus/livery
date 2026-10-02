import 'package:path/path.dart' as p;

import '../livery_exception.dart';
import '../yaml_reader.dart';
import 'kotlin_identifier.dart';
import 'output_format.dart';

/// What a `kotlin` output is rendered with. The format has no option keys;
/// the object is named after the output's files.
class KotlinOptions {
  const KotlinOptions({required this.objectName});

  /// Takes the object name from the files of [output], which must all have
  /// the same name.
  factory KotlinOptions.parse(YamlReader output) {
    final files = output.child('files').asStringList();
    final name = p.basenameWithoutExtension(files.first);
    for (final file in files.skip(1)) {
      if (p.basenameWithoutExtension(file) != name) {
        throw output.error(
          '`${files.first}` and `$file` have different names, '
          'and every file of a kotlin output must have the same one',
          at: 'files',
        );
      }
    }
    if (!KotlinIdentifier.isValid(name)) {
      throw output.error(
        '`$name` is not a valid Kotlin identifier, and a kotlin output names its object after the file',
        at: 'files',
      );
    }

    return KotlinOptions(objectName: name);
  }

  /// Name of the generated object.
  final String objectName;
}

/// A Kotlin object in the default package for Gradle build scripts, as
/// decided in ADR-0001: an enum class and a property per constrained define,
/// a property per free-form define, and a constant per config value, all
/// baked in at generation time.
final class KotlinFormat extends OutputFormat<KotlinOptions> {
  const KotlinFormat();

  @override
  String get id => 'kotlin';

  @override
  Set<String> get optionKeys => const <String>{};

  @override
  List<String> defaultMerge(String outputName) => <String>[outputName];

  @override
  bool get includesDefinesByDefault => true;

  @override
  KotlinOptions parseOptions(YamlReader output) => KotlinOptions.parse(output);

  @override
  String render(RenderInput<KotlinOptions> input) {
    final objectName = input.options.objectName;
    final defines = input.includeDefines ? input.defines : const <ResolvedDefine>[];
    final names = _Names(objectName);

    final enumTypes = _enumTypes(defines, names);
    final blocks = <String>[
      for (final block in <List<String>>[
        <String>[
          for (final MapEntry(key: define, value: type) in enumTypes.entries)
            '    enum class ${KotlinIdentifier.escape(type)} ${_enumBody(define)}\n',
        ],
        <String>[for (final define in defines) _property(define, enumType: enumTypes[define], names: names)],
        <String>[for (final entry in input.entries) _constant(entry, names: names)],
      ])
        if (block.isNotEmpty) block.join(),
    ];
    final object = blocks.isEmpty ? 'object $objectName\n' : 'object $objectName {\n${blocks.join('\n')}}\n';

    return '${generatedHeader('//')}$object';
  }

  /// The name of the enum class of each constrained define of [defines], in
  /// declaration order.
  ///
  /// Throws when a name is taken or hides a Kotlin type a member uses.
  static Map<ResolvedDefine, String> _enumTypes(List<ResolvedDefine> defines, _Names names) {
    final types = <ResolvedDefine, String>{};
    for (final define in defines) {
      if (define.values == null) {
        continue;
      }
      final type = names.claim(KotlinIdentifier.upperCamel(define.name), 'the enum class of define `${define.name}`');
      if (_kotlinTypes.contains(type)) {
        throw LiveryException(
          'define `${define.name}` becomes the enum class `$type`, '
          'which hides the Kotlin type `$type`; rename the define',
        );
      }
      types[define] = type;
    }

    return types;
  }

  /// The property line of [define]: the constant of its enum class
  /// [enumType], or its `String` value for a free-form define.
  ///
  /// Only a define that is required or has a default is non-null.
  static String _property(ResolvedDefine define, {required String? enumType, required _Names names}) {
    final name = names.claim(KotlinIdentifier.upperSnake(define.name), 'define `${define.name}`');
    final type = enumType == null ? 'String' : KotlinIdentifier.escape(enumType);
    final nullable = !define.required && define.defaultValue == null;
    final value = define.value;
    final literal = switch (value) {
      null => 'null',
      _ when enumType == null => _literal(value),
      _ => '$type.${KotlinIdentifier.escape(KotlinIdentifier.upperSnake(value))}',
    };

    return '    val ${KotlinIdentifier.escape(name)}: $type${nullable ? '?' : ''} = $literal\n';
  }

  /// The `const val` line of [entry].
  static String _constant(ConfigEntry entry, {required _Names names}) {
    final (type, literal) = _typeAndLiteral(entry);
    final name = names.claim(
      KotlinIdentifier.upperSnake(entry.path.join('_')),
      'config key `${dottedPath(entry.path)}`',
    );

    return '    const val ${KotlinIdentifier.escape(name)}: $type = $literal\n';
  }

  /// The braces and constants of [define]'s enum class.
  static String _enumBody(ResolvedDefine define) {
    final constants = <String, String>{};
    for (final value in define.values!) {
      final constant = KotlinIdentifier.upperSnake(value);
      if (KotlinIdentifier.isReserved(constant)) {
        throw LiveryException(
          'define `${define.name}` value `$value` becomes `$constant`, which is not a usable Kotlin name; rename it',
        );
      }
      final previous = constants[constant];
      if (previous != null) {
        throw LiveryException(
          'define `${define.name}` values `$previous` and `$value` both become '
          'the Kotlin enum constant `$constant`; rename one of them',
        );
      }
      constants[constant] = value;
    }

    return constants.isEmpty ? '{}' : '{ ${constants.keys.map(KotlinIdentifier.escape).join(', ')} }';
  }

  /// The Kotlin type and literal of [entry]'s value.
  static (String, String) _typeAndLiteral(ConfigEntry entry) {
    final key = dottedPath(entry.path);
    Never fail(String what) => throw LiveryException('config key `$key` is $what, which a kotlin output cannot hold');

    return switch (entry.value) {
      final String value => ('String', _literal(value)),
      final int value when value < _minInt || value > _maxInt =>
        throw LiveryException('config key `$key` is $value, outside the range of a Kotlin Int'),
      final int value => ('Int', '$value'),
      double(isNaN: true) => fail('NaN'),
      double(isInfinite: true) => fail('infinite'),
      // Dart writes every double with a decimal point or an exponent.
      final double value => ('Double', '$value'),
      final bool value => ('Boolean', '$value'),
      null => fail('null'),
      _ => fail(entry.kind.described),
    };
  }

  static const _minInt = -2147483648;
  static const _maxInt = 2147483647;

  /// [value] as a double-quoted Kotlin string literal.
  static String _literal(String value) {
    final buffer = StringBuffer('"');
    for (final unit in value.codeUnits) {
      buffer.write(switch (unit) {
        0x5C => r'\\',
        0x22 => r'\"',
        0x24 => r'\$',
        0x0A => r'\n',
        0x0D => r'\r',
        0x09 => r'\t',
        < 0x20 || >= 0x7F && <= 0x9F => '\\u${unit.toRadixString(16).padLeft(4, '0')}',
        _ => String.fromCharCode(unit),
      });
    }
    buffer.write('"');

    return buffer.toString();
  }

  /// Kotlin types a generated member names, which a nested enum class must
  /// not hide.
  static const _kotlinTypes = <String>{'Any', 'Boolean', 'Double', 'Int', 'Nothing', 'String', 'Unit'};
}

/// The names declared in one object, which share one namespace: Kotlin
/// rejects a nested class and a property with the same name.
class _Names {
  _Names(this.objectName);

  final String objectName;
  final _owners = <String, String>{};

  /// Records [name] for [source], as an error message names it.
  ///
  /// Throws when [name] is not usable or another source already has it.
  String claim(String name, String source) {
    if (KotlinIdentifier.isReserved(name)) {
      throw LiveryException('$source becomes `$name`, which is not a usable Kotlin name; rename it');
    }
    final previous = _owners[name];
    if (previous != null) {
      throw LiveryException('$previous and $source both become `$name` in `$objectName`; rename one of them');
    }
    _owners[name] = source;

    return name;
  }
}

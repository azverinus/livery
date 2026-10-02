import 'package:path/path.dart' as p;

import '../livery_exception.dart';
import '../yaml_reader.dart';
import 'dart_identifier.dart';
import 'output_format.dart';

/// Options of a `dart` output.
class DartOptions {
  const DartOptions({required this.className});

  /// Reads `class_name` from [output], deriving it from the first of its
  /// `files` when the output does not set it.
  factory DartOptions.parse(YamlReader output) {
    final className = output.child('class_name').asStringOrNull();
    if (className != null && !DartIdentifier.isValid(className)) {
      throw output.error('`$className` is not a valid Dart identifier', at: 'class_name');
    }

    return DartOptions(className: className ?? _classNameFor(output.child('files').asStringList().first));
  }

  /// The output keys these options are read from.
  static const keys = <String>{'class_name'};

  /// Name of the holder class.
  final String className;

  /// `lib/src/app_config.g.dart` becomes `AppConfig`.
  static String _classNameFor(String path) {
    final name = DartIdentifier.upperCamel(p.basename(path).split('.').first);

    return _startsWithLetter.hasMatch(name) ? name : defaultClassName;
  }

  /// Name of the holder class when the file name gives none.
  static const defaultClassName = 'LiveryValues';

  static final _startsWithLetter = RegExp('^[A-Za-z]');
}

/// A Dart library: an enum per constrained define and a holder class for the
/// free-form defines and the merged config.
///
/// Defines are read back with `String.fromEnvironment`, so they take the
/// values the app is compiled with, and an output without config is the same
/// for every generation. Config values are baked in as constants.
///
/// The file turns the formatter off and is laid out the same whatever the
/// line length, so any project's `dart format` leaves it alone.
final class DartFormat extends OutputFormat<DartOptions> {
  const DartFormat();

  @override
  String get id => 'dart';

  @override
  Set<String> get optionKeys => DartOptions.keys;

  @override
  List<String> defaultMerge(String outputName) => const <String>[];

  @override
  bool get includesDefinesByDefault => true;

  @override
  DartOptions parseOptions(YamlReader output) => DartOptions.parse(output);

  @override
  String render(RenderInput<DartOptions> input) {
    final className = input.options.className;
    final defines = input.includeDefines ? input.defines : const <ResolvedDefine>[];
    final enums = <ResolvedDefine>[
      for (final define in defines)
        if (define.values != null) define,
    ];
    final members = _holderMembers(
      className,
      freeForm: <ResolvedDefine>[
        for (final define in defines)
          if (define.values == null) define,
      ],
      entries: input.entries,
    );

    final parts = <String>[
      for (final (name, define) in _enumNames(enums, holder: members.isEmpty ? null : className)) _enum(name, define),
      if (members.isNotEmpty) _holder(className, members),
    ];
    final header = '// dart format off\n${generatedHeaderLines('//')}// ignore_for_file: type=lint\n';

    return parts.isEmpty ? header : '$header\n${parts.join('\n')}';
  }

  /// Each define of [enums] with the name of its enum.
  ///
  /// Throws when two enums, or an enum and the [holder] class, would have the
  /// same name.
  static List<(String, ResolvedDefine)> _enumNames(List<ResolvedDefine> enums, {required String? holder}) {
    final owners = <String, ResolvedDefine>{};
    final named = <(String, ResolvedDefine)>[];
    for (final define in enums) {
      final dartClass = define.dartClass;
      if (dartClass != null && !DartIdentifier.isValid(dartClass)) {
        throw LiveryException(
          'define `${define.name}` sets `dart_class` to `$dartClass`, which is not a valid Dart identifier',
        );
      }
      final name = dartClass ?? '${DartIdentifier.type(define.name)}Define';
      if (name == holder) {
        throw LiveryException(
          'define `${define.name}` and the holder class both become the Dart class `$name`; '
          'set `dart_class` on the define or `class_name` on the output',
        );
      }
      final previous = owners[name];
      if (previous != null) {
        throw LiveryException(
          'defines `${previous.name}` and `${define.name}` both become the Dart enum `$name`; '
          'set `dart_class` on one of them',
        );
      }
      owners[name] = define;
      named.add((name, define));
    }

    return named;
  }

  static String _enum(String name, ResolvedDefine define) {
    final values = define.values!;
    if (values.isEmpty) {
      throw LiveryException('define `${define.name}` declares no values, and a Dart enum needs at least one');
    }

    final members = <String, String>{};
    for (final value in values) {
      final member = DartIdentifier.enumMember(value, enumName: name);
      final previous = members[member];
      if (previous != null) {
        throw LiveryException(
          'define `${define.name}` values `$previous` and `$value` both become the Dart enum value `$member`; '
          'rename one of them',
        );
      }
      members[member] = value;
    }

    final buffer =
        StringBuffer()
          ..writeln('/// `--dart-define=${_commentSafe(define.name)}=<${_commentSafe(values.join('|'))}>`')
          ..writeln('enum $name {');
    for (final (index, MapEntry(:key, :value)) in members.entries.indexed) {
      buffer.writeln('  $key(${_literal(value)})${index == members.length - 1 ? ';' : ','}');
    }
    buffer
      ..writeln()
      ..writeln('  const $name(this.value);')
      ..writeln()
      ..writeln('  /// The value as spelled in the manifest.')
      ..writeln('  final String value;')
      ..writeln()
      ..writeln('  /// Raw `${_commentSafe(define.name)}` the running app was compiled with.')
      ..writeln('  static const String rawValue = ${_fromEnvironment(define)};')
      ..writeln()
      ..writeln('  /// [rawValue] resolved to a value, `null` when it matches none.')
      ..writeln('  ///')
      ..writeln('  /// Const, so branches on it are resolved at compile time and the')
      ..writeln('  /// unreachable ones are tree-shaken away.')
      ..writeln('  static const $name? maybeCurrent =');
    for (final MapEntry(:key, :value) in members.entries) {
      buffer.writeln('      rawValue == ${_literal(value)} ? $key :');
    }
    buffer
      ..writeln('      null;')
      ..writeln()
      ..writeln('  /// How the app was launched.')
      ..writeln('  ///')
      ..writeln('  /// Throws when `${_commentSafe(define.name)}` holds an undeclared value.')
      ..writeln('  static $name get current =>')
      ..writeln(
        "      maybeCurrent ?? (throw StateError('${_escaped(define.name)}=\$rawValue "
        "is not one of ${_escaped(values.join(', '))}'));",
      )
      ..writeln()
      ..writeln('  /// [value] resolved to a value, `null` when it matches none.')
      ..writeln('  ///')
      ..writeln('  /// Matches exactly, as `String.fromEnvironment` does.')
      ..writeln('  static $name? tryParse(String? value) {')
      ..writeln('    for (final candidate in values) {')
      ..writeln('      if (candidate.value == value) {')
      ..writeln('        return candidate;')
      ..writeln('      }')
      ..writeln('    }')
      ..writeln()
      ..writeln('    return null;')
      ..writeln('  }')
      ..writeln('}');

    return buffer.toString();
  }

  /// The members of the holder class [className], each a block of lines: one
  /// per free-form define, then one with every config constant.
  ///
  /// Throws when two members would have the same name, or when a config value
  /// has no Dart constant type.
  static List<String> _holderMembers(
    String className, {
    required List<ResolvedDefine> freeForm,
    required List<ConfigEntry> entries,
  }) {
    final owners = <String, _Source>{};
    String claim(_Source source) {
      final name = DartIdentifier.constant(source.key, className: className);
      final previous = owners[name];
      if (previous != null) {
        final both =
            previous.kind == source.kind
                ? '${source.kind}s `${previous.name}` and `${source.name}`'
                : '${previous.kind} `${previous.name}` and ${source.kind} `${source.name}`';
        throw LiveryException('$both both become the Dart constant `$name` on `$className`; rename one of them');
      }
      owners[name] = source;

      return name;
    }

    // One block per define, so a blank line separates them.
    final blocks = <String>[];
    for (final define in freeForm) {
      final name = claim((kind: 'define', name: define.name, key: define.name));
      blocks.add(
        '  /// `--dart-define=${_commentSafe(define.name)}=...`\n'
        '  static const String $name = ${_fromEnvironment(define)};\n',
      );
    }
    final constants = StringBuffer();
    for (final entry in entries) {
      final (type, literal) = _typeAndLiteral(entry);
      final name = claim((kind: 'config key', name: dottedPath(entry.path), key: entry.path.join('_')));
      constants.writeln('  static const $type $name = $literal;');
    }
    if (constants.isNotEmpty) {
      blocks.add(constants.toString());
    }

    return blocks;
  }

  static String _holder(String className, List<String> members) =>
      '/// Values resolved by livery.\n'
      '///\n'
      '/// Free-form defines are read at compile time; config values are baked in\n'
      '/// as constants.\n'
      'abstract final class $className {\n'
      '${members.join('\n')}'
      '}\n';

  /// The Dart type and literal of [entry]'s value.
  static (String, String) _typeAndLiteral(ConfigEntry entry) {
    Never fail(String what) =>
        throw LiveryException('config key `${dottedPath(entry.path)}` is $what, which a dart output cannot hold');

    return switch (entry.value) {
      final String value => ('String', _literal(value)),
      final int value => ('int', '$value'),
      double(isNaN: true) => fail('NaN'),
      double(isInfinite: true) => fail('infinite'),
      final double value => ('double', '$value'),
      final bool value => ('bool', '$value'),
      null => fail('null'),
      _ => fail(entry.kind.described),
    };
  }

  /// The `String.fromEnvironment` call that reads [define].
  static String _fromEnvironment(ResolvedDefine define) {
    final fallback = define.defaultValue;

    return 'String.fromEnvironment(${_literal(define.name)}'
        '${fallback == null ? '' : ', defaultValue: ${_literal(fallback)}'})';
  }

  /// [value] as a single-quoted Dart string literal.
  static String _literal(String value) => "'${_escaped(value)}'";

  /// [value] escaped to sit inside a single-quoted Dart string literal.
  static String _escaped(String value) {
    final buffer = StringBuffer();
    for (final unit in value.codeUnits) {
      buffer.write(switch (unit) {
        0x5C => r'\\',
        0x27 => r"\'",
        0x24 => r'\$',
        0x0A => r'\n',
        0x0D => r'\r',
        0x09 => r'\t',
        < 0x20 || 0x7F => '\\x${unit.toRadixString(16).padLeft(2, '0')}',
        _ => String.fromCharCode(unit),
      });
    }

    return buffer.toString();
  }

  /// [text] safe to put on one comment line.
  static String _commentSafe(String text) => text.replaceAll('\n', r'\n').replaceAll('\r', r'\r');
}

/// Where a holder member comes from: a free-form define or a config key.
///
/// [name] is how an error names it and [key] the text its identifier is made
/// from.
typedef _Source = ({String kind, String name, String key});

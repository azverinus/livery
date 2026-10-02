import '../livery_exception.dart';
import '../yaml_reader.dart';
import 'output_format.dart';

/// Options of a `properties` output.
class PropertiesOptions {
  const PropertiesOptions({required this.flatten, required this.separator});

  /// Whether nested keys are joined into one key. Without it every value must
  /// sit directly in a merged section.
  final bool flatten;

  /// Joins the segments of a nested key.
  final String separator;
}

/// Java-style `key=value` lines, the format Gradle's `Properties` reads.
final class PropertiesFormat extends OutputFormat<PropertiesOptions> {
  const PropertiesFormat();

  @override
  String get id => 'properties';

  @override
  Set<String> get optionKeys => const <String>{'flatten', 'separator'};

  @override
  List<String> defaultMerge(String outputName) => <String>[outputName];

  @override
  bool get includesDefinesByDefault => false;

  @override
  PropertiesOptions parseOptions(YamlReader output) => PropertiesOptions(
    flatten: output.child('flatten').asBool(orElse: true),
    separator: output.child('separator').asStringOrNull() ?? '_',
  );

  @override
  String render(RenderInput<PropertiesOptions> input) {
    final buffer = StringBuffer(generatedHeader('#'));
    final firstSource = <String, String>{};
    for (final entry in input.entries) {
      // A dot cannot be used from Gradle or Xcode variable syntax.
      final key = _key(entry.path, input.options).replaceAll('.', '__');
      final previous = firstSource[key];
      if (previous != null) {
        throw LiveryException(
          'config keys `$previous` and `${entry.path.join('.')}` both become `$key`; '
          'rename one of them or change `separator`',
        );
      }
      firstSource[key] = entry.path.join('.');

      buffer
        ..write(_escape(key, isKey: true))
        ..write('=')
        ..write(_escape(_stringify(entry.value), isKey: false))
        ..writeln();
    }

    return buffer.toString();
  }

  static String _key(List<String> path, PropertiesOptions options) {
    if (options.flatten) {
      return path.join(options.separator);
    }
    if (path.length > 1) {
      throw LiveryException(
        '`${path.first}` is a mapping, which a properties output with `flatten: false` cannot write; '
        'set `flatten: true`',
      );
    }

    return path.single;
  }

  /// `null` becomes empty and a list becomes comma-joined text.
  static String _stringify(Object? value) => switch (value) {
    null => '',
    List<Object?>() => value.map(_stringify).join(','),
    _ => '$value',
  };

  /// Escapes what `Properties.load` would otherwise consume as an escape
  /// sequence, a line break or, inside a key, the end of the key.
  ///
  /// Without this a Windows path such as `C:\temp` loses its backslash and a
  /// value holding a newline is read as a second property.
  static String _escape(String raw, {required bool isKey}) {
    final buffer = StringBuffer();
    for (var index = 0; index < raw.length; index++) {
      final char = raw[index];
      switch (char) {
        case r'\':
          buffer.write(r'\\');
        case '\n':
          buffer.write(r'\n');
        case '\r':
          buffer.write(r'\r');
        case '\t':
          buffer.write(r'\t');
        case '\f':
          buffer.write(r'\f');
        case ' ':
          // Java strips leading whitespace from a value, and reads a space in a
          // key as the key/value separator.
          buffer.write(isKey || index == 0 ? r'\ ' : char);
        case '=' || ':' when isKey:
          buffer.write('\\$char');
        case '#' || '!' when index == 0:
          buffer.write('\\$char');
        default:
          buffer.write(char);
      }
    }

    return buffer.toString();
  }
}

import '../yaml_reader.dart';
import 'key_value.dart';
import 'output_format.dart';

/// Java-style `key=value` lines, the format Gradle's `Properties` reads.
final class PropertiesFormat extends OutputFormat<KeyValueOptions> {
  const PropertiesFormat();

  @override
  String get id => 'properties';

  @override
  Set<String> get optionKeys => KeyValueOptions.keys;

  @override
  List<String> defaultMerge(String outputName) => <String>[outputName];

  @override
  bool get includesDefinesByDefault => false;

  @override
  KeyValueOptions parseOptions(YamlReader output) => KeyValueOptions.parse(output, flattenByDefault: true);

  @override
  String render(RenderInput<KeyValueOptions> input) {
    final buffer = StringBuffer(generatedHeader('#'));
    for (final (:key, :entry) in flatEntries(input)) {
      buffer
        ..write(_escape(key, isKey: true))
        ..write('=')
        ..write(_escape(flatText(entry.value), isKey: false))
        ..writeln();
    }

    return buffer.toString();
  }

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

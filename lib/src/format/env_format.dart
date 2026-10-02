import '../yaml_reader.dart';
import 'key_value.dart';
import 'output_format.dart';

/// `KEY=value` lines a POSIX shell can `source`.
final class EnvFormat extends OutputFormat<KeyValueOptions> {
  const EnvFormat();

  @override
  String get id => 'env';

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
    for (final (:key, :entry) in identifierEntries(input, format: id)) {
      buffer
        ..write(key)
        ..write('=')
        ..write(_quote(flatText(entry.value)))
        ..writeln();
    }

    return buffer.toString();
  }

  /// [value] as a shell word: as it is when it holds nothing the shell would
  /// interpret, and in single quotes otherwise, where only `'` itself needs
  /// care: it closes the quotes, adds an escaped `'` and opens them again.
  static String _quote(String value) {
    if (_plain.hasMatch(value)) {
      return value;
    }

    return "'${value.replaceAll("'", r"'\''")}'";
  }

  static final _plain = RegExp(r'^[A-Za-z0-9_./:@=+-]*$');
}

import '../livery_exception.dart';
import '../yaml_reader.dart';
import 'key_value.dart';
import 'output_format.dart';

/// Xcode build settings, `KEY=value` lines an xcconfig file holds.
final class XcconfigFormat extends OutputFormat<KeyValueOptions> {
  const XcconfigFormat();

  @override
  String get id => 'xcconfig';

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
    final buffer = StringBuffer(generatedHeader('//'));
    for (final (:key, :entry) in identifierEntries(input, format: id)) {
      final value = flatText(entry.value);
      if (value.contains(_lineBreak)) {
        throw LiveryException(
          'config key `${dottedPath(entry.path)}` holds a line break, which an xcconfig value cannot hold; '
          'Xcode reads every setting from one line',
        );
      }

      buffer
        ..write(key)
        ..write('=')
        ..write(_escape(value))
        ..writeln();
    }

    return buffer.toString();
  }

  /// Splits every `//` with the empty `$()`, which Xcode expands to nothing.
  ///
  /// Xcode reads `//` as the start of a comment, so `https://example.com`
  /// would otherwise resolve to `https:`. A run of slashes is split between
  /// every pair, so `///` leaves no `//` behind either.
  static String _escape(String value) => value.replaceAll(_slashBeforeSlash, r'/$()');

  static final _slashBeforeSlash = RegExp('/(?=/)');
  static final _lineBreak = RegExp('[\n\r]');
}

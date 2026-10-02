/// Turns define names, define values and config keys into Kotlin identifiers.
///
/// Names are ASCII: every other character becomes `_`, and a name starting
/// with a digit gets a `_` prefix. A name made only of underscores is
/// reserved in Kotlin, and the mapping returns it for the caller to reject.
abstract final class KotlinIdentifier {
  /// `buildTag`, `build-tag` and `BUILD_TAG` all become `BUILD_TAG`.
  static String upperSnake(String raw) => _prefixed(
    raw
        .replaceAllMapped(_camelHump, (match) => '${match[1]}_${match[2]}')
        .replaceAll(_nonIdentifier, '_')
        .toUpperCase(),
  );

  /// `BUILD_MODE` and `build-mode` both become `BuildMode`.
  static String upperCamel(String raw) => _prefixed(
    raw
        .split(_separators)
        .where((word) => word.isNotEmpty)
        .map((word) => _allCaps.hasMatch(word) ? word.toLowerCase() : word)
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(),
  );

  /// Whether [name], as written by the user, can name a Kotlin declaration
  /// without backticks.
  static bool isValid(String name) => _identifier.hasMatch(name) && !isReserved(name) && !_keywords.contains(name);

  /// Whether Kotlin reserves [name], which is the case for a name made only
  /// of underscores, the empty name included.
  static bool isReserved(String name) => _underscores.hasMatch(name);

  /// [identifier] as written in source: in backticks when it is a keyword.
  static String escape(String identifier) => _keywords.contains(identifier) ? '`$identifier`' : identifier;

  static String _prefixed(String identifier) => _leadingDigit.hasMatch(identifier) ? '_$identifier' : identifier;

  static final _camelHump = RegExp('([a-z])([A-Z])');
  static final _nonIdentifier = RegExp('[^A-Za-z0-9_]');
  static final _separators = RegExp('[^A-Za-z0-9]+');
  static final _allCaps = RegExp(r'^[A-Z0-9]+$');
  static final _leadingDigit = RegExp('^[0-9]');
  static final _underscores = RegExp(r'^_*$');
  static final _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  /// Kotlin's hard keywords, which cannot name anything without backticks.
  static const _keywords = <String>{
    'as',
    'break',
    'class',
    'continue',
    'do',
    'else',
    'false',
    'for',
    'fun',
    'if',
    'in',
    'interface',
    'is',
    'null',
    'object',
    'package',
    'return',
    'super',
    'this',
    'throw',
    'true',
    'try',
    'typealias',
    'typeof',
    'val',
    'var',
    'when',
    'while',
  };
}

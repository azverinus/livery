/// Turns define names, define values and config keys into Dart identifiers.
abstract final class DartIdentifier {
  /// `BUILD_TAG` and `build-tag` both become `BuildTag`.
  static String upperCamel(String raw) => _words(raw).map(_capitalize).join();

  /// Name of a type made from [raw]: [upperCamel], with a `V` prefix when it
  /// starts with a digit, so `2FA` becomes `V2fa`.
  static String type(String raw) {
    final identifier = upperCamel(raw);

    return _leadingDigit.hasMatch(identifier) ? 'V$identifier' : identifier;
  }

  /// Whether [name], as written by the user, can name a Dart class.
  static bool isValid(String name) => _identifier.hasMatch(name) && !_reserved.contains(name);

  /// `app_name` becomes `appName`.
  static String lowerCamel(String raw) {
    final identifier = upperCamel(raw);
    if (identifier.isEmpty) {
      return identifier;
    }

    return identifier[0].toLowerCase() + identifier.substring(1);
  }

  /// Name of the enum constant holding [value], kept clear of Dart keywords,
  /// the members of the enum and the enum's own name, [enumName].
  static String enumMember(String value, {required String enumName}) {
    final identifier = _member(value, orElse: 'empty');
    if (_reserved.contains(identifier) || _enumMembers.contains(identifier) || identifier == enumName) {
      return '$identifier\$';
    }

    return identifier;
  }

  /// Name of a static constant of the class [className] holding [raw], kept
  /// clear of Dart keywords, the members every object has and the class's own
  /// name.
  static String constant(String raw, {required String className}) {
    final identifier = _member(raw, orElse: 'value');
    if (_reserved.contains(identifier) || _objectMembers.contains(identifier) || identifier == className) {
      return '$identifier\$';
    }

    return identifier;
  }

  /// [raw] in lowerCamel, [orElse] when it has no letters or digits, and with
  /// a `v` prefix when it starts with a digit.
  static String _member(String raw, {required String orElse}) {
    final identifier = lowerCamel(raw);
    if (identifier.isEmpty) {
      return orElse;
    }

    return _leadingDigit.hasMatch(identifier) ? 'v$identifier' : identifier;
  }

  /// Splits on anything that is not a letter or a digit, then normalises
  /// SCREAMING_CASE parts so `ENV` reads as `Env` rather than `ENV`.
  static List<String> _words(String raw) =>
      raw
          .split(_separators)
          .where((word) => word.isNotEmpty)
          .map((word) => _allCaps.hasMatch(word) ? word.toLowerCase() : word)
          .toList();

  static String _capitalize(String word) => word[0].toUpperCase() + word.substring(1);

  static final _separators = RegExp('[^A-Za-z0-9]+');
  static final _allCaps = RegExp(r'^[A-Z0-9]+$');
  static final _leadingDigit = RegExp('^[0-9]');
  static final _identifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

  /// Words that cannot be used as an identifier at all.
  static const _reserved = <String>{
    'assert',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'default',
    'do',
    'else',
    'enum',
    'extends',
    'false',
    'final',
    'finally',
    'for',
    'if',
    'in',
    'is',
    'new',
    'null',
    'rethrow',
    'return',
    'super',
    'switch',
    'this',
    'throw',
    'true',
    'try',
    'var',
    'void',
    'while',
    'with',
  };

  /// Members every object has, which a static member must not shadow.
  static const _objectMembers = <String>{'hashCode', 'runtimeType', 'toString', 'noSuchMethod'};

  /// Members a generated enum declares or inherits, which a value must not
  /// shadow.
  static const _enumMembers = <String>{
    ..._objectMembers,
    'index',
    'values',
    'value',
    'rawValue',
    'maybeCurrent',
    'current',
    'tryParse',
  };
}

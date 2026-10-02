import 'dart:convert';
import 'dart:io';

import 'livery_exception.dart';

/// Name of the variable, and of the `Generated.xcconfig` setting, that holds
/// Flutter's encoded dart-defines.
const dartDefinesVariable = 'DART_DEFINES';

/// Define input from every source, merged key by key, a later source winning:
///
/// 1. the `DART_DEFINES` line of [dartDefinesFile], an absolute path to a
///    `Generated.xcconfig`, ignored when it does not exist;
/// 2. `DART_DEFINES` in [environment];
/// 3. [dartDefinesFlag], the `--dart-defines` payload;
/// 4. [assignments], the `--define KEY=VALUE` pairs.
///
/// Every key is kept, declared or not; resolution picks the declared ones.
Map<String, String> collectDefineInput({
  required String? dartDefinesFile,
  required Map<String, String> environment,
  required String? dartDefinesFlag,
  required Map<String, String> assignments,
}) => <String, String>{
  if (dartDefinesFile != null) ..._decode(_readXcconfigPayload(dartDefinesFile)),
  ..._decode(environment[dartDefinesVariable]),
  ..._decode(dartDefinesFlag),
  ...assignments,
};

/// Parses `KEY=VALUE` pairs from the command line, a later pair winning.
///
/// Splits on the first `=`, so a value may itself hold one. Throws a
/// [FormatException] on a pair with no `=` or an empty key.
Map<String, String> parseAssignments(Iterable<String> assignments) {
  final result = <String, String>{};
  for (final assignment in assignments) {
    final (key, value) =
        _split(assignment) ?? (throw FormatException('malformed define `$assignment`, expected KEY=VALUE'));
    result[key] = value;
  }

  return result;
}

/// Decodes a `DART_DEFINES` payload: comma-separated, base64-encoded
/// `KEY=VALUE` pairs.
///
/// An entry that is not base64 or has no `=` is skipped, since the payload is
/// Flutter's and livery only reads the keys it declares.
Map<String, String> _decode(String? payload) {
  final result = <String, String>{};
  for (final chunk in payload?.split(',') ?? const <String>[]) {
    final String pair;
    try {
      pair = utf8.decode(base64.decode(base64.normalize(chunk.trim())));
    } on FormatException {
      continue;
    }

    if (_split(pair) case (final key, final value)) {
      result[key] = value;
    }
  }

  return result;
}

/// [pair] split on its first `=`, or `null` when it has no `=` or the key is
/// empty.
(String, String)? _split(String pair) {
  final separator = pair.indexOf('=');

  return separator > 0 ? (pair.substring(0, separator), pair.substring(separator + 1)) : null;
}

/// The value of the `DART_DEFINES` line in the xcconfig at [path], or `null`
/// when the file or the line does not exist.
String? _readXcconfigPayload(String path) {
  final List<String> lines;
  try {
    final file = File(path);
    if (!file.existsSync()) {
      return null;
    }
    lines = file.readAsLinesSync();
  } on FileSystemException catch (error) {
    throw LiveryException('cannot read $path: ${describeFileSystemError(error)}');
  }

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('$dartDefinesVariable=')) {
      return trimmed.substring(dartDefinesVariable.length + 1);
    }
  }

  return null;
}

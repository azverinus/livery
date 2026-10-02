import '../livery_exception.dart';
import 'output_format.dart';

/// The payload of a key-value format: [RenderInput.entries], followed by the
/// resolved defines as top-level string entries when the output includes them.
///
/// Throws when a declared define has the name of a top-level config key, so
/// one never silently replaces the other.
List<ConfigEntry> keyValuePayload(RenderInput<Object?> input) {
  if (!input.includeDefines) {
    return input.entries;
  }

  final configKeys = <String>{for (final entry in input.entries) entry.path.first};
  for (final define in input.defines) {
    if (configKeys.contains(define.name)) {
      throw LiveryException('define `${define.name}` has the same name as a config key; rename one of them');
    }
  }

  return <ConfigEntry>[
    ...input.entries,
    for (final ResolvedDefine(:name, :value) in input.defines)
      if (value != null) ConfigEntry(path: <String>[name], kind: ValueKind.string, value: value),
  ];
}

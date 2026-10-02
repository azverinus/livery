import 'dart:io';

import 'package:path/path.dart' as p;

import 'config.dart';
import 'define.dart';
import 'format/output_format.dart';
import 'livery_exception.dart';
import 'yaml_reader.dart';

/// The config a generation uses, and the file it was read from; `null` for
/// inline config.
typedef SelectedConfig = ({Config config, String? file});

/// Where a manifest's config comes from: inline `config` and `overrides`, one
/// `config_file`, or one file per app through `apps` or `app_pattern`.
///
/// Paths are relative to the manifest's directory.
sealed class ConfigSource {
  const ConfigSource();

  /// Reads the config source of the manifest [manifest], whose overrides may
  /// select on [defines].
  ///
  /// Inline config and a `config_file` are loaded and checked here. App files
  /// are loaded by [select], since a pattern can depend on any define.
  factory ConfigSource.parse(YamlReader manifest, {required List<Define> defines}) {
    final present = <String>[
      for (final key in _sourceKeys)
        if (!manifest.child(key).isNull) key,
    ];
    // Source to the first key that declares it; `overrides` belongs to `config`.
    final sources = <String, String>{};
    for (final key in present) {
      sources.putIfAbsent(key == 'overrides' ? 'config' : key, () => key);
    }
    if (sources.length > 1) {
      final clash = sources.values.toList();
      throw manifest.error('${clash.map((key) => '`$key`').join(' and ')} are mutually exclusive', at: clash.last);
    }

    final source = sources.keys.firstOrNull;
    if (source != 'apps' && source != 'app_pattern') {
      if (!manifest.child('app_define').isNull) {
        throw manifest.error('`app_define` only applies with `apps` or `app_pattern`', at: 'app_define');
      }

      if (source == 'config_file') {
        final configFile = manifest.child('config_file');
        final relative = configFile.asString();

        return _Single((
          config: _loadFile(relative, from: configFile, defines: defines),
          file: _resolve(relative, from: configFile),
        ));
      }

      return _Single((
        config: Config.parse(
          config: manifest.child('config'),
          overrides: manifest.child('overrides'),
          defines: defines,
        ),
        file: null,
      ));
    }

    final appDefine = _appDefine(manifest, location: source!, defines: defines);
    final apps = appDefine.values!;
    if (source == 'apps') {
      return _Apps(
        appDefine: appDefine.name,
        declared: defines,
        location: manifest.child('apps'),
        apps: _parseRegistry(manifest.child('apps'), appDefine: appDefine),
      );
    }

    final pattern = manifest.child('app_pattern');
    final template = _AppPattern.parse(pattern, appDefine: appDefine.name, defines: defines);

    return _Apps(
      appDefine: appDefine.name,
      declared: defines,
      location: pattern,
      apps: <String, _App>{
        for (final app in apps) app: (at: pattern, path: (resolved) => template.substitute(app, resolved)),
      },
    );
  }

  static const _sourceKeys = <String>['config', 'overrides', 'config_file', 'apps', 'app_pattern'];

  /// Manifest keys a config source reads.
  static const keys = <String>{..._sourceKeys, 'app_define'};

  static const _defaultAppDefine = 'APP';

  /// The config this generation uses, given its resolved [defines].
  ///
  /// With several apps, loads and checks every app first, so a broken app
  /// fails whichever app is built.
  SelectedConfig select(List<ResolvedDefine> defines);

  /// The app define: declared, with `values`, and never unresolved.
  static Define _appDefine(YamlReader manifest, {required String location, required List<Define> defines}) {
    final named = manifest.child('app_define');
    final name = named.asStringOrNull() ?? _defaultAppDefine;
    final define = defines.where((define) => define.name == name).firstOrNull;
    if (define == null) {
      throw manifest.error(
        'the app define `$name` is not a declared define',
        at: named.isNull ? location : 'app_define',
      );
    }
    if (define.values?.isEmpty ?? true) {
      throw manifest.error('`$name` selects the app, so it must declare `values`', at: 'defines.$name');
    }
    if (!define.required && define.defaultValue == null) {
      throw manifest.error(
        '`$name` selects the app, so it must be `required` or have a `default`',
        at: 'defines.$name',
      );
    }

    return define;
  }

  /// The `apps` registry, whose keys must be the values of [appDefine].
  static Map<String, _App> _parseRegistry(YamlReader registry, {required Define appDefine}) {
    final apps = appDefine.values!;
    final keys = registry.asMap().keys;
    final problems = <String>[
      for (final app in apps)
        if (!keys.contains(app)) '`$app` has no entry',
      for (final key in keys)
        if (!apps.contains(key)) '`$key` is not a value',
    ];
    if (problems.isNotEmpty) {
      throw registry.error(
        'the apps must be the values of `${appDefine.name}`, ${appDefine.allowed}: ${problems.join(', ')}',
      );
    }

    final result = <String, _App>{};
    for (final app in apps) {
      final entry = registry.child(app);
      final path = entry.asString();
      result[app] = (at: entry, path: (_) => path);
    }

    return result;
  }
}

/// One config, the same for every generation.
final class _Single extends ConfigSource {
  const _Single(this.selected);

  final SelectedConfig selected;

  @override
  SelectedConfig select(List<ResolvedDefine> defines) => selected;
}

/// Where an app's config file is: the manifest entry that names it, and its
/// path given the resolved define values.
typedef _App = ({YamlReader at, String Function(Map<String, String?> defines) path});

/// One config file per app, selected by the app define.
final class _Apps extends ConfigSource {
  const _Apps({required this.appDefine, required this.declared, required this.location, required this.apps});

  final String appDefine;

  /// The manifest's defines, which app files' overrides may select on.
  final List<Define> declared;

  /// The manifest entry the apps come from, `apps` or `app_pattern`.
  final YamlReader location;

  /// App name to its config file, in the app define's value order.
  final Map<String, _App> apps;

  @override
  SelectedConfig select(List<ResolvedDefine> defines) {
    final values = <String, String?>{for (final define in defines) define.name: define.value};
    // Every path first, so a bad pattern value fails before any file is read.
    final files = <String, String>{
      for (final MapEntry(key: app, value: (:path, at: _)) in apps.entries) app: path(values),
    };
    final configs = <String, Config>{
      for (final MapEntry(key: app, value: (:at, path: _)) in apps.entries)
        app: _loadFile(files[app]!, from: at, defines: declared),
    };
    _checkShapes(configs, files: files);
    final app = values[appDefine]!;

    return (config: configs[app]!, file: _resolve(files[app]!, from: apps[app]!.at));
  }

  /// Fails unless every app has the keys and kinds of the first.
  void _checkShapes(Map<String, Config> configs, {required Map<String, String> files}) {
    final MapEntry(key: first, value: reference) = configs.entries.first;
    final problems = <String>[];
    for (final MapEntry(key: app, value: config) in configs.entries.skip(1)) {
      final differences = shapeDifferences(reference.sections, config.sections).toList();
      if (differences.isEmpty) {
        continue;
      }

      String keys(Iterable<ShapeDifference> differences) =>
          differences.map((difference) => '`${dottedPath(difference.path)}`').join(', ');
      final missing = differences.where((difference) => difference.actual == null);
      final extra = differences.where((difference) => difference.expected == null);
      problems.add(
        <String>[
          '  $app (${files[app]}):',
          if (missing.isNotEmpty) '    missing ${keys(missing)}',
          if (extra.isNotEmpty) '    extra ${keys(extra)}',
          for (final difference in differences)
            if (difference case ShapeDifference(:final path, :final expected?, :final actual?))
              '    `${dottedPath(path)}` is ${expected.described} in `$first`, ${actual.described} here',
        ].join('\n'),
      );
    }
    if (problems.isNotEmpty) {
      throw location.error('every app must have the keys and value types of `$first`:\n${problems.join('\n')}');
    }
  }
}

/// An `app_pattern` such as `config/{ENV}/{APP}.yaml`, where each placeholder
/// names a declared define.
class _AppPattern {
  const _AppPattern._(this.reader, {required this.template, required this.appDefine});

  factory _AppPattern.parse(YamlReader reader, {required String appDefine, required List<Define> defines}) {
    final template = reader.asString();
    final names = defines.map((define) => define.name).toList();
    for (final match in _placeholder.allMatches(template)) {
      if (!names.contains(match[1])) {
        throw reader.error('`${match[0]}` is not a declared define; declared defines are ${names.join(', ')}');
      }
    }
    if (!template.contains('{$appDefine}')) {
      throw reader.error('the pattern must contain `{$appDefine}`, the app define');
    }

    return _AppPattern._(reader, template: template, appDefine: appDefine);
  }

  static final _placeholder = RegExp(r'\{([^{}]*)\}');

  final YamlReader reader;
  final String template;
  final String appDefine;

  /// The path of [app]'s config, with the other placeholders replaced by
  /// their [defines] values.
  ///
  /// A value must stay one path segment, so it cannot reach another directory.
  String substitute(String app, Map<String, String?> defines) => template.replaceAllMapped(_placeholder, (match) {
    final name = match[1]!;
    final value = name == appDefine ? app : defines[name];
    if (value == null) {
      throw reader.error('`${match[0]}` has no value: define `$name` is unresolved');
    }
    if (value.contains('/') || value.contains(r'\') || value.contains('..')) {
      throw reader.error('`${match[0]}` would be `$value`; a substituted value must not contain `/`, `\\` or `..`');
    }

    return value;
  });
}

/// The absolute path of [relative], relative to the manifest that declares
/// it at [from].
String _resolve(String relative, {required YamlReader from}) => p.normalize(p.join(p.dirname(from.source), relative));

/// Loads the config file at [relative], relative to the manifest that
/// declares it at [from].
///
/// The file holds only `config` and `overrides`, checked as inline config is.
/// An empty file is more likely a mistake than an empty config, so it fails.
Config _loadFile(String relative, {required YamlReader from, required List<Define> defines}) {
  final path = _resolve(relative, from: from);
  final String content;
  try {
    content = File(path).readAsStringSync();
  } on FileSystemException catch (error) {
    throw from.error('cannot read `$relative`: ${describeFileSystemError(error)}');
  }

  final reader = YamlReader.parse(content, source: path);
  if (reader.isNull) {
    throw reader.error('the config file is empty; expected `config` and `overrides`');
  }
  reader.expectKeys(const <String>{'config', 'overrides'});

  return Config.parse(config: reader.child('config'), overrides: reader.child('overrides'), defines: defines);
}

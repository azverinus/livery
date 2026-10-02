import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/golden.dart';

/// The golden Dart files of the `dart` fixture, checked the way a consuming
/// package sees them: analyzed, format-checked and compiled.
void main() {
  late String package;

  setUpAll(() {
    final directory = Directory.systemTemp.createTempSync('livery_dart_consumer_');
    addTearDown(() => directory.deleteSync(recursive: true));
    package = directory.resolveSymbolicLinksSync();

    _write(package, 'pubspec.yaml', '''
name: consumer
publish_to: none
environment:
  sdk: ^3.7.0
''');
    // A narrow page width that would reflow any long line the formatter saw.
    _write(package, 'analysis_options.yaml', '''
analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
formatter:
  page_width: 40
''');
    final expected = p.join(goldensDir, 'dart', 'expected');
    for (final file in Directory(expected).listSync(recursive: true).whereType<File>()) {
      final relative = p.split(p.relative(file.path, from: expected));
      // <run>/lib/src/<file> becomes lib/<run>/<file>.
      _write(package, p.join('lib', relative.first, relative.last), file.readAsStringSync());
    }
    _write(package, p.join('bin', 'main.dart'), _program);

    _dart(package, <String>['pub', 'get', '--offline']);
  });

  test('golden files pass dart analyze with no issues', () {
    _dart(package, <String>['analyze', '--fatal-infos', '--fatal-warnings']);
  });

  test('golden files pass dart format --set-exit-if-changed', () {
    _dart(package, <String>['format', '--output=none', '--set-exit-if-changed', 'lib']);
  });

  group('compiled with', () {
    Map<String, Object?> runWith(List<String> defines) {
      final output = _dart(package, <String>[
        'run',
        for (final define in defines) '--define=$define',
        p.join('bin', 'main.dart'),
      ]);

      return jsonDecode(output) as Map<String, Object?>;
    }

    test('no defines, the enums read their defaults', () {
      expect(runWith(const <String>[]), <String, Object?>{
        'rawValue': 'dev',
        'maybeCurrent': 'dev',
        'current': 'dev',
        'tryParse(staging)': 'staging',
        'tryParse(STAGING)': null,
        'tryParse(null)': null,
        'edge': null,
        'buildTag': '',
        'channel': 'beta',
        'appName': 'Demo App',
      });
    });

    test('declared values, the enums and the holder read them', () {
      expect(
        runWith(const <String>['ENV=production', 'EDGE=it\'s', 'BUILD_TAG=nightly', 'CHANNEL=alpha']),
        <String, Object?>{
          'rawValue': 'production',
          'maybeCurrent': 'production',
          'current': 'production',
          'tryParse(staging)': 'staging',
          'tryParse(STAGING)': null,
          'tryParse(null)': null,
          'edge': 'itS',
          'buildTag': 'nightly',
          'channel': 'alpha',
          'appName': 'Demo App',
        },
      );
    });

    test('values matched exactly', () {
      expect(runWith(const <String>[r'EDGE=a\b']), containsPair('edge', 'aB'));
      expect(runWith(const <String>[r'EDGE=$x']), containsPair('edge', 'x'));
      expect(runWith(const <String>['EDGE=Default']), containsPair('edge', null));
    });

    test('an undeclared value, maybeCurrent is null and current throws', () {
      expect(
        runWith(const <String>['ENV=Production']),
        allOf(
          containsPair('rawValue', 'Production'),
          containsPair('maybeCurrent', null),
          containsPair('current', 'StateError: ENV=Production is not one of dev, staging, production'),
        ),
      );
    });
  });
}

const _program = r'''
import 'dart:convert';

import 'package:consumer/dev/app_config.g.dart';

void main() {
  String current;
  try {
    current = EnvDefine.current.value;
  } on StateError catch (error) {
    current = 'StateError: ${error.message}';
  }

  print(jsonEncode(<String, Object?>{
    'rawValue': EnvDefine.rawValue,
    'maybeCurrent': EnvDefine.maybeCurrent?.value,
    'current': current,
    'tryParse(staging)': EnvDefine.tryParse('staging')?.value,
    'tryParse(STAGING)': EnvDefine.tryParse('STAGING')?.value,
    'tryParse(null)': EnvDefine.tryParse(null)?.value,
    'edge': Edge.maybeCurrent?.name,
    'buildTag': AppConfig.buildTag,
    'channel': AppConfig.channel,
    'appName': AppConfig.appName,
  }));
}
''';

void _write(String root, String relative, String contents) {
  File(p.join(root, relative))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);
}

/// Runs `dart [args]` in [package], expecting it to succeed, and returns its
/// standard output.
String _dart(String package, List<String> args) {
  final result = Process.runSync(Platform.resolvedExecutable, args, workingDirectory: package);
  expect(result.exitCode, 0, reason: 'dart ${args.join(' ')}\n${result.stdout}${result.stderr}');

  return result.stdout as String;
}

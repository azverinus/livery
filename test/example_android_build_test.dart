@Tags(<String>['gradle'])
@Timeout(Duration(minutes: 15))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/test_project.dart';

/// Builds the Android app of `example/` with the Kotlin object livery
/// generates, the way a user project builds it.
///
/// Skipped by default, see `dart_test.yaml`. It needs Flutter on the `PATH`, a
/// JDK and the Android SDK, and network access for Gradle's first build. Run it
/// with `dart test --tags gradle --run-skipped`.
void main() {
  test('the example builds with the generated object and its values reach the APK', () {
    final app = TestProject.create().root;
    _copyExample(app);
    // The copy is outside the repository, so its `path: ..` no longer points
    // at livery.
    File(p.join(app, 'pubspec_overrides.yaml')).writeAsStringSync('''
dependency_overrides:
  livery:
    path: ${jsonEncode(Directory.current.path)}
''');

    _run(app, 'flutter', <String>['pub', 'get']);
    _run(app, 'dart', <String>['run', 'livery', '-D', 'ENV=staging', '-D', 'BUILD_TAG=ci']);
    _run(app, 'flutter', <String>[
      'build',
      'apk',
      '--debug',
      '--dart-define=ENV=staging',
      '--dart-define=BUILD_TAG=ci',
    ]);

    final metadata =
        jsonDecode(
              File(p.join(app, 'build', 'app', 'outputs', 'apk', 'debug', 'output-metadata.json')).readAsStringSync(),
            )
            as Map<String, Object?>;
    final element = (metadata['elements']! as List<Object?>).single! as Map<String, Object?>;
    expect(metadata['applicationId'], 'dev.livery.example.staging');
    expect(element['versionCode'], 3);
    expect(element['versionName'], '1.0.0-ci');
  });
}

/// Copies the files of `example/` that git tracks or would track into [to],
/// leaving out whatever a local build or run left there.
void _copyExample(String to) {
  final listed = Process.runSync('git', <String>[
    'ls-files',
    '-z',
    '--cached',
    '--others',
    '--exclude-standard',
    '--',
    'example',
  ]);
  expect(listed.exitCode, 0, reason: '${listed.stderr}');

  for (final file in (listed.stdout as String).split('\x00').where((file) => file.isNotEmpty)) {
    final target = File(p.join(to, p.relative(file, from: 'example')))..parent.createSync(recursive: true);
    File(file).copySync(target.path);
  }
}

/// Runs [executable] in [directory], expecting it to succeed.
void _run(String directory, String executable, List<String> args) {
  final result = Process.runSync(executable, args, workingDirectory: directory);
  expect(result.exitCode, 0, reason: '$executable ${args.join(' ')}\n${result.stdout}${result.stderr}');
}

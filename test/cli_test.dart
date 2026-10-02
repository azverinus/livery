import 'package:test/test.dart';

import 'support/test_project.dart';

const _unversioned = '''
config:
  android:
    app_name: Demo
outputs:
  android:
    files: [out/livery.properties]
''';

const _manifest = 'version: 1\n$_unversioned';

void main() {
  test('--help prints usage and exits 0', () {
    final result = TestProject.create().run(const <String>['--help']);

    expect(result.exitCode, 0);
    expect(result.out, contains('Usage: livery'));
    expect(result.out, contains('--config'));
    expect(result.out, contains('--root'));
    expect(result.out, contains('--define'));
    expect(result.out, contains('--dart-defines'));
  });

  test('an unknown option exits 64 with usage', () {
    final result = TestProject.create().run(const <String>['--nope']);

    expect(result.exitCode, 64);
    expect(result.err, contains('Usage: livery'));
  });

  test('a positional argument exits 64 with usage', () {
    final result = TestProject.create().run(const <String>['generate']);

    expect(result.exitCode, 64);
    expect(result.err, contains('unexpected argument `generate`'));
  });

  group('finding the manifest', () {
    test('searches upward from the working directory', () {
      final project =
          TestProject.create()
            ..writeManifest(_manifest)
            ..write('lib/src/.keep', '');

      final result = project.run(const <String>[], workingDirectory: 'lib/src');

      expect(result.exitCode, 0, reason: '$result');
      expect(project.exists('out/livery.properties'), isTrue);
    });

    test('--config is resolved against the working directory', () {
      final project =
          TestProject.create()
            ..write('tools/livery.yaml', 'root: ..\n$_manifest')
            ..write('app/.keep', '');

      final result = project.run(const <String>['--config', '../tools/livery.yaml'], workingDirectory: 'app');

      expect(result.exitCode, 0, reason: '$result');
      expect(project.exists('out/livery.properties'), isTrue);
    });

    test('fails when no manifest is found', () {
      final project = TestProject.create();

      final result = project.run(const <String>[]);

      expect(result.exitCode, 1);
      expect(result.err, contains('no livery.yaml in ${project.root} or its parents; pass --config'));
    });

    test('fails when --config names a missing file', () {
      final result = TestProject.create().run(const <String>['--config', 'missing.yaml']);

      expect(result.exitCode, 1);
      expect(result.err, contains('missing.yaml: cannot read the manifest'));
    });
  });

  group('root', () {
    test('defaults to the manifest directory', () {
      final project = TestProject.create()..write('app/livery.yaml', _manifest);

      expect(project.run(const <String>[], workingDirectory: 'app').exitCode, 0);
      expect(project.exists('app/out/livery.properties'), isTrue);
    });

    test('resolves against the manifest directory', () {
      final project = TestProject.create()..write('tools/livery.yaml', 'root: ../app\n$_manifest');

      expect(project.run(const <String>['--config', 'tools/livery.yaml']).exitCode, 0);
      expect(project.exists('app/out/livery.properties'), isTrue);
    });

    test('--root overrides it, resolved against the working directory', () {
      final project = TestProject.create()..write('tools/livery.yaml', 'root: ../app\n$_manifest');

      final result = project.run(const <String>[
        '-c',
        '../tools/livery.yaml',
        '-r',
        '.',
      ], workingDirectory: 'elsewhere');

      expect(result.exitCode, 0, reason: '$result');
      expect(project.exists('elsewhere/out/livery.properties'), isTrue);
      expect(project.exists('app/out/livery.properties'), isFalse);
    });
  });

  group('version', () {
    test('1 is accepted', () {
      final project = TestProject.create()..writeManifest(_manifest);

      expect(project.run(const <String>[]).exitCode, 0);
    });

    test('is required', () {
      final project = TestProject.create()..writeManifest(_unversioned);

      final result = project.run(const <String>[]);

      expect(result.exitCode, 1);
      expect(result.err, contains('[version] the manifest declares no `version`; add `version: 1`'));
    });

    test('any other version is an error', () {
      final project = TestProject.create()..writeManifest('version: 2\n$_unversioned');

      final result = project.run(const <String>[]);

      expect(result.exitCode, 1);
      expect(result.err, contains('[version] unsupported manifest version 2, livery reads version 1'));
    });
  });
}

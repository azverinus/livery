import 'package:test/test.dart';

import 'support/test_project.dart';

const _manifest = '''
version: 1
defines:
  ENV: {values: [dev, production], default: dev}
  BUILD_TAG:
config:
  android: {app_name: Demo}
  ios: {app_name: Demo}
outputs:
  android:
    files: [android/livery.properties, android/app/livery.properties]
  ios:
    files: [ios/livery.properties]
''';

void main() {
  group('--only', () {
    test('generates only the named output', () {
      final project = TestProject.create()..writeManifest(_manifest);

      final result = project.run(const <String>['--only', 'ios']);

      expect(result.exitCode, 0, reason: '$result');
      expect(project.files(), <String>{'livery.yaml', 'ios/livery.properties'});
    });

    test('is repeatable', () {
      final project = TestProject.create()..writeManifest(_manifest);

      final result = project.run(const <String>['--only', 'ios', '--only', 'android']);

      expect(result.exitCode, 0, reason: '$result');
      expect(project.files(), <String>{
        'livery.yaml',
        'ios/livery.properties',
        'android/livery.properties',
        'android/app/livery.properties',
      });
    });

    test('an unknown output name exits 1 and writes nothing', () {
      final project = TestProject.create()..writeManifest(_manifest);

      final result = project.run(const <String>['--only', 'ios', '--only', 'web', '--only', 'macos']);

      expect(result.exitCode, 1);
      expect(result.err, contains('unknown output `macos`, `web`; declared outputs are android, ios'));
      expect(project.files(), <String>{'livery.yaml'});
    });

    test('still checks the outputs it does not write', () {
      final project =
          TestProject.create()..writeManifest('''
version: 1
config:
  ios: {app_name: Demo}
outputs:
  android:
    files: [android/livery.properties]
  ios:
    files: [ios/livery.properties]
''');

      final result = project.run(const <String>['--only', 'ios']);

      expect(result.exitCode, 1);
      expect(result.err, contains('merges section `android`, which the config does not define'));
      expect(project.files(), <String>{'livery.yaml'});
    });
  });

  group('--dry-run', () {
    test('prints the defines and every file, and writes nothing', () {
      final project = TestProject.create()..writeManifest(_manifest);

      final result = project.run(const <String>['--dry-run', '-D', 'ENV=production', '--only', 'android']);

      expect(result.exitCode, 0, reason: '$result');
      expect(
        result.out,
        'manifest: ${project.path('livery.yaml')}\n'
        'defines:  ENV=production\n'
        '\n'
        '--- android/livery.properties (properties)\n'
        '${_header}app_name=Demo\n'
        '\n'
        '--- android/app/livery.properties (properties)\n'
        '${_header}app_name=Demo\n',
      );
      expect(project.files(), <String>{'livery.yaml'});
    });

    test('prints the config file the run read', () {
      final project =
          TestProject.create()
            ..writeManifest('''
version: 1
defines:
  APP: {values: [demo, kiosk], default: demo}
app_pattern: config/{APP}.yaml
outputs:
  android:
    files: [android/livery.properties]
''')
            ..write('config/demo.yaml', 'config:\n  android: {app_name: Demo}\n')
            ..write('config/kiosk.yaml', 'config:\n  android: {app_name: Kiosk}\n');

      final result = project.run(const <String>['--dry-run', '-D', 'APP=kiosk']);

      expect(result.exitCode, 0, reason: '$result');
      expect(
        result.out,
        'manifest: ${project.path('livery.yaml')}\n'
        'defines:  APP=kiosk\n'
        'config:   ${project.path('config/kiosk.yaml')}\n'
        '\n'
        '--- android/livery.properties (properties)\n'
        '${_header}app_name=Kiosk\n',
      );
      expect(project.exists('android/livery.properties'), isFalse);
    });

    test('prints the config_file', () {
      final project =
          TestProject.create()
            ..writeManifest('''
version: 1
config_file: config/app.yaml
outputs:
  android:
    files: [android/livery.properties]
''')
            ..write('config/app.yaml', 'config:\n  android: {app_name: Demo}\n');

      final result = project.run(const <String>['--dry-run']);

      expect(result.exitCode, 0, reason: '$result');
      expect(result.out, contains('\nconfig:   ${project.path('config/app.yaml')}\n'));
    });

    test('says so when no define has a value', () {
      final project =
          TestProject.create()..writeManifest('''
version: 1
defines:
  BUILD_TAG:
config:
  android: {app_name: Demo}
outputs:
  android:
    files: [android/livery.properties]
''');

      final result = project.run(const <String>['--dry-run']);

      expect(result.out, contains('defines:  (none)\n'));
    });
  });

  group('--verbose', () {
    test('reports the defines and whether each file was written', () {
      final project = TestProject.create()..writeManifest(_manifest);
      expect(project.run(const <String>['--only', 'android']).exitCode, 0);
      project.write('android/app/livery.properties', 'stale\n');

      final result = project.run(const <String>['-v', '-D', 'BUILD_TAG=42']);

      expect(result.exitCode, 0, reason: '$result');
      expect(
        result.out,
        'manifest: ${project.path('livery.yaml')}\n'
        'defines:  ENV=dev BUILD_TAG=42\n'
        'unchanged android/livery.properties\n'
        'wrote     android/app/livery.properties\n'
        'wrote     ios/livery.properties\n',
      );
    });

    test('reports the config file', () {
      final project =
          TestProject.create()
            ..writeManifest('''
version: 1
config_file: config/app.yaml
outputs:
  android:
    files: [android/livery.properties]
''')
            ..write('config/app.yaml', 'config:\n  android: {app_name: Demo}\n');

      final result = project.run(const <String>['--verbose']);

      expect(result.exitCode, 0, reason: '$result');
      expect(
        result.out,
        'manifest: ${project.path('livery.yaml')}\n'
        'defines:  (none)\n'
        'config:   ${project.path('config/app.yaml')}\n'
        'wrote     android/livery.properties\n',
      );
    });

    test('with --dry-run prints the files and writes nothing', () {
      final project = TestProject.create()..writeManifest(_manifest);

      final result = project.run(const <String>['-v', '--dry-run', '--only', 'ios']);

      expect(result.exitCode, 0, reason: '$result');
      expect(result.out, contains('--- ios/livery.properties (properties)\n'));
      expect(result.out, isNot(contains('wrote')));
      expect(project.files(), <String>{'livery.yaml'});
    });

    test('is silent without the flag', () {
      final project = TestProject.create()..writeManifest(_manifest);

      expect(project.run(const <String>[]).out, isEmpty);
    });
  });

  group('usage', () {
    test('--help lists every option', () {
      final result = TestProject.create().run(const <String>['--help']);

      expect(result.out, contains('--only'));
      expect(result.out, contains('--dry-run'));
      expect(result.out, contains('--verbose'));
    });

    test('--only without a name exits 64 with usage', () {
      final result = TestProject.create().run(const <String>['--only']);

      expect(result.exitCode, 64);
      expect(result.err, contains('Missing argument for "--only"'));
      expect(result.err, contains('Usage: livery'));
    });

    test('a value for a flag exits 64 with usage', () {
      final result = TestProject.create().run(const <String>['--dry-run=yes']);

      expect(result.exitCode, 64);
      expect(result.err, contains('Usage: livery'));
    });
  });
}

const _header =
    '# GENERATED BY livery. Do not edit by hand.\n'
    '# Regenerate with `dart run livery`.\n'
    '\n';

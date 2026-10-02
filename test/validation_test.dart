import 'package:test/test.dart';

import 'support/test_project.dart';

/// Runs [manifest], expects it to fail with exit code 1 and returns stderr.
String _fail(String manifest) {
  final project = TestProject.create()..writeManifest(manifest);

  final result = project.run(const <String>[]);

  expect(result.exitCode, 1, reason: '$result');
  expect(result.err, isNot(contains('#0')), reason: 'no stack trace');

  return result.err;
}

void main() {
  group('closed key sets', () {
    test('an unknown top-level key fails, naming it, the accepted keys and the file', () {
      final project =
          TestProject.create()..writeManifest('''
version: 1
config: {}
outputs:
  android: {files: [a.properties]}
overides: []
''');

      final result = project.run(const <String>[]);

      expect(result.exitCode, 1);
      expect(
        result.err,
        'livery: ${project.path('livery.yaml')}: [overides] unknown key `overides`, '
        'accepted keys are config, outputs, root, version\n',
      );
    });

    test('an unknown output key fails, naming the output path and the keys its format accepts', () {
      final err = _fail('''
version: 1
config:
  android: {a: b}
outputs:
  android:
    formt: xcconfig
    files: [a.properties]
''');

      expect(
        err,
        contains(
          '[outputs.android.formt] unknown key `formt`, accepted keys are files, flatten, format, merge, separator',
        ),
      );
    });

    test('an unknown format fails, listing the known ones', () {
      final err = _fail('''
version: 1
config:
  android: {a: b}
outputs:
  android:
    format: yaml
    files: [a.yaml]
''');

      expect(err, contains('[outputs.android.format] unknown format `yaml`, known formats are properties'));
    });
  });

  group('shape', () {
    test('invalid YAML fails', () {
      expect(_fail('version: 1\nconfig: [\n'), contains('invalid YAML'));
    });

    test('a manifest without outputs fails', () {
      expect(_fail('version: 1\nconfig: {}\n'), contains('[outputs] the manifest declares no `outputs`'));
    });

    test('an output without files fails', () {
      expect(
        _fail('version: 1\noutputs:\n  android: {}\n'),
        contains('[outputs.android.files] output `android` declares no `files`'),
      );
    });

    test('a config section that is not a mapping fails', () {
      expect(
        _fail('version: 1\nconfig:\n  android: Demo\noutputs:\n  android: {files: [a.properties]}\n'),
        contains('[config.android] a config section must be a mapping'),
      );
    });

    test('a value of the wrong type fails with its path', () {
      expect(
        _fail(
          'version: 1\nconfig:\n  android: {a: b}\noutputs:\n  android: {files: [a.properties], flatten: yes please}\n',
        ),
        contains('[outputs.android.flatten] expected true or false, got `yes please`'),
      );
    });
  });

  test('merging a section the config does not define fails', () {
    expect(
      _fail('''
version: 1
config:
  common: {a: b}
outputs:
  android:
    merge: [common, android]
    files: [a.properties]
'''),
      contains('[outputs.android] output `android` merges section `android`, which the config does not define'),
    );
  });

  test('two outputs writing the same path fail', () {
    expect(
      _fail('''
version: 1
config:
  android: {a: b}
  ios: {c: d}
outputs:
  android:
    files: [out/a.properties]
  ios:
    files: [out/../out/a.properties]
'''),
      contains('`outputs.android.files[0]` and `outputs.ios.files[0]` both write to `out/a.properties`'),
    );
  });

  group('output paths', () {
    String failWithPath(String path) => _fail('''
version: 1
config:
  android: {a: b}
outputs:
  android:
    files: ["$path"]
''');

    test('an absolute path fails', () {
      expect(failWithPath('/tmp/a.properties'), contains('[outputs.android.files[0]] `/tmp/a.properties` is absolute'));
    });

    test('a path that escapes the root after normalisation fails', () {
      expect(failWithPath('out/../../a.properties'), contains('`out/../../a.properties` points outside the root'));
    });

    test('the root itself is not a file path', () {
      expect(failWithPath('out/..'), contains('points outside the root'));
    });
  });

  test('a failing run writes nothing', () {
    final project =
        TestProject.create()..writeManifest('''
version: 1
config:
  android: {a: b}
outputs:
  android:
    files: [first.properties]
  ios:
    files: [second.properties]
''');

    final result = project.run(const <String>[]);

    expect(result.exitCode, 1);
    expect(result.err, contains('merges section `ios`'));
    expect(project.files(), <String>{'livery.yaml'});
  });
}

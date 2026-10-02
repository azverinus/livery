import 'dart:io';

import 'package:test/test.dart';

import 'support/test_project.dart';

const _manifest = '''
config:
  android: {a: b}
outputs:
  android:
    files: [out/a.properties]
''';

void main() {
  test('a file whose content is unchanged is not rewritten', () {
    final project = TestProject.create()..writeManifest(_manifest);
    expect(project.run(const <String>[]).exitCode, 0);
    final file = File(project.path('out/a.properties'));
    final past = DateTime(2000);
    file.setLastModifiedSync(past);

    expect(project.run(const <String>[]).exitCode, 0);

    expect(file.lastModifiedSync(), past);
  });

  test('a file whose content changed is rewritten', () {
    final project =
        TestProject.create()
          ..writeManifest(_manifest)
          ..write('out/a.properties', 'stale\n');

    expect(project.run(const <String>[]).exitCode, 0);

    expect(project.read('out/a.properties'), endsWith('\na=b\n'));
  });

  test('an unwritable output exits 1 with a message, not a stack trace', () {
    final project = TestProject.create()..writeManifest(_manifest);
    Directory(project.path('out/a.properties')).createSync(recursive: true);

    final result = project.run(const <String>[]);

    expect(result.exitCode, 1);
    expect(result.err, startsWith('livery: cannot write ${project.path('out/a.properties')}: '));
    expect(result.err, isNot(contains('#0')));
  });

  test('an unreadable manifest exits 1 with a message, not a stack trace', () {
    final project = TestProject.create();
    Directory(project.path('livery.yaml')).createSync();

    final result = project.run(const <String>['--config', 'livery.yaml']);

    expect(result.exitCode, 1);
    expect(result.err, startsWith('livery: ${project.path('livery.yaml')}: cannot read the manifest: '));
    expect(result.err, isNot(contains('#0')));
  });
}

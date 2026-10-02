import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/markdown.dart';
import 'support/test_project.dart';

/// The user docs a reader can land on, from pub.dev or from GitHub.
final _docs = <String>[
  'README.md',
  'example/README.md',
  ...Directory('doc').listSync().whereType<File>().map((file) => file.path).where((path) => path.endsWith('.md')),
];

void main() {
  test('the README links the manifest reference, the guides and the example', () {
    final links = _relativeLinks('README.md').map((link) => link.split('#').first).toSet();

    expect(links, containsAll(<String>['doc/schema.md', 'doc/ios.md', 'doc/android.md', 'doc/dart.md', 'example/']));
  });

  for (final doc in _docs) {
    test('every relative link in $doc points to a file and heading that exist', () {
      for (final link in _relativeLinks(doc)) {
        final [target, ...fragment] = link.split('#');
        final path = target.isEmpty ? doc : p.normalize(p.join(p.dirname(doc), target));
        expect(FileSystemEntity.typeSync(path), isNot(FileSystemEntityType.notFound), reason: '$doc links $link');

        if (fragment.isNotEmpty) {
          expect(_anchors(path), contains(fragment.single), reason: '$doc links $link');
        }
      }
    });
  }

  test("the example's README, pub.dev's Example tab, shows the example's manifest as it is", () {
    final manifest = File('example/livery.yaml').readAsStringSync();

    expect(codeBlocks(File('example/README.md').readAsStringSync()), contains('# livery.yaml\n$manifest'));
  });

  test('every complete manifest in the README generates', () {
    final manifests =
        codeBlocks(
          File('README.md').readAsStringSync(),
        ).where((block) => block.startsWith('# livery.yaml\n') && block.contains('\nversion: 1\n')).toList();
    expect(manifests, isNotEmpty);

    for (final manifest in manifests) {
      final project = TestProject.create()..writeManifest(manifest);
      final result = project.run(const <String>['--dry-run']);
      expect(result.exitCode, 0, reason: '$manifest\n$result');
    }
  });
}

/// Targets of the Markdown links in [doc] that are neither absolute URLs nor
/// inside code.
List<String> _relativeLinks(String doc) => [
  for (final match in RegExp(r'\]\(([^)\s]+)\)').allMatches(prose(File(doc).readAsStringSync())))
    if (!match.group(1)!.contains('://')) match.group(1)!,
];

/// The anchors GitHub and pub.dev give the headings of [doc], for ASCII
/// headings that are not repeated, which is all the docs have.
Set<String> _anchors(String doc) => {
  for (final match in RegExp(r'^#+ (.+)$', multiLine: true).allMatches(prose(File(doc).readAsStringSync())))
    match.group(1)!.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 _-]'), '').replaceAll(' ', '-'),
};

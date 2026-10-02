import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support/test_project.dart';

const _skillDir = 'skills/livery-setup';

/// Recipes the skill shares with a guide, which must read the same in both.
const _sharedRecipes = <({String guide, String recipe})>[
  (
    guide: 'doc/ios.md',
    recipe: '''
#include "Generated.xcconfig"
#include "livery.xcconfig"''',
  ),
  (guide: 'doc/ios.md', recipe: r'PRODUCT_BUNDLE_IDENTIFIER = "$(APP_BUNDLE_ID)";'),
  (
    guide: 'doc/ios.md',
    recipe: r'''
<key>CFBundleDisplayName</key>
<string>$(APP_NAME)</string>''',
  ),
  (guide: 'doc/ios.md', recipe: 'ios/Flutter/livery.xcconfig\n'),
  (
    guide: 'doc/android.md',
    recipe: '''
plugins {
    `kotlin-dsl`
}

repositories {
    mavenCentral()
}''',
  ),
  (guide: 'doc/android.md', recipe: '    includeBuild("livery")'),
  (guide: 'doc/android.md', recipe: 'applicationId = LiveryConfig.APP_ID\n'),
  (guide: 'doc/android.md', recipe: '    id("livery")'),
  (guide: 'doc/android.md', recipe: 'applicationIdSuffix = LiveryConfig.APP_ID_SUFFIX.ifEmpty { null }'),
  (guide: 'doc/android.md', recipe: 'manifestPlaceholders["appLabel"] = LiveryConfig.APP_NAME'),
  (guide: 'doc/android.md', recipe: r'android:label="${appLabel}"'),
  (
    guide: 'doc/android.md',
    recipe: '''
android/livery/src/main/kotlin/LiveryConfig.kt
android/livery/.gradle/
android/livery/.kotlin/
android/livery/build/''',
  ),
];

void main() {
  final skill = File(p.join(_skillDir, 'SKILL.md')).readAsStringSync();
  final skillCode = _codeBlocks(skill).join('\n');

  test('SKILL.md has Agent Skills frontmatter named after its pub skills directory', () {
    final match = RegExp(r'^---\n([\s\S]*?)\n---\n').firstMatch(skill);
    expect(match, isNotNull, reason: 'SKILL.md must start with YAML frontmatter');

    final frontmatter = loadYaml(match!.group(1)!) as YamlMap;
    expect(frontmatter['name'], p.basename(_skillDir));
    expect(frontmatter['name'], startsWith('livery-'));
    expect(frontmatter['name'], matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$')));

    final description = frontmatter['description'] as String;
    expect(description.length, inInclusiveRange(1, 1024));
    expect(description, contains('livery.yaml'));
  });

  for (final (:guide, :recipe) in _sharedRecipes) {
    test('the skill and $guide share the recipe `${recipe.trim().split('\n').first}`', () {
      expect(File(guide).readAsStringSync(), contains(recipe));
      expect(skillCode, contains(recipe));
    });
  }

  test('every complete manifest in the skill generates', () {
    final manifests =
        _codeBlocks(
          skill,
        ).where((block) => block.startsWith('# livery.yaml\n') && block.contains('\nversion: 1\n')).toList();
    expect(manifests, isNotEmpty);

    for (final manifest in manifests) {
      final project = TestProject.create()..writeManifest(manifest);
      final result = project.run(const <String>['--dry-run']);
      expect(result.exitCode, 0, reason: '$manifest\n$result');
    }
  });
}

/// The contents of the fenced code blocks in [markdown], each with the
/// indentation of its fence removed, as in a list item.
List<String> _codeBlocks(String markdown) =>
    RegExp(r'^( *)```\w*\n([\s\S]*?)^\1```', multiLine: true).allMatches(markdown).map((match) {
      final indent = match.group(1)!;

      return match
          .group(2)!
          .split('\n')
          .map((line) => line.startsWith(indent) ? line.substring(indent.length) : line)
          .join('\n');
    }).toList();

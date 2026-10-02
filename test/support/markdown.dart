/// Fenced code blocks, with the indentation of their fence, as in a list item.
final _fence = RegExp(r'^( *)```\w*\n([\s\S]*?)^\1```', multiLine: true);

/// The contents of the fenced code blocks in [markdown], each with the
/// indentation of its fence removed.
List<String> codeBlocks(String markdown) =>
    _fence.allMatches(markdown).map((match) {
      final indent = match.group(1)!;

      return match
          .group(2)!
          .split('\n')
          .map((line) => line.startsWith(indent) ? line.substring(indent.length) : line)
          .join('\n');
    }).toList();

/// [markdown] without its fenced code blocks.
String prose(String markdown) => markdown.replaceAll(_fence, '');

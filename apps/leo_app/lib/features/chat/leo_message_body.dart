import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

class LeoMessageBody extends StatelessWidget {
  const LeoMessageBody({super.key, required this.text});

  final String text;

  static final _mathExpression = RegExp(
    r'\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]|\\\(([^\n]+?)\\\)|\$([^$\n]+?)\$',
  );

  @override
  Widget build(BuildContext context) {
    final matches = _mathExpression.allMatches(text).toList(growable: false);
    if (matches.isEmpty) return _markdown(context, text);

    final children = <Widget>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        final plain = text.substring(cursor, match.start);
        if (plain.trim().isNotEmpty) children.add(_markdown(context, plain));
      }
      final tex = (match.group(1) ??
              match.group(2) ??
              match.group(3) ??
              match.group(4) ??
              '')
          .trim();
      if (tex.isNotEmpty) {
        final isDisplay = match.group(1) != null || match.group(2) != null;
        children.add(
          Padding(
            padding: EdgeInsets.symmetric(vertical: isDisplay ? 10 : 3),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Math.tex(
                  tex,
                  textStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 16,
                  ),
                  onErrorFallback: (_) => SelectableText(
                    isDisplay ? '\$\$$tex\$\$' : '\$$tex\$',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      final tail = text.substring(cursor);
      if (tail.trim().isNotEmpty) children.add(_markdown(context, tail));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _markdown(BuildContext context, String value) {
    final theme = Theme.of(context);
    return MarkdownBody(
      data: value,
      selectable: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      builders: {'code': _LeoCodeBlockBuilder()},
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: theme.textTheme.bodyMedium?.copyWith(height: 1.65),
        code: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          backgroundColor: Color(0x223A4768),
        ),
        blockSpacing: 10,
      ),
    );
  }
}

class _LeoCodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final code = element.textContent;
    final language = (element.attributes['class'] ?? '')
        .replaceFirst('language-', '');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101827),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF26344D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (language.isNotEmpty) ...[
            Text(
              language.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF9DB4E8),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
          ],
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              code,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: Color(0xFFE5ECF8),
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

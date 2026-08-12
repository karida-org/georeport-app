import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Renders Redmine-authored text: Markdown when the instance formats in
/// CommonMark, plain selectable text otherwise (rendering Textile as
/// Markdown would be wrong, so it is shown as-is).
class RichTextBody extends StatelessWidget {
  const RichTextBody({required this.text, required this.markdown, super.key});

  final String text;
  final bool markdown;

  @override
  Widget build(BuildContext context) {
    if (!markdown) {
      return SelectableText(text);
    }
    return MarkdownBody(data: text, selectable: true);
  }
}

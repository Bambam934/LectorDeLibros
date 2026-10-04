import '../../domain/entities/chapter_block.dart';

/// Un bloque de Markdown con el nivel de su título (0 si no es un título).
///
/// El nivel solo sirve para cortar capítulos por `#` y `##`; el bloque en sí
/// no lo guarda.
typedef MarkdownBlock = ({ChapterBlock block, int level});

final RegExp _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})');
final RegExp _atxHeading = RegExp(r'^ {0,3}(#{1,6})[ \t]+(.+?)[ \t]*#*[ \t]*$');
final RegExp _listOrQuote = RegExp(r'^\s*([-*+>]|\d+[.)])\s');

/// Divide un texto Markdown en párrafos, títulos y bloques de código (ADR 13).
///
/// - Las vallas ``` y ~~~ pasan a un bloque de código literal; la etiqueta de
///   lenguaje se descarta. Sin esto, los `#` de los comentarios de Python
///   dentro de una valla se tomaban por títulos de capítulo.
/// - Los títulos `#`…`######` pasan a títulos sin las almohadillas.
/// - Las líneas de un párrafo se unen con un espacio, como las pinta
///   Markdown; un elemento de lista o una cita empieza párrafo propio.
List<MarkdownBlock> parseMarkdownBlocks(String content) {
  final lines =
      content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final blocks = <MarkdownBlock>[];
  final paragraph = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    final text = paragraph.join(' ').trim();
    if (text.isNotEmpty) {
      blocks.add((block: ChapterBlock.paragraph(text), level: 0));
    }
    paragraph.clear();
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];

    final fence = _fence.firstMatch(line);
    if (fence != null) {
      flushParagraph();
      final marker = fence.group(1)!;
      final closing = RegExp(
        '^ {0,3}${RegExp.escape(marker[0])}{${marker.length},}[ \\t]*\$',
      );
      final code = <String>[];
      var j = i + 1;
      while (j < lines.length && !closing.hasMatch(lines[j])) {
        code.add(lines[j].replaceAll('\t', '    ').trimRight());
        j++;
      }
      i = j;
      while (code.isNotEmpty && code.first.trim().isEmpty) {
        code.removeAt(0);
      }
      while (code.isNotEmpty && code.last.trim().isEmpty) {
        code.removeLast();
      }
      if (code.isNotEmpty) {
        blocks.add((block: ChapterBlock.code(code.join('\n')), level: 0));
      }
      continue;
    }

    final heading = _atxHeading.firstMatch(line);
    if (heading != null) {
      flushParagraph();
      blocks.add((
        block: ChapterBlock.heading(heading.group(2)!.trim()),
        level: heading.group(1)!.length,
      ));
      continue;
    }

    if (line.trim().isEmpty) {
      flushParagraph();
      continue;
    }
    if (_listOrQuote.hasMatch(line)) flushParagraph();
    paragraph.add(line.trim());
  }
  flushParagraph();
  return blocks;
}

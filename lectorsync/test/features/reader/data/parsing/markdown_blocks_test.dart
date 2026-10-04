import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/parsing/markdown_blocks.dart';
import 'package:lectorsync/features/reader/domain/entities/chapter_block.dart';

void main() {
  test('las vallas pasan a código literal, sin la etiqueta de lenguaje', () {
    const md = 'Un párrafo antes.\n'
        '\n'
        '```python\n'
        'def saluda():\n'
        '    # no es un título\n'
        '\tprint("hola")\n'
        '```\n'
        '~~~\n'
        'x = 1\n'
        '~~~\n';

    final blocks = [for (final b in parseMarkdownBlocks(md)) b.block];

    expect(blocks, const [
      ChapterBlock.paragraph('Un párrafo antes.'),
      ChapterBlock.code(
          'def saluda():\n    # no es un título\n    print("hola")'),
      ChapterBlock.code('x = 1'),
    ]);
  });

  test('los títulos pierden las almohadillas y guardan su nivel', () {
    final parsed = parseMarkdownBlocks('# Uno\n\n### Ejercicio 1 ###\ntexto');

    expect(parsed.map((b) => (b.block.text, b.level)), [
      ('Uno', 1),
      ('Ejercicio 1', 3),
      ('texto', 0),
    ]);
    expect(parsed[1].block.kind, ChapterBlockKind.heading);
  });

  test('las líneas de un párrafo se unen y cada elemento de lista va aparte',
      () {
    final blocks = [
      for (final b in parseMarkdownBlocks('Una línea\npartida en dos.\n'
          '- uno\n- dos\n'))
        b.block.text,
    ];

    expect(blocks, ['Una línea partida en dos.', '- uno', '- dos']);
  });

  test('una valla sin cerrar toma el resto del texto', () {
    final blocks = [for (final b in parseMarkdownBlocks('```\nx = 1\ny = 2'))
      b.block];

    expect(blocks, const [ChapterBlock.code('x = 1\ny = 2')]);
  });
}

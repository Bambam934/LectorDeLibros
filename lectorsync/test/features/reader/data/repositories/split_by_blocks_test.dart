import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/repositories/tts/speak_segment.dart';
import 'package:lectorsync/features/reader/data/repositories/tts/tts_segmentation.dart';
import 'package:lectorsync/features/reader/domain/entities/chapter.dart';
import 'package:lectorsync/features/reader/domain/entities/chapter_block.dart';

final _blocks = [
  const ChapterBlock.heading('4.6.1 Trabajo'),
  const ChapterBlock.paragraph('El trabajo es fuerza por distancia.'),
  const ChapterBlock.paragraph('Se calcula así:'),
  ChapterBlock.figure(
    page: 135,
    rect: const PageRect(150, 216, 300, 245),
    figureKind: FigureKind.formula,
  ),
  const ChapterBlock.code('def trabajo(f, d):\n    return f * d'),
  const ChapterBlock.paragraph('Y eso es todo.'),
];

List<String> _words() =>
    Chapter.textOfBlocks(_blocks).split(RegExp(r'\s+')).toList();

/// Registra los tramos de prosa que recibe, para comprobar que van de una
/// pieza y con las palabras que tocan.
final _proseCalls = <(String, int, int)>[];
List<SpeakSegment> _prose(String text, List<String> words, int start) {
  _proseCalls.add((text, start, words.length));
  return splitIntoSegments(text, words, start);
}

void main() {
  setUp(_proseCalls.clear);

  test('cada bloque especial va aparte y la prosa seguida va de una pieza', () {
    final segments = splitByBlocks(_blocks, _words(), 0,
        segmentProse: _prose)!;

    expect(segments.map((s) => s.text), [
      '4.6.1 Trabajo.',
      'El trabajo es fuerza por distancia.\n\nSe calcula así:',
      'Fórmula.',
      'Bloque de código.',
      'Y eso es todo.',
    ]);
    expect(_proseCalls.first.$1,
        'El trabajo es fuerza por distancia.\n\nSe calcula así:');
  });

  test('conserva los índices de palabra de cada bloque', () {
    final words = _words();
    final segments = splitByBlocks(_blocks, words, 0, segmentProse: _prose)!;

    // título 2 + prosa 6+3 + fórmula 1 + código 7 + prosa 4 = 23 palabras.
    expect(segments.map((s) => s.globalStartWordIndex), [0, 2, 11, 12, 19]);
    expect(segments.fold(0, (n, s) => n + s.words.length), words.length);
    expect(segments[2].words, [kFormulaMarker]);
    expect(segments[3].words,
        ['def', 'trabajo(f,', 'd):', 'return', 'f', '*', 'd']);
  });

  test('los avisos llevan la marca de texto sintético', () {
    final segments = splitByBlocks(_blocks, _words(), 0, segmentProse: _prose)!;

    expect(segments.map((s) => s.isFormula),
        [false, false, true, true, false]);
  });

  test('con el ajuste activado el código se lee como prosa', () {
    final segments = splitByBlocks(_blocks, _words(), 0,
        segmentProse: _prose, readCode: true)!;

    expect(segments[3].text, 'def trabajo(f, d):\n    return f * d');
    expect(segments[3].isFormula, isFalse);
    expect(segments[3].globalStartWordIndex, 12);
  });

  test('empieza a mitad de un bloque desde la palabra pedida', () {
    // Palabra 5 = "fuerza", dentro del primer párrafo.
    final segments = splitByBlocks(_blocks, _words(), 5,
        segmentProse: _prose)!;

    expect(segments.first.text, 'fuerza por distancia.\n\nSe calcula así:');
    expect(segments.first.globalStartWordIndex, 5);
  });

  test('si los bloques no cuadran con las palabras devuelve null', () {
    expect(
      splitByBlocks(_blocks, ['sobra', ..._words()], 0, segmentProse: _prose),
      isNull,
    );
  });

  test('un título con su propio punto no gana otro', () {
    final segments = splitByBlocks(
      const [ChapterBlock.heading('Fin.')],
      const ['Fin.'],
      0,
      segmentProse: _prose,
    )!;

    expect(segments.single.text, 'Fin.');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/data/parsing/pdf_layout.dart';
import 'package:lectorsync/features/reader/domain/entities/chapter_block.dart';

/// Las medidas imitan "Cálculo integral": cuerpo en Minion de 11 pt con
/// interlineado de 13,5, columna de 71 a 382,7 y sangría de primera línea en
/// 99. Las de código imitan "Ciencia de datos desde cero".
const _pages = [
  LayoutPageSize(439.4, 609.4),
  LayoutPageSize(439.4, 609.4),
  LayoutPageSize(439.4, 609.4),
  LayoutPageSize(439.4, 609.4),
];

PdfTextFragment _frag(
  int page,
  double top,
  String text, {
  double left = 71,
  double? right,
  String font = 'Minion',
  double size = 11,
  bool bold = false,
  bool mono = false,
}) =>
    PdfTextFragment(
      page: page,
      left: left,
      top: top,
      right: right ?? left + text.length * size * 0.5,
      bottom: top + size,
      text: text,
      font: font,
      bold: bold,
      monoChars: mono ? text.replaceAll(RegExp(r'\s'), '').length : 0,
    );

/// Una línea de cuerpo justificada, de margen a margen.
PdfTextFragment _body(int page, double top, String text, {double left = 71}) =>
    _frag(page, top, text, left: left, right: 382.7);

/// Relleno de cuerpo para que el perfil del libro tenga de dónde medir.
List<PdfTextFragment> _filler(int page, {double from = 99.3, int lines = 12}) => [
      for (var i = 0; i < lines; i++)
        _body(page, from + i * 13.5,
            'Texto del cuerpo de la página número $page con palabras $i'),
    ];

List<ChapterBlock> _blocks(List<PdfTextFragment> fragments) {
  final layout = analyzePdfLayout(fragments, _pages);
  expect(layout, isNotNull, reason: 'el libro debería tener maquetación');
  return layout!.blocks;
}

List<String> _texts(List<ChapterBlock> blocks, ChapterBlockKind kind) => [
      for (final b in blocks)
        if (b.kind == kind) b.text,
    ];

void main() {
  group('analyzePdfLayout — párrafos', () {
    test('une las líneas, abre párrafo con la sangría y deshace el guion', () {
      final blocks = _blocks([
        _body(0, 100, 'Una de las aplicaciones más importantes del pro-',
            left: 99),
        _body(0, 113.5, 'blema es la existencia del cálculo como ciencia y'),
        _frag(0, 127, 'su relación con la física.', right: 250),
        _body(0, 140.5, 'Otro párrafo empieza aquí con su sangría de la',
            left: 99),
        _frag(0, 154, 'primera línea y acaba en Cuenca-', right: 300),
        _frag(0, 167.5, 'Ecuador.', right: 120),
      ]);

      expect(_texts(blocks, ChapterBlockKind.paragraph), [
        'Una de las aplicaciones más importantes del problema es la '
            'existencia del cálculo como ciencia y su relación con la física.',
        'Otro párrafo empieza aquí con su sangría de la primera línea y '
            'acaba en Cuenca-Ecuador.',
      ]);
    });

    test('un pie de figura en otro tamaño no se pega a la frase anterior', () {
      final blocks = _blocks([
        ..._filler(0, lines: 10),
        _body(0, 99.3 + 10 * 13.5, 'la integral anterior se convierte en'),
        _frag(1, 99.3, 'Figura 39', size: 9, right: 120),
        ..._filler(1, from: 120, lines: 10),
      ]);

      expect(blocks.where((b) => b.text == 'Figura 39'), hasLength(1));
    });
  });

  group('analyzePdfLayout — cabeceras y pies', () {
    test('quita la cabecera repetida y los números de página', () {
      final fragments = <PdfTextFragment>[];
      for (var page = 0; page < 3; page++) {
        fragments
          ..add(_frag(page, 65.6, 'APLICACIONES DE LA INTEGRAL DEFINIDA',
              left: 175, font: 'Albertus', size: 7))
          ..add(_frag(page, 77.1, '${135 + page}',
              left: 221, font: 'Albertus', size: 9))
          ..addAll(_filler(page));
      }

      final text = _blocks(fragments).map((b) => b.text).join(' ');

      expect(text, isNot(contains('APLICACIONES')));
      expect(text, isNot(contains('135')));
      expect(text, contains('Texto del cuerpo'));
    });

    test('un rótulo al principio de varias páginas no es una cabecera', () {
      final fragments = <PdfTextFragment>[
        for (var page = 0; page < 3; page++) ...[
          _frag(page, 99.3, 'Ejercicio ${page + 1}', font: 'Albertus'),
          ..._filler(page, from: 120),
        ],
        // La mayoría de las páginas empiezan con texto en lo alto: ahí está
        // el principio del cuerpo, y el rótulo cae dentro, no encima.
        for (var page = 3; page < 7; page++) ..._filler(page),
      ];

      expect(_texts(_blocks(fragments), ChapterBlockKind.heading),
          ['Ejercicio 1', 'Ejercicio 2', 'Ejercicio 3']);
    });

    test('descarta el índice con puntos de relleno sin tomar su hueco por '
        'una figura', () {
      final blocks = _blocks([
        ..._filler(0),
        _body(1, 99.3, 'Índice de un libro con contenido para el perfil'),
        for (var i = 1; i <= 4; i++)
          _body(1, 99.3 + i * 13.5, '4.$i Aplicaciones ............... 13$i'),
        _body(1, 99.3 + 5 * 13.5, 'Texto que sigue al índice en esta página'),
      ]);

      expect(blocks.map((b) => b.text).join(' '), isNot(contains('....')));
      expect(blocks.where((b) => b.kind == ChapterBlockKind.figure), isEmpty);
    });
  });

  group('analyzePdfLayout — código', () {
    test('reconstruye la sangría por niveles y deja el código en línea en la '
        'prosa', () {
      PdfTextFragment code(int page, double top, String text, double left) =>
          _frag(page, top, text,
              left: left,
              right: left + text.length * 5.85,
              font: 'LiberationMono',
              size: 9.8,
              mono: true);
      PdfTextFragment serif(double top, String text,
              {double left = 72, double right = 539.9}) =>
          _frag(0, top, text,
              left: left, right: right, font: 'LiberationSerif', size: 15);

      final blocks = analyzePdfLayout([
        for (var i = 0; i < 8; i++)
          serif(75 + i * 18.75, 'Una línea de prosa del libro de Python $i'),
        // "Thor (id 4)": el código en línea llega como trozo aparte, un poco
        // más abajo y más bajo.
        serif(225, 'Thor (', right: 110.6),
        _frag(0, 227.2, 'id',
            left: 110.6,
            right: 125,
            font: 'LiberationMono',
            size: 12,
            mono: true),
        serif(225, ' 4) solo tiene dos conexiones con la gente.', left: 125),
        code(0, 270, 'def foaf_ids_bad(user):', 73.5),
        code(0, 283.5, '"""foaf is short"""', 88.5),
        code(0, 297, 'return [foaf_id', 88.5),
        code(0, 310.5, 'for friend_id in friendships[user["id"]]', 103.5),
        serif(345, 'Cuando aplicamos esto sobre los usuarios del grafo.'),
      ], const [LayoutPageSize(612, 792)])!
          .blocks;

      expect(_texts(blocks, ChapterBlockKind.code), [
        'def foaf_ids_bad(user):\n'
            '   """foaf is short"""\n'
            '   return [foaf_id\n'
            '      for friend_id in friendships[user["id"]]',
      ]);
      expect(_texts(blocks, ChapterBlockKind.paragraph),
          contains(contains('Thor (id 4) solo tiene dos conexiones')));
    });
  });

  group('analyzePdfLayout — títulos', () {
    test('otra familia al mismo tamaño, corta y aislada, es un título', () {
      final blocks = _blocks([
        ..._filler(0, lines: 4),
        _frag(0, 169.8, '4.6.1 Trabajo', font: 'Albertus', right: 122.4),
        _body(0, 191.8, 'En Física se estudió que el trabajo que una fuerza',
            left: 99),
        ..._filler(0, from: 205.3, lines: 6),
      ]);

      expect(_texts(blocks, ChapterBlockKind.heading), ['4.6.1 Trabajo']);
    });

    test('la última línea de un párrafo en otra fuente no es un título', () {
      final blocks = _blocks([
        ..._filler(0, lines: 8),
        _frag(0, 250, 'Una nota en otra fuente que ocupa toda la línea de',
            font: 'LiberationSans', right: 382.7),
        _frag(0, 263.5, 'la columna y acaba corta.',
            font: 'LiberationSans', right: 200),
        ..._filler(0, from: 290, lines: 4),
      ]);

      expect(_texts(blocks, ChapterBlockKind.heading), isEmpty);
    });

    test('más grande que el cuerpo es un título', () {
      final blocks = _blocks([
        ..._filler(0, lines: 6),
        _frag(0, 200, 'Científicos de datos que podría conocer',
            font: 'SerifaStd', size: 19.5, bold: true, right: 380),
        ..._filler(0, from: 240, lines: 6),
      ]);

      expect(_texts(blocks, ChapterBlockKind.heading),
          ['Científicos de datos que podría conocer']);
    });
  });

  group('analyzePdfLayout — líneas partidas en trozos', () {
    test('separa la variable en otra fuente, pero no el exponente', () {
      final blocks = _blocks([
        ..._filler(0, lines: 6),
        _frag(0, 190, 'En donde el subíndice', right: 199.7),
        _frag(0, 190, 'x',
            left: 199.7, right: 204.6, font: 'TimesNewRomanPS'),
        _frag(0, 190, ' significa que la curva es y = x',
            left: 204.6, right: 300),
        _frag(0, 187.5, '2', left: 300, right: 304, size: 7),
        _frag(0, 190, ' en el intervalo pedido.', left: 304, right: 382.7),
      ]);

      expect(
        blocks.map((b) => b.text).join(' '),
        contains('En donde el subíndice x significa que la curva es y = x2 '
            'en el intervalo pedido.'),
      );
    });
  });

  group('figuras', () {
    // Cinco líneas de relleno (la última en 153,3) y la frase que presenta la
    // ecuación pegada a ellas, en 166,8 y 180,3.
    List<PdfTextFragment> pageWithGap() => [
          ..._filler(0, lines: 5),
          _body(0, 166.8, 'En Física se estudió que el trabajo es:', left: 99),
          _body(0, 180.3, 'cuerpo está dado por la expresión siguiente:'),
          // Hueco de 28,4 pt: la ecuación vectorial que el texto no tiene.
          _body(0, 219.7, 'En los problemas que hasta ahora se resolvieron',
              left: 99),
          ..._filler(0, from: 233.2, lines: 5),
        ];

    test('un hueco grande entre dos líneas es un candidato', () {
      final layout = analyzePdfLayout(pageWithGap(), _pages)!;

      expect(layout.figureCandidates, hasLength(1));
      final (page, rect) = layout.figureCandidates.single;
      expect(page, 0);
      expect(rect.top, closeTo(191.3, 0.01));
      expect(rect.bottom, closeTo(219.7, 0.01));
    });

    test('con tinta pasa a fórmula recortada a la tinta; sin ella se quita', () {
      final layout = analyzePdfLayout(pageWithGap(), _pages)!;

      final inked = resolveFigureCandidates(
          layout, const [PageRect(150, 197, 300, 215)]);
      final figure = inked.singleWhere((b) => b.kind == ChapterBlockKind.figure);
      expect(figure.figureKind, FigureKind.formula);
      expect(figure.text, kFormulaMarker);
      expect(figure.rect, const PageRect(147, 194, 303, 218));
      expect(figure.textHeight, 11);

      final blank = resolveFigureCandidates(layout, const [null]);
      expect(blank.where((b) => b.kind == ChapterBlockKind.figure), isEmpty);
      expect(blank.length, inked.length - 1);
    });

    test('un filete decorativo no es una fórmula', () {
      final layout = analyzePdfLayout(pageWithGap(), _pages)!;

      final blocks = resolveFigureCandidates(
          layout, const [PageRect(71, 205, 382, 206)]);

      expect(blocks.where((b) => b.kind == ChapterBlockKind.figure), isEmpty);
    });

    test('una figura alta es una figura, no una fórmula', () {
      final layout = analyzePdfLayout([
        ..._filler(0, lines: 3),
        _body(0, 146, 'de la red (véase la figura 1.2).'),
        _body(0, 340, 'Esto tiene la virtud de ser bastante fácil de calcular'),
        ..._filler(0, from: 353.5, lines: 6),
      ], _pages)!;

      final blocks = resolveFigureCandidates(
          layout, const [PageRect(80, 160, 360, 330)]);

      expect(
        blocks.singleWhere((b) => b.kind == ChapterBlockKind.figure).figureKind,
        FigureKind.figure,
      );
    });
  });

  group('plan B', () {
    test('sin una fuente de cuerpo dominante devuelve null', () {
      final fragments = [
        for (var i = 0; i < 12; i++)
          _frag(0, 100 + i * 13.5, 'Texto escaneado con fuente $i',
              font: 'Fuente$i', right: 382.7),
      ];

      expect(analyzePdfLayout(fragments, _pages), isNull);
    });

    test('a dos columnas devuelve null', () {
      // El PDF escribe una columna entera y después la otra.
      final fragments = [
        for (var i = 0; i < 12; i++)
          _frag(0, 100 + i * 13.5, 'Columna izquierda $i', right: 200),
        for (var i = 0; i < 12; i++)
          _frag(0, 100 + i * 13.5, 'Columna derecha $i',
              left: 230, right: 382.7),
      ];

      expect(analyzePdfLayout(fragments, _pages), isNull);
    });

    test('sin texto devuelve null', () {
      expect(analyzePdfLayout(const [], _pages), isNull);
    });
  });

  group('learnGlyphCodeFixes', () {
    test('aprende que el código 31 es la ligadura "fi"', () {
      final fragments = [
        _body(3, 100, 'el área de la super31cie que envuelve'),
        _body(3, 113.5, 'es la 31gura de revolución y su super31cie lateral'),
      ];
      const plain = 'el área de la superficie que envuelve\n'
          'es la figura de revolución y su superficie lateral';

      final fixes = learnGlyphCodeFixes(fragments, (_) => plain);

      expect(fixes, {'31': 'fi'});
      expect(
        applyGlyphCodeFixes('la super31cie de la 31gura', fixes),
        'la superficie de la figura',
      );
    });

    test('no confunde un ordinal con una palabra parecida', () {
      final fragments = [
        _body(0, 100, '1ra edición: Universidad Politécnica Salesiana'),
        _body(0, 113.5, 'Para 1ra edición del libro'),
      ];
      const plain = '1ra edición: Universidad Politécnica Salesiana\n'
          'Para 1ra edición del libro';

      expect(learnGlyphCodeFixes(fragments, (_) => plain), isEmpty);
    });

    test('no toca las cifras que no aprendió', () {
      expect(applyGlyphCodeFixes('sen3x y cos2x', {'31': 'fi'}),
          'sen3x y cos2x');
    });
  });

  test('joinProseLines conserva el guion de los compuestos', () {
    expect(joinProseLines(['teórico-', 'práctico']), 'teóricopráctico');
    expect(joinProseLines(['Cuenca-', 'Ecuador']), 'Cuenca-Ecuador');
    expect(joinProseLines(['una pala­', 'bra']), 'una palabra');
    expect(joinProseLines(['fin.', 'Otra']), 'fin. Otra');
  });
}

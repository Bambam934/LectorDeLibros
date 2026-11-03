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
  bool italic = false,
  bool mono = false,
  int mathChars = 0,
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
      italic: italic,
      monoChars: mono ? text.replaceAll(RegExp(r'\s'), '').length : 0,
      mathChars: mathChars,
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

    test('un pie de figura repetido bajo el texto no es un pie de página', () {
      // Sin cifras, "Figura 38" y "Figura 42" son el mismo texto; los pies
      // caen donde cae la figura, no a la misma altura en cada página.
      final fragments = <PdfTextFragment>[
        for (var page = 0; page < 3; page++) ...[
          ..._filler(page),
          _frag(page, 300 + page * 40, 'Figura ${38 + page}',
              left: 180, size: 9),
          _frag(page, 312 + page * 40, 'Gráfica del ejercicio ${page + 1}',
              left: 150, size: 9),
        ],
      ];

      final text = _blocks(fragments).map((b) => b.text).join(' ');

      expect(text, contains('Figura 38'));
      expect(text, contains('Figura 40'));
      expect(text, contains('Gráfica del ejercicio 3'));
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

  group('analyzePdfLayout — pies en la fuente del cuerpo', () {
    final pages = [
      for (var i = 0; i < 8; i++) const LayoutPageSize(439.4, 609.4),
    ];
    List<PdfTextFragment> book(String Function(int page) first) => [
          for (var p = 0; p < 8; p++) ...[
            _body(p, 99.3, first(p)),
            ..._filler(p, from: 112.8, lines: 10),
            _frag(p, 560, 'www.lectulandia.com - Página ${p + 10}',
                right: 250),
          ],
        ];

    test('el pie que se repite en todas las páginas desaparece', () {
      final blocks = analyzePdfLayout(book((p) => 'Primera línea $p'), pages)!
          .blocks;

      expect(blocks.map((b) => b.text).join(' '),
          isNot(contains('lectulandia')));
    });

    test('lo que abre unas pocas páginas sigue en el texto', () {
      final blocks = analyzePdfLayout(
              book((p) => p < 2 ? 'Ejercicio ${p + 1}' : 'Primera línea $p'),
              pages)!
          .blocks;

      expect(blocks.map((b) => b.text).join(' '), contains('Ejercicio 1'));
    });
  });

  group('analyzePdfLayout — frases con línea sangrada', () {
    test('la palabra partida con sangría sigue en el párrafo', () {
      final blocks = _blocks([
        ..._filler(0),
        _frag(0, 261.3, 'Solución: aplicamos la fórmula 2 de la Tabla 1 ha-',
            right: 300),
        _frag(0, 274.8, 'ciendo n=3', left: 99, right: 160),
      ]);

      expect(_texts(blocks, ChapterBlockKind.paragraph),
          contains(contains('Tabla 1 haciendo n=3')));
    });

    test('el cambio de fuente no corta una frase sin cerrar', () {
      final blocks = _blocks([
        ..._filler(0),
        _frag(0, 261.3, 'Solución: aplicamos la fórmula 2 de la Tabla 1 ha-',
            font: 'Albertus', right: 370),
        _frag(0, 274.8, 'ciendo n=3', right: 121),
      ]);

      expect(
          blocks.map((b) => b.text).join(' '), contains('Tabla 1 haciendo n=3'));
    });

    test('una nota más pequeña en minúscula no se pega a la frase', () {
      final blocks = _blocks([
        ..._filler(0),
        _body(0, 261.3, 'Una frase que la página deja sin cerrar con'),
        _frag(0, 274.8, 'nota a pie de página', size: 8, right: 190),
      ]);

      expect(_texts(blocks, ChapterBlockKind.paragraph),
          contains('nota a pie de página'));
    });

    test('una línea larga sin cerrar sigue en la siguiente', () {
      final blocks = _blocks([
        ..._filler(0),
        _frag(0, 261.3, 'Aplicamos la misma fórmula del ejercicio, esta',
            right: 300),
        _frag(0, 274.8, 'vez haciendo n igual a cuatro', left: 99, right: 260),
      ]);

      expect(_texts(blocks, ChapterBlockKind.paragraph),
          contains(contains('ejercicio, esta vez haciendo')));
    });

    test('las entradas cortas de un índice no se unen', () {
      final blocks = _blocks([
        ..._filler(0),
        _frag(0, 261.3, 'NumPy', right: 110),
        _frag(0, 274.8, 'pandas', left: 99, right: 140),
      ]);

      expect(_texts(blocks, ChapterBlockKind.paragraph), contains('pandas'));
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

    group('monoespaciada dentro de una frase', () {
      PdfTextFragment mono(double top, String text, {double left = 72}) =>
          _frag(0, top, text,
              left: left,
              right: left + text.length * 5.85,
              font: 'LiberationMono',
              size: 9.8,
              mono: true);
      PdfTextFragment serif(double top, String text, {double right = 539.9}) =>
          _frag(0, top, text,
              left: 72, right: right, font: 'LiberationSerif', size: 15);
      List<PdfTextFragment> prose() => [
            for (var i = 0; i < 8; i++)
              serif(75 + i * 18.75, 'Una línea de prosa del libro de Python.'),
          ];
      List<ChapterBlock> analyze(List<PdfTextFragment> fragments) =>
          analyzePdfLayout(fragments, const [LayoutPageSize(612, 792)])!.blocks;

      test('una URL que cierra la línea sigue en la frase', () {
        final blocks = analyze([
          ...prose(),
          serif(225, 'La documentación oficial de Python está en'),
          mono(243.75, 'https://docs.python.org/es/3/ con todos los'),
          serif(262.5, 'detalles que hagan falta.'),
        ]);

        expect(_texts(blocks, ChapterBlockKind.code), isEmpty);
        expect(
            _texts(blocks, ChapterBlockKind.paragraph),
            contains(contains('está en https://docs.python.org/es/3/ con '
                'todos los detalles que hagan falta.')));
      });

      test('el punto final en monoespaciada no abre un bloque', () {
        final blocks = analyze([
          ...prose(),
          serif(225, 'Tiene una web, pero se pasa el día tuiteando en'),
          mono(243.75, '@joelgrus.'),
          serif(262.5, 'Este libro ha sido creado para ayudar.'),
        ]);

        expect(_texts(blocks, ChapterBlockKind.code), isEmpty);
        expect(_texts(blocks, ChapterBlockKind.paragraph),
            contains(contains('tuiteando en @joelgrus.')));
      });

      test('una viñeta tras dos puntos sigue siendo texto', () {
        final blocks = analyze([
          ...prose(),
          serif(225, 'Hay varios disponibles en línea:'),
          mono(243.75, '■ Linear Algebra, en  http://joshua.smcvt.edu/'),
          serif(262.5, 'de Jim Hefferon, de Saint Michael.'),
        ]);

        expect(_texts(blocks, ChapterBlockKind.code), isEmpty);
        expect(
            _texts(blocks, ChapterBlockKind.paragraph),
            contains(contains(
                '■ Linear Algebra, en http://joshua.smcvt.edu/ de Jim')));
      });

      test('una nota al pie con una URL es texto, y una llamada no', () {
        final blocks = analyze([
          ...prose(),
          serif(225, 'Es un buen punto de partida para este estudio.'),
          mono(270, '1 https://matplotlib.org/.'),
          serif(315, 'Con esto cerramos el capítulo.'),
          mono(360, 'get("https://matplotlib.org/")'),
          serif(405, 'Y terminamos aquí.'),
        ]);

        expect(_texts(blocks, ChapterBlockKind.code),
            ['get("https://matplotlib.org/")']);
        expect(_texts(blocks, ChapterBlockKind.paragraph),
            contains('1 https://matplotlib.org/.'));
      });

      test('el código que sigue a dos puntos es un bloque', () {
        final blocks = analyze([
          ...prose(),
          serif(225, 'Podemos usar la función de error de Python:¹'),
          mono(243.75, 'def normal_cdf(x: float) -> float:'),
          serif(262.5, 'De nuevo, trazamos la figura.'),
        ]);

        expect(_texts(blocks, ChapterBlockKind.code),
            ['def normal_cdf(x: float) -> float:']);
      });

      test('el código separado de la frase es un bloque aunque no cierre', () {
        final blocks = analyze([
          ...prose(),
          serif(225, 'Podemos escribirlo de la siguiente forma'),
          mono(270, 'print("hola")'),
          serif(315, 'y ya tenemos el resultado que buscábamos.'),
        ]);

        expect(_texts(blocks, ChapterBlockKind.code), ['print("hola")']);
      });

      test('tres líneas seguidas son código aunque la frase quede abierta',
          () {
        final blocks = analyze([
          ...prose(),
          serif(225, 'Podemos escribirlo de la siguiente forma'),
          mono(243.75, 'x = 1'),
          mono(257.25, 'y = 2'),
          mono(270.75, 'print(x + y)'),
          serif(295, 'y ya tenemos el resultado que buscábamos.'),
        ]);

        expect(_texts(blocks, ChapterBlockKind.code),
            ['x = 1\ny = 2\nprint(x + y)']);
      });
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
        contains('En donde el subíndice x significa que la curva es y = x² '
            'en el intervalo pedido.'),
      );
    });

    test('la cursiva con el mismo nombre de fuente también separa palabras',
        () {
      // "la rotación de y=x² alrededor del eje x." de "Cálculo integral":
      // Syncfusion llama "Minion" a la redonda y a la cursiva.
      PdfTextFragment part(String text, double left, double right,
              {bool italic = false}) =>
          _frag(0, 190, text, left: left, right: right, italic: italic);
      final blocks = _blocks([
        ..._filler(0, lines: 6),
        part('la rotación de', 71, 130.9),
        part('y=x', 130.9, 147.5, italic: true),
        part(' alrededor del eje', 155.5, 228),
        part('x', 228, 233, italic: true),
        part('.', 233, 235.6),
      ]);

      expect(blocks.map((b) => b.text).join(' '),
          contains('la rotación de y=x alrededor del eje x.'));
    });
  });

  group('exponentes y subíndices', () {
    test('se reconocen por la altura y el desplazamiento', () {
      ScriptPosition at(double center, double height) => scriptPosition(
          baseCenter: 221, baseHeight: 11, center: center, height: height);

      expect(at(218.5, 6.4), ScriptPosition.superscript);
      expect(at(224, 6.4), ScriptPosition.subscript);
      // Versalitas: más bajas, pero sobre la misma línea base.
      expect(at(221.5, 7.7), ScriptPosition.normal);
      expect(at(218.5, 11), ScriptPosition.normal);
    });

    test('las cifras pasan a superíndice o subíndice Unicode', () {
      expect(scriptText('2', ScriptPosition.superscript), '²');
      expect(scriptText('-1', ScriptPosition.superscript), '⁻¹');
      expect(scriptText('10', ScriptPosition.subscript), '₁₀');
      // Sin versión Unicode, el texto tal cual.
      expect(scriptText('ab', ScriptPosition.superscript), 'ab');
    });
  });

  group('figuras', () {
    // Cinco líneas de relleno (la última en 153,3) y la frase que presenta la
    // ecuación pegada a ellas, en 166,8 y 180,3. Sus signos (fuente Symbol)
    // son la señal de que el libro es de matemáticas.
    List<PdfTextFragment> pageWithGap({int mathChars = 30}) => [
          ..._filler(0, lines: 5),
          _body(0, 166.8, 'En Física se estudió que el trabajo es:', left: 99),
          _frag(0, 180.3, 'cuerpo está dado por la expresión siguiente:',
              right: 382.7, mathChars: mathChars),
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

    test('en un libro sin matemáticas, una imagen baja es una figura', () {
      // "De animales a dioses": el banner de una web, de 42 pt de alto,
      // salía como "Fórmula.".
      final layout = analyzePdfLayout(pageWithGap(mathChars: 0), _pages)!;

      final blocks = resolveFigureCandidates(
          layout, const [PageRect(150, 197, 300, 215)]);

      expect(layout.allowFormulas, isFalse);
      expect(
        blocks.singleWhere((b) => b.kind == ChapterBlockKind.figure).figureKind,
        FigureKind.figure,
      );
    });

    test('una capitular no deja un hueco falso sobre su línea', () {
      // La "H" grande de "Hace unos 13.500 millones de años…" sube por encima
      // de la línea a la que pertenece: medido desde el texto normal, el
      // hueco tenía tinta (la capitular) y salía una figura falsa.
      // Relleno hasta 164,3; la capitular empieza en 170 y el texto de su
      // línea, en 190: medido desde el texto quedaba un hueco de 25,7 pt.
      final layout = analyzePdfLayout([
        ..._filler(0, lines: 5),
        _frag(0, 170, 'H', left: 71, right: 95, size: 30),
        _frag(0, 190, 'ace unos 13.500 millones de años, la materia',
            left: 95, right: 382.7),
        ..._filler(0, from: 203.5, lines: 5),
      ], _pages)!;

      expect(layout.figureCandidates, isEmpty);
      expect(layout.blocks.map((b) => b.text).join(' '),
          contains('Hace unos 13.500 millones de años'));
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

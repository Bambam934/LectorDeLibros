import 'package:equatable/equatable.dart';

/// Tipo de un [ChapterBlock].
enum ChapterBlockKind {
  /// Prosa: se reparte en oraciones y se resalta frase a frase.
  paragraph,

  /// Título de sección o rótulo de ejercicio ("Ejercicio 1", "4.6.1 Trabajo").
  heading,

  /// Código fuente: conserva los saltos de línea y la sangría.
  code,

  /// Hueco del PDF con tinta (una ecuación vectorial o una figura) que se
  /// enseña recortado del original. Su [ChapterBlock.text] es la palabra
  /// marcadora que lo representa en la lista de palabras.
  figure,
}

/// Variante de un bloque [ChapterBlockKind.figure].
enum FigureKind { formula, figure }

/// Rectángulo en una página del PDF, en puntos y con el origen arriba a la
/// izquierda, como lo devuelve el extractor de texto.
class PageRect extends Equatable {
  const PageRect(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  @override
  List<Object?> get props => [left, top, right, bottom];
}

/// Palabra que ocupa una figura en la lista de palabras del capítulo.
///
/// Las palabras son la única referencia del progreso, el resaltado y la voz:
/// la figura aporta exactamente una para que, mientras la voz la dice, se
/// resalte el bloque y los índices de lo que viene detrás no se descuadren.
const String kFormulaMarker = 'Fórmula';
const String kFigureMarker = 'Figura';

/// Un bloque de un capítulo con maquetación propia (ADR 13).
///
/// Solo los generan los PDF y los Markdown del modo offline. Un capítulo sin
/// bloques —los del servidor, las cachés antiguas, los TXT— se pinta y se lee
/// como siempre, partiendo `Chapter.text` por líneas en blanco.
class ChapterBlock extends Equatable {
  const ChapterBlock({
    required this.kind,
    required this.text,
    this.page,
    this.rect,
    this.figureKind,
    this.textHeight,
  });

  const ChapterBlock.paragraph(String text)
      : this(kind: ChapterBlockKind.paragraph, text: text);

  const ChapterBlock.heading(String text)
      : this(kind: ChapterBlockKind.heading, text: text);

  const ChapterBlock.code(String text)
      : this(kind: ChapterBlockKind.code, text: text);

  const ChapterBlock.figure({
    required int page,
    required PageRect rect,
    required FigureKind figureKind,
    double? textHeight,
  }) : this(
          kind: ChapterBlockKind.figure,
          text: figureKind == FigureKind.formula ? kFormulaMarker : kFigureMarker,
          page: page,
          rect: rect,
          figureKind: figureKind,
          textHeight: textHeight,
        );

  final ChapterBlockKind kind;

  /// Texto del bloque. En el código conserva `\n` y la sangría; en una figura
  /// es su palabra marcadora.
  final String text;

  /// Página del PDF, base 0. Solo en las figuras.
  final int? page;

  /// Zona de la página que ocupa la figura.
  final PageRect? rect;

  final FigureKind? figureKind;

  /// Altura en puntos de la letra del cuerpo del libro.
  ///
  /// Permite pintar el recorte a la misma escala que el texto que lo rodea:
  /// una ecuación sale del tamaño de la letra elegida por el lector, no
  /// estirada al ancho de la columna.
  final double? textHeight;

  /// Palabras del bloque, con la misma tokenización que `Chapter.words`.
  int get wordCount => countBlockWords(text);

  @override
  List<Object?> get props => [kind, text, page, rect, figureKind, textHeight];
}

final RegExp _whitespace = RegExp(r'\s+');

/// Número de palabras de [text], separadas por espacio en blanco.
int countBlockWords(String text) =>
    text.split(_whitespace).where((w) => w.isNotEmpty).length;

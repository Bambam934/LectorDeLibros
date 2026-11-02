/// Análisis de maquetación de los PDF del modo offline (ADR 13).
///
/// El texto plano que devuelve el extractor pierde justo lo que distingue un
/// libro técnico de una novela: las ecuaciones dibujadas como vectores no
/// existen en él, el código pierde su sangría al reflujo y los rótulos
/// ("Ejercicio 1") quedan pegados a la frase anterior. Las líneas con su
/// posición y su fuente sí lo conservan, y de ellas sale aquí una lista de
/// bloques tipados: párrafos, títulos, código y huecos candidatos a figura.
///
/// Es **puro** a propósito: recibe fragmentos propios y no los `TextLine` de
/// Syncfusion, para poder probarlo con líneas sintéticas. Las mediciones que
/// calibran cada umbral están en `.claude/docs/PLAN-BLOQUES-TIPADOS.md`.
library;

import 'dart:math' as math;

import '../../domain/entities/chapter_block.dart';

/// Un trozo de texto con su posición, tal y como lo entrega el extractor.
///
/// Syncfusion corta una línea visual en varios trozos cada vez que cambia la
/// altura del glifo: el código en línea de una frase en prosa, las versalitas
/// de una cabecera o un exponente llegan como trozos aparte a la misma altura.
/// [analyzePdfLayout] los vuelve a juntar.
class PdfTextFragment {
  const PdfTextFragment({
    required this.page,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.text,
    required this.font,
    this.bold = false,
    this.italic = false,
    this.monoChars = 0,
    this.mathChars = 0,
  });

  /// Página, base 0.
  final int page;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final String text;

  /// Nombre de la fuente dominante del trozo.
  final String font;
  final bool bold;

  /// En cursiva. Syncfusion da a veces el mismo nombre de fuente a la
  /// redonda y a la cursiva ("Minion"), y la variable de una fórmula en línea
  /// solo se distingue por esto.
  final bool italic;

  /// Caracteres visibles del trozo escritos en una fuente monoespaciada.
  final int monoChars;

  /// Caracteres del trozo en una fuente matemática (Symbol, Cambria Math…)
  /// o que son signos matemáticos (∫, √, ≤…).
  final int mathChars;

  double get height => bottom - top;

  /// Caracteres visibles (sin espacio en blanco).
  int get chars => text.replaceAll(_whitespace, '').length;

  PdfTextFragment withText(String newText) => PdfTextFragment(
        page: page,
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        text: newText,
        font: font,
        bold: bold,
        italic: italic,
        monoChars: monoChars,
        mathChars: mathChars,
      );
}

final RegExp _mathFont =
    RegExp(r'math|symbol|cmmi|cmsy|cmex|stix|euler|mtextra', caseSensitive: false);
final RegExp _mathSymbol = RegExp(r'[∫∑∏√±∞∂∆∇≤≥≠≈≡∈∉⊂⊆∪∩∀∃→⇒⇔×÷α-ωΑ-Ω]');

/// Caracteres "matemáticos" de una palabra en la fuente [fontName]: todos si
/// la fuente es matemática; si no, los signos matemáticos que lleve.
int mathCharsOf(String text, String fontName) => _mathFont.hasMatch(fontName)
    ? text.trim().length
    : _mathSymbol.allMatches(text).length;

/// Posición de un trozo respecto al texto que lo precede.
enum ScriptPosition { normal, superscript, subscript }

/// Si un trozo de altura [height] centrado en [center] es un exponente o un
/// subíndice del texto de altura [baseHeight] centrado en [baseCenter]: más
/// bajo y desplazado hacia arriba o hacia abajo. Las versalitas son más bajas
/// pero comparten la línea base, y su centro apenas se mueve.
ScriptPosition scriptPosition({
  required double baseCenter,
  required double baseHeight,
  required double center,
  required double height,
}) {
  if (baseHeight <= 0 || height >= 0.8 * baseHeight) {
    return ScriptPosition.normal;
  }
  final shift = center - baseCenter;
  if (shift < -0.15 * baseHeight) return ScriptPosition.superscript;
  if (shift > 0.15 * baseHeight) return ScriptPosition.subscript;
  return ScriptPosition.normal;
}

const _superscripts = {
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', //
  '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
  '+': '⁺', '-': '⁻', '−': '⁻', 'n': 'ⁿ',
};
const _subscripts = {
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄', //
  '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
  '+': '₊', '-': '₋', '−': '₋',
};

/// [text] escrito como exponente o subíndice Unicode ("2" → "²"), si todos
/// sus caracteres tienen versión; si no, el texto tal cual. Así "x2" se ve
/// "x²", como en el libro, y la voz puede leerlo "x al cuadrado".
String scriptText(String text, ScriptPosition position) {
  final table = switch (position) {
    ScriptPosition.superscript => _superscripts,
    ScriptPosition.subscript => _subscripts,
    ScriptPosition.normal => null,
  };
  final trimmed = text.trim();
  if (table == null || trimmed.isEmpty) return text;
  final sb = StringBuffer();
  for (final rune in trimmed.runes) {
    final mapped = table[String.fromCharCode(rune)];
    if (mapped == null) return text;
    sb.write(mapped);
  }
  return sb.toString();
}

/// Tamaño de una página en puntos.
class LayoutPageSize {
  const LayoutPageSize(this.width, this.height);

  final double width;
  final double height;
}

/// Resultado del análisis de un libro.
class PdfLayout {
  const PdfLayout({
    required this.blocks,
    required this.bodyHeight,
    required this.pitch,
    this.allowFormulas = true,
  });

  /// Bloques en orden de lectura. Los de tipo figura son **candidatos**: hay
  /// que confirmar con [resolveFigureCandidates] que el hueco tiene tinta.
  final List<ChapterBlock> blocks;

  /// Altura en puntos de la letra del cuerpo.
  final double bodyHeight;

  /// Interlineado del cuerpo, en puntos.
  final double pitch;

  /// Si una figura baja puede ser una fórmula. Solo en libros con alguna
  /// señal matemática: en uno de prosa, el banner de una web o una viñeta
  /// pequeña salían como "Fórmula." en la voz.
  final bool allowFormulas;

  /// Zonas que hay que pintar para saber si tienen tinta, en el orden en que
  /// [resolveFigureCandidates] espera la respuesta.
  List<(int, PageRect)> get figureCandidates => [
        for (final b in blocks)
          if (b.kind == ChapterBlockKind.figure) (b.page!, b.rect!),
      ];
}

final RegExp _monoFont = RegExp(
  r'mono|courier|consol|menlo|inconsolata|code|typewriter|fixed',
  caseSensitive: false,
);

/// `true` si [fontName] es una fuente monoespaciada, la marca del código.
bool isMonospaceFont(String fontName) => _monoFont.hasMatch(fontName);

/// Familia de una fuente: sin el prefijo de subconjunto (`ABCDEF+`) ni el
/// estilo (`-Regular`, `-Italic`, `,Bold`…), en minúsculas.
///
/// "Ejercicio 1" va en Albertus y el cuerpo en Minion, al mismo tamaño: es la
/// familia, no el tamaño, lo que lo delata como rótulo.
String fontFamily(String fontName) {
  var name = fontName;
  if (name.length > 7 && name[6] == '+') name = name.substring(7);
  final cut = name.indexOf(_styleSeparator);
  if (cut > 0) name = name.substring(0, cut);
  return name.toLowerCase();
}

final RegExp _styleSeparator = RegExp(r'[-,]');
final RegExp _whitespace = RegExp(r'\s+');

/// Proporción mínima de caracteres en la fuente del cuerpo. Por debajo
/// (escaneados con OCR, maquetaciones con muchas fuentes) el libro sigue con
/// el proceso de siempre.
const double _kMinBodyShare = 0.4;

/// Un título de mayor tamaño que el cuerpo lo es al menos en esta proporción.
const double _kHeadingScale = 1.15;

/// Hueco vertical mínimo, en alturas de letra del cuerpo, para sospechar que
/// hay una ecuación o una figura. Medido: las ecuaciones de "Cálculo integral"
/// dejan 28-49 pt con letra de 11 pt, y el aire sobre "Ejercicio 1" son 19 pt.
/// Un candidato de más solo cuesta mirarlo: la tinta decide.
const double _kGapFactor = 1.8;

/// Una figura de hasta esta altura, en interlineados, es una fórmula.
const double _kFormulaMaxPitches = 4;

/// Cada parte de una figura que se pinta lleva este aire alrededor de la
/// tinta, en puntos.
const double _kInkPadding = 3;

/// Caracteres matemáticos (fuente matemática o signos) a partir de los que un
/// libro se considera de matemáticas. Medido: "Cálculo integral" 226, "Ciencia
/// de datos desde cero" 89, "De animales a dioses" 0.
const int _kMinMathChars = 20;

/// Divide un libro en bloques tipados a partir de sus líneas.
///
/// Devuelve `null` cuando el libro no tiene una fuente de cuerpo clara o
/// parece maquetado a dos columnas: ahí el orden de lectura no se puede
/// deducir con estas reglas y es mejor el texto plano de siempre.
PdfLayout? analyzePdfLayout(
  List<PdfTextFragment> fragments,
  List<LayoutPageSize> pages,
) {
  final lines = _groupLines(fragments);
  if (lines.isEmpty) return null;

  final profile = _BookProfile.of(lines);
  if (profile == null) return null;

  final dropped = <int, List<_Line>>{};
  final kept = <_Line>[];
  for (final line in _withoutRunningHeads(lines, profile)) {
    if (line.chars == 0) continue;
    if (_tocLeader.hasMatch(line.text)) {
      // Índice: "4.6 Aplicaciones ........ 135". Se descarta, pero su sitio
      // no puede tomarse por un hueco con una figura.
      (dropped[line.page] ??= []).add(line);
      continue;
    }
    kept.add(line);
  }
  for (final line in lines) {
    if (line.droppedAsHead) (dropped[line.page] ??= []).add(line);
  }

  return PdfLayout(
    blocks: _assemble(kept, profile, pages, dropped),
    bodyHeight: profile.bodyHeight,
    pitch: profile.pitch,
    allowFormulas:
        fragments.fold(0, (sum, f) => sum + f.mathChars) >= _kMinMathChars,
  );
}

/// Código decimal de un glifo metido en una palabra: entre letras, o al
/// principio de una palabra seguido de dos letras o más.
final RegExp _glyphCode = RegExp(
  r'(?<=\p{L})\d{1,3}(?=\p{L})|(?<![\p{L}\p{N}])\d{1,3}(?=\p{L}{2})',
  unicode: true,
);
final RegExp _wordToken = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// Aprende a traducir los glifos que el extractor de líneas deja como su
/// código decimal.
///
/// El extractor de líneas de Syncfusion escribe con su código decimal los
/// glifos que no sabe traducir: la ligadura "fi" de Minion (código 31) sale
/// como "super31cie", mientras que el extractor de texto plano sí la traduce
/// ("superficie"). Volver a extraer todo el libro en texto plano doblaría el
/// tiempo de la primera apertura, así que se cotejan unas pocas páginas: las
/// que más palabras sospechosas tienen.
///
/// Cada palabra sospechosa se busca en el texto plano de su página **con la
/// palabra anterior o la siguiente** como contexto: sola, "1ra" casaría con
/// "Para". Un código solo se traduce si al menos dos cotejos coinciden y son
/// el 80 % de los suyos. [plainTextOf] devuelve el texto plano de una página.
Map<String, String> learnGlyphCodeFixes(
  List<PdfTextFragment> fragments,
  String Function(int page) plainTextOf, {
  int maxPages = 6,
}) {
  final contexts = <int, List<(String?, String, String?)>>{};
  for (final f in fragments) {
    final tokens = [for (final m in _wordToken.allMatches(f.text)) m[0]!];
    for (var i = 0; i < tokens.length; i++) {
      if (!_glyphCode.hasMatch(tokens[i])) continue;
      String? clean(int j) => j >= 0 &&
              j < tokens.length &&
              !_glyphCode.hasMatch(tokens[j])
          ? tokens[j]
          : null;
      (contexts[f.page] ??= []).add((clean(i - 1), tokens[i], clean(i + 1)));
    }
  }
  if (contexts.isEmpty) return const {};

  final pages = contexts.keys.toList()
    ..sort((a, b) => contexts[b]!.length.compareTo(contexts[a]!.length));
  final votes = <String, Map<String, int>>{};
  for (final page in pages.take(maxPages)) {
    final plain = plainTextOf(page);
    for (final (before, word, after) in contexts[page]!.take(60)) {
      if (before == null && after == null) continue;
      final codes = [for (final m in _glyphCode.allMatches(word)) m[0]!];
      final core = word.splitMapJoin(
        _glyphCode,
        onMatch: (_) => r'(\p{L}{1,3})',
        onNonMatch: RegExp.escape,
      );
      final lead = before == null
          ? r'(?<![\p{L}\p{N}])'
          : '${RegExp.escape(before)}' r'[^\p{L}\p{N}]+';
      final tail = after == null
          ? r'(?![\p{L}\p{N}])'
          : r'[^\p{L}\p{N}]+' '${RegExp.escape(after)}';
      final match = RegExp('$lead$core$tail', unicode: true).firstMatch(plain);
      if (match == null) continue;
      for (var i = 0; i < codes.length; i++) {
        final tally = votes[codes[i]] ??= {};
        final letters = match.group(i + 1)!;
        tally[letters] = (tally[letters] ?? 0) + 1;
      }
    }
  }

  final fixes = <String, String>{};
  for (final MapEntry(key: code, value: tally) in votes.entries) {
    final total = tally.values.fold(0, (a, b) => a + b);
    final best = tally.entries.reduce((a, b) => b.value > a.value ? b : a);
    if (best.value >= 2 && best.value * 10 >= total * 8) {
      fixes[code] = best.key;
    }
  }
  return fixes;
}

/// Aplica a [text] las traducciones de [learnGlyphCodeFixes].
String applyGlyphCodeFixes(String text, Map<String, String> fixes) =>
    fixes.isEmpty
        ? text
        : text.replaceAllMapped(_glyphCode, (m) => fixes[m[0]!] ?? m[0]!);

/// Convierte los candidatos a figura en figuras, o los quita.
///
/// [inkBounds] trae, en el orden de [PdfLayout.figureCandidates], la caja de
/// la tinta de cada hueco, o `null` si está en blanco. Pintar el hueco es lo
/// que impide inventarse una fórmula donde solo había aire (el espacio sobre
/// un título, el final de un capítulo).
List<ChapterBlock> resolveFigureCandidates(
  PdfLayout layout,
  List<PageRect?> inkBounds,
) {
  final out = <ChapterBlock>[];
  var k = 0;
  for (final block in layout.blocks) {
    if (block.kind != ChapterBlockKind.figure) {
      out.add(block);
      continue;
    }
    final ink = k < inkBounds.length ? inkBounds[k] : null;
    k++;
    // Sin tinta, o tan baja que es un filete decorativo y no una ecuación.
    if (ink == null || ink.height < 0.4 * layout.bodyHeight) continue;
    final region = block.rect!;
    final rect = PageRect(
      math.max(region.left, ink.left - _kInkPadding),
      math.max(region.top, ink.top - _kInkPadding),
      math.min(region.right, ink.right + _kInkPadding),
      math.min(region.bottom, ink.bottom + _kInkPadding),
    );
    out.add(ChapterBlock.figure(
      page: block.page!,
      rect: rect,
      figureKind: layout.allowFormulas &&
              rect.height <= _kFormulaMaxPitches * layout.pitch
          ? FigureKind.formula
          : FigureKind.figure,
      textHeight: layout.bodyHeight,
    ));
  }
  return out;
}

// ---------------------------------------------------------------------------
// Líneas visuales

class _Line {
  _Line(PdfTextFragment first) : page = first.page {
    add(first);
  }

  final int page;
  final List<PdfTextFragment> parts = [];
  double left = double.infinity;
  double right = double.negativeInfinity;
  double unionTop = double.infinity;
  double unionBottom = double.negativeInfinity;
  int chars = 0;
  int monoChars = 0;
  late PdfTextFragment _main;
  String text = '';
  bool droppedAsHead = false;

  /// Línea en monoespaciada que forma parte de una frase: va con la prosa.
  bool inlineCode = false;

  void add(PdfTextFragment f) {
    if (parts.isEmpty || f.chars > _main.chars) _main = f;
    parts.add(f);
    left = math.min(left, f.left);
    right = math.max(right, f.right);
    unionTop = math.min(unionTop, f.top);
    unionBottom = math.max(unionBottom, f.bottom);
    chars += f.chars;
    monoChars += f.monoChars;
  }

  /// Métricas del trozo con más texto: un exponente o una letra capitular no
  /// deben mover la línea.
  double get top => _main.top;
  double get bottom => _main.bottom;
  double get size => _main.height;
  String get font => _main.font;
  bool get bold => _main.bold;
  double get width => right - left;

  bool get isMono => chars > 0 && monoChars * 2 >= chars;

  /// Ancho de un carácter de código, medido sobre la propia línea.
  double get charWidth {
    final widths = <double>[
      for (final p in parts)
        if (p.monoChars > 0 && p.text.length >= 2)
          (p.right - p.left) / p.text.length,
    ];
    return widths.isEmpty ? 0.6 * size : _median(widths);
  }

  /// Une los trozos en el texto de la línea.
  void finish() {
    final mono = isMono;
    final cw = mono ? charWidth : 0.0;
    final sb = StringBuffer();
    PdfTextFragment? prev;
    // Último trozo de tamaño normal: la referencia para reconocer exponentes.
    PdfTextFragment? base;
    for (final f in parts) {
      if (prev != null && base != null && !mono && f.chars > 0) {
        final script = scriptPosition(
          baseCenter: (base.top + base.bottom) / 2,
          baseHeight: base.height,
          center: (f.top + f.bottom) / 2,
          height: f.height,
        );
        if (script != ScriptPosition.normal &&
            f.left - prev.right < 0.5 * base.height) {
          // Un exponente va pegado a lo que modifica: "x" + "2" es "x²".
          sb.write(scriptText(f.text, script));
          prev = f;
          continue;
        }
      }
      if (prev != null) {
        final gap = f.left - prev.right;
        final soFar = sb.toString();
        final hasSpace = soFar.endsWith(' ') || f.text.startsWith(' ');
        if (mono && cw > 0 && gap > 0.6 * cw) {
          // En el código, el hueco entre trozos es alineación (un comentario
          // a la derecha): se respeta en caracteres.
          final n = (gap / cw).round();
          sb.write(' ' * math.max(hasSpace ? 0 : 1, n));
        } else if (!hasSpace &&
            (gap > 0.15 * size || _fontBoundary(prev, f, soFar))) {
          sb.write(' ');
        }
      }
      sb.write(f.text);
      prev = f;
      if (f.chars > 0) base = f;
    }
    final raw = sb.toString();
    text = mono ? raw.trim() : raw.replaceAll(_whitespace, ' ').trim();
  }
}

final RegExp _endsInWord = RegExp(r'[\p{L}\p{N}]$', unicode: true);
final RegExp _startsWord = RegExp(r'^[\p{L}\p{N}(“"«¿¡\[]', unicode: true);

/// `true` si entre [prev] y [next] hay una frontera de palabra sin espacio:
/// la variable en cursiva de una fórmula en línea va en otra fuente, o en la
/// misma pero en cursiva, y pegada ("eje" + "x"). Un exponente o un
/// subíndice, más bajos, sí van pegados.
bool _fontBoundary(PdfTextFragment prev, PdfTextFragment next, String soFar) =>
    (prev.font != next.font || prev.italic != next.italic) &&
    next.height >= 0.8 * prev.height &&
    prev.height >= 0.8 * next.height &&
    _endsInWord.hasMatch(soFar) &&
    _startsWord.hasMatch(next.text);

/// Junta los trozos que comparten línea visual.
///
/// Se recorren en el orden del documento, que es el de lectura en un libro
/// a una columna. Un trozo se une a una de las últimas líneas de su página si
/// se solapa con ella en vertical y empieza a su derecha. Se mira más de una
/// línea atrás porque el código alinea comentarios a la derecha y el PDF a
/// veces los escribe después de la línea siguiente.
List<_Line> _groupLines(List<PdfTextFragment> fragments) {
  final lines = <_Line>[];
  final recent = <_Line>[];
  var page = -1;
  for (final f in fragments) {
    if (f.page != page) {
      recent.clear();
      page = f.page;
    }
    _Line? target;
    for (var i = recent.length - 1; i >= 0; i--) {
      if (_continuesLine(recent[i], f)) {
        target = recent[i];
        break;
      }
    }
    if (target != null) {
      target.add(f);
    } else {
      final line = _Line(f);
      lines.add(line);
      recent.add(line);
      if (recent.length > 4) recent.removeAt(0);
    }
  }
  for (final line in lines) {
    line.finish();
  }
  return lines;
}

bool _continuesLine(_Line line, PdfTextFragment f) {
  final minHeight = math.min(line.unionBottom - line.unionTop, f.height);
  if (minHeight <= 0) return false;
  final overlap = math.min(line.unionBottom, f.bottom) -
      math.max(line.unionTop, f.top);
  if (overlap < 0.5 * minHeight) return false;
  return f.left >= line.right - 0.5 * minHeight;
}

// ---------------------------------------------------------------------------
// Perfil del libro

class _BookProfile {
  _BookProfile({
    required this.bodyFamily,
    required this.bodyHeight,
    required this.bodyBold,
    required this.pitch,
    required this.codePitch,
    required this.colLeft,
    required this.colRight,
    required this.textTop,
    required this.textBottom,
  });

  final String bodyFamily;
  final double bodyHeight;
  final bool bodyBold;
  final double pitch;
  final double codePitch;

  /// Márgenes de la columna en páginas pares e impares: un libro impreso
  /// alterna el margen interior y el exterior.
  final List<double> colLeft;
  final List<double> colRight;

  /// Mediana, por página, de dónde empieza y acaba el texto del cuerpo. Lo
  /// que queda fuera es cabecera o pie.
  final double textTop;
  final double textBottom;

  double colLeftOf(int page) => colLeft[page % 2];
  double colRightOf(int page) => colRight[page % 2];
  double colWidthOf(int page) => colRightOf(page) - colLeftOf(page);

  static _BookProfile? of(List<_Line> lines) {
    final charsByKey = <String, int>{};
    final heightByKey = <String, double>{};
    final boldByKey = <String, int>{};
    var total = 0;
    for (final l in lines) {
      total += l.chars;
      if (l.isMono || l.chars == 0) continue;
      final key = '${fontFamily(l.font)}|${_quantize(l.size)}';
      charsByKey[key] = (charsByKey[key] ?? 0) + l.chars;
      heightByKey[key] = _quantize(l.size);
      if (l.bold) boldByKey[key] = (boldByKey[key] ?? 0) + l.chars;
    }
    if (total == 0 || charsByKey.isEmpty) return null;
    final bodyKey = charsByKey.entries
        .reduce((a, b) => b.value > a.value ? b : a)
        .key;
    if (charsByKey[bodyKey]! < _kMinBodyShare * total) return null;
    final bodyFamily = bodyKey.substring(0, bodyKey.lastIndexOf('|'));
    final bodyHeight = heightByKey[bodyKey]!;
    if (bodyHeight <= 0) return null;
    final bodyBold = (boldByKey[bodyKey] ?? 0) * 2 > charsByKey[bodyKey]!;

    bool isBody(_Line l) =>
        !l.isMono &&
        fontFamily(l.font) == bodyFamily &&
        _quantize(l.size) == bodyHeight;

    final body = [for (final l in lines) if (isBody(l)) l];
    final code = [for (final l in lines) if (l.isMono) l];
    final pitch = _typicalPitch(body, bodyHeight) ?? 1.2 * bodyHeight;
    final codeHeight = code.isEmpty
        ? bodyHeight
        : _median([for (final l in code) l.size]);
    final codePitch = _typicalPitch(code, codeHeight) ?? 1.3 * codeHeight;

    final colLeft = <double>[0, 0];
    final colRight = <double>[0, 0];
    for (final parity in [0, 1]) {
      var side = [for (final l in body) if (l.page % 2 == parity) l];
      if (side.length < 3) side = body;
      colLeft[parity] = _percentile([for (final l in side) l.left], 0.15);
      colRight[parity] = _percentile([for (final l in side) l.right], 0.85);
      final width = colRight[parity] - colLeft[parity];
      if (width <= 0) return null;
      // Dos columnas: una de cada cuatro líneas de cuerpo empieza pasada la
      // mitad de la "columna", que en realidad abarca las dos.
      final pastMiddle = side
          .where((l) => l.left > colLeft[parity] + 0.45 * width)
          .length;
      if (pastMiddle >= 0.25 * side.length) return null;
    }

    final firstTops = <int, double>{};
    final lastBottoms = <int, double>{};
    for (final l in body) {
      firstTops[l.page] = math.min(firstTops[l.page] ?? double.infinity, l.top);
      lastBottoms[l.page] =
          math.max(lastBottoms[l.page] ?? double.negativeInfinity, l.bottom);
    }

    return _BookProfile(
      bodyFamily: bodyFamily,
      bodyHeight: bodyHeight,
      bodyBold: bodyBold,
      pitch: pitch,
      codePitch: codePitch,
      colLeft: colLeft,
      colRight: colRight,
      textTop: _median(firstTops.values.toList()),
      textBottom: _median(lastBottoms.values.toList()),
    );
  }
}

/// Mediana de la distancia entre líneas seguidas de la misma página, entre
/// 0,9 y 2,2 alturas de letra (fuera de ese rango no son líneas seguidas).
double? _typicalPitch(List<_Line> lines, double height) {
  final deltas = <double>[];
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].page != lines[i - 1].page) continue;
    final d = lines[i].top - lines[i - 1].top;
    if (d > 0.9 * height && d < 2.2 * height) deltas.add(d);
  }
  return deltas.isEmpty ? null : _median(deltas);
}

double _quantize(double size) => (size * 2).round() / 2;

double _median(List<double> values) => _percentile(values, 0.5);

double _percentile(List<double> values, double p) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  return sorted[(p * (sorted.length - 1)).round()];
}

// ---------------------------------------------------------------------------
// Cabeceras, pies e índice

final RegExp _tocLeader = RegExp(r'(\.\s?){5,}');
final RegExp _pageNumber = RegExp(r'^[-–—\s]*(\d{1,4}|[ivxlcdm]{1,7})[-–—\s]*$',
    caseSensitive: false);
final RegExp _digits = RegExp(r'\d+');
final RegExp _caption = RegExp(
  r'^(figura|fig\.?|tabla|gr[áa]fic[ao]|imagen|cuadro|ilustraci[óo]n)\s*\d',
  caseSensitive: false,
);

/// Quita las cabeceras y los pies de página.
///
/// Solo mira las líneas que quedan por encima de donde empieza el texto del
/// cuerpo en una página típica, o por debajo de donde acaba: así un
/// "Ejercicio 2" al principio de una página no se confunde con la cabecera
/// por repetirse en varias. Ahí se descarta lo que se repite, sin contar las
/// cifras, **a la misma altura** en tres páginas o más, y los números de
/// página sueltos.
///
/// La misma altura importa: sin cifras, "Figura 39" y "Figura 55" son el
/// mismo texto, y los pies de figura que caían bajo el texto se tomaban por
/// pies de página (faltaban 15 de 78 en "Cálculo integral"). Una cabecera
/// está siempre en el mismo sitio; un pie de figura, donde caiga la figura.
/// Por si coinciden, un pie de figura ("Figura 12", "Tabla 3") nunca es una
/// cabecera.
Iterable<_Line> _withoutRunningHeads(List<_Line> lines, _BookProfile p) sync* {
  final margin = 0.25 * p.pitch;
  bool inZone(_Line l) =>
      l.unionBottom <= p.textTop - margin || l.unionTop >= p.textBottom + margin;
  String signature(_Line l) => '${fontFamily(l.font)}|${_quantize(l.size)}|'
      '${l.text.toLowerCase().replaceAll(_digits, '').replaceAll(_whitespace, ' ').trim()}';

  final bySignature = <String, List<_Line>>{};
  for (final l in lines) {
    if (inZone(l)) (bySignature[signature(l)] ??= []).add(l);
  }
  for (final l in lines) {
    if (inZone(l) && !_caption.hasMatch(l.text)) {
      final pagesAtSameHeight = {
        for (final other in bySignature[signature(l)]!)
          if ((other.unionTop - l.unionTop).abs() <= 2.5) other.page,
      };
      final repeated = pagesAtSameHeight.length >= 3;
      final folio = _pageNumber.hasMatch(l.text) &&
          l.size <= 1.2 * p.bodyHeight;
      if (repeated || folio) {
        l.droppedAsHead = true;
        continue;
      }
    }
    yield l;
  }
}

// ---------------------------------------------------------------------------
// Clasificación y montaje de bloques

enum _Kind { body, heading, code }

String _styleKey(_Line l) =>
    '${fontFamily(l.font)}|${_quantize(l.size)}|${l.bold}';

bool _looksLikeHeading(_Line l, _Line? prev, _BookProfile p) {
  if (l.chars < 2 || l.text.length > 160) return false;
  if (l.size >= p.bodyHeight * _kHeadingScale) return true;
  // Más pequeño que el cuerpo: pies de figura, notas, créditos. Nunca título.
  if (l.size < p.bodyHeight * 0.95) return false;
  final otherFamily = fontFamily(l.font) != p.bodyFamily;
  final bolder = l.bold && !p.bodyBold;
  if (!otherFamily && !bolder) return false;
  if (l.width > 0.85 * p.colWidthOf(l.page)) return false;
  // Aislado: si la línea anterior va en el mismo estilo y sin aire entre
  // ambas, es la última línea (corta) de un párrafo en otra fuente.
  if (prev == null || prev.page != l.page) return true;
  if (_styleKey(prev) != _styleKey(l)) return true;
  return l.top - prev.bottom >= 0.4 * p.pitch;
}

/// Líneas seguidas en monoespaciada que aún pueden ser parte de una frase.
const _kInlineCodeLines = 2;

final RegExp _sentenceEnd = RegExp(r'[.!?:;…»"”)\]]$');

/// `true` si la línea de cuerpo [l] abre párrafo tras la línea [prev].
bool _startsParagraph(_Line prev, _Line l, _BookProfile p) {
  // Otra fuente u otro tamaño: un pie de figura, una cita, una nota. Sin
  // esto, el pie "Figura 39" de la página siguiente se pegaba a la frase
  // que la página anterior dejaba a medias.
  if (!prev.inlineCode &&
      !l.inlineCode &&
      _styleKey(prev) != _styleKey(l)) {
    return true;
  }
  final endsSentence = _sentenceEnd.hasMatch(prev.text);
  final prevShort = prev.right <
      p.colRightOf(prev.page) - 0.12 * p.colWidthOf(prev.page);
  if (prev.page == l.page) {
    if (l.top - prev.top > 1.45 * p.pitch) return true;
  } else if (prevShort && endsSentence) {
    return true;
  }
  // Sangría de primera línea, pero solo si la anterior cerraba algo: en una
  // lista con sangría francesa las continuaciones también entran más adentro.
  final indented = l.left - p.colLeftOf(l.page) >= 0.8 * p.bodyHeight;
  return indented && (endsSentence || prevShort);
}

final RegExp _closedLine = RegExp(r'[.!?:;…»"”)\]][¹²³⁴-⁹⁰]*$');
final RegExp _colonLine = RegExp(r':[¹²³⁴-⁹⁰]*$');
final RegExp _startsBullet = RegExp(r'^[■•▪●]');
final RegExp _plainUrl = RegExp(r'^[^()=\[\]{}"$]*https?://[^()=\[\]{}"$]*$');

/// Devuelve a la prosa las líneas en monoespaciada que están dentro de una
/// frase: una URL o un nombre de función que ocupa casi toda la línea.
///
/// Un trozo de hasta [_kInlineCodeLines] líneas, pegado al texto, sigue la
/// frase si la anterior quedó abierta o la siguiente empieza en minúscula.
/// Tras dos puntos es código de verdad, salvo que sea una viñeta. Una URL
/// sin sintaxis de código alrededor (una nota al pie) tampoco es código.
/// Sin esto, el párrafo se partía y la voz decía «Bloque de código» a media
/// frase.
void _absorbInlineCode(List<_Line> lines, List<_Kind> kinds, _BookProfile p) {
  bool adjacent(_Line a, _Line b) =>
      a.page != b.page || b.top - a.top <= 1.45 * p.pitch;

  var i = 0;
  while (i < lines.length) {
    if (kinds[i] != _Kind.code) {
      i++;
      continue;
    }
    var end = i;
    while (end + 1 < lines.length && kinds[end + 1] == _Kind.code) {
      end++;
    }
    if (end - i + 1 <= _kInlineCodeLines) {
      final before = i > 0 &&
              kinds[i - 1] == _Kind.body &&
              adjacent(lines[i - 1], lines[i])
          ? lines[i - 1]
          : null;
      final after = end + 1 < lines.length &&
              kinds[end + 1] == _Kind.body &&
              adjacent(lines[end], lines[end + 1])
          ? lines[end + 1]
          : null;
      final opens = before != null && !_closedLine.hasMatch(before.text);
      final afterColon = before != null &&
          _colonLine.hasMatch(before.text) &&
          !_startsBullet.hasMatch(lines[i].text);
      final flows = after != null &&
          _startsLower.hasMatch(after.text) &&
          !afterColon;
      final urls = [
        for (var j = i; j <= end; j++) lines[j].text,
      ].every(_plainUrl.hasMatch);
      if (opens || flows || urls) {
        for (var j = i; j <= end; j++) {
          kinds[j] = _Kind.body;
          lines[j].inlineCode = true;
          lines[j].text = lines[j].text.replaceAll(_whitespace, ' ');
        }
      }
    }
    i = end + 1;
  }
}

List<ChapterBlock> _assemble(
  List<_Line> lines,
  _BookProfile p,
  List<LayoutPageSize> pages,
  Map<int, List<_Line>> dropped,
) {
  final kinds = <_Kind>[
    for (var i = 0; i < lines.length; i++)
      if (lines[i].isMono)
        _Kind.code
      else if (_looksLikeHeading(lines[i], i > 0 ? lines[i - 1] : null, p))
        _Kind.heading
      else
        _Kind.body,
  ];
  _absorbInlineCode(lines, kinds, p);

  final blocks = <ChapterBlock>[];
  final group = <_Line>[];
  _Kind? groupKind;

  void flush() {
    if (group.isEmpty) return;
    switch (groupKind!) {
      case _Kind.body:
        final text = joinProseLines([for (final l in group) l.text]);
        if (text.isNotEmpty) blocks.add(ChapterBlock.paragraph(text));
      case _Kind.heading:
        final text = joinProseLines([for (final l in group) l.text]);
        if (text.isNotEmpty) blocks.add(ChapterBlock.heading(text));
      case _Kind.code:
        final text = _codeText(group, p);
        if (text.trim().isNotEmpty) blocks.add(ChapterBlock.code(text));
    }
    group.clear();
    groupKind = null;
  }

  _Line? prev;
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final kind = kinds[i];

    var gapBreak = false;
    // El hueco va de la letra más baja de una línea a la más alta de la
    // siguiente: con las métricas del trozo dominante, las letras grandes de
    // un título o una capitular quedaban dentro y contaban como tinta.
    if (prev != null && prev.page == l.page && l.unionTop > prev.unionBottom) {
      final gapTop = prev.unionBottom;
      final gapBottom = l.unionTop;
      if (gapBottom - gapTop >= _kGapFactor * p.bodyHeight &&
          !_coversDropped(dropped[l.page], gapTop, gapBottom)) {
        flush();
        final page = l.page < pages.length ? pages[l.page] : null;
        final left = p.colLeftOf(l.page);
        final right = p.colRightOf(l.page);
        final margin = 0.15 * (right - left);
        blocks.add(ChapterBlock.figure(
          page: l.page,
          rect: PageRect(
            math.max(0.0, left - margin),
            gapTop,
            page == null ? right + margin : math.min(page.width, right + margin),
            gapBottom,
          ),
          // Provisional: lo decide la altura de la tinta.
          figureKind: FigureKind.figure,
          textHeight: p.bodyHeight,
        ));
        gapBreak = true;
      }
    }

    final continues = !gapBreak &&
        group.isNotEmpty &&
        groupKind == kind &&
        switch (kind) {
          _Kind.code => true,
          _Kind.heading => group.last.page == l.page &&
              _styleKey(group.last) == _styleKey(l) &&
              l.top - group.last.top <= 1.8 * l.size,
          _Kind.body => !_startsParagraph(group.last, l, p),
        };
    if (!continues) {
      flush();
      groupKind = kind;
    }
    group.add(l);
    prev = l;
  }
  flush();
  return blocks;
}

/// `true` si alguna línea descartada (índice, cabecera) cae dentro del hueco:
/// entonces el hueco no está vacío, solo se quitó lo que había.
bool _coversDropped(List<_Line>? dropped, double top, double bottom) {
  if (dropped == null) return false;
  for (final l in dropped) {
    final center = (l.unionTop + l.unionBottom) / 2;
    if (center > top && center < bottom) return true;
  }
  return false;
}

/// Texto de un bloque de código: una línea por línea del PDF, con la sangría
/// reconstruida desde la posición horizontal.
///
/// La sangría se mide en caracteres respecto a la línea más a la izquierda.
/// Si los saltos son regulares (el libro sangra cada nivel 15 pt, que son
/// 2,56 caracteres) se redondea por niveles, para que todos los niveles midan
/// lo mismo en pantalla en lugar de alternar 3 y 2 espacios.
String _codeText(List<_Line> lines, _BookProfile p) {
  final cw = _median([for (final l in lines) l.charWidth]);
  final base = lines.map((l) => l.left).reduce(math.min);
  final offsets = [for (final l in lines) l.left - base];
  final steps = offsets.where((o) => o > 0.5 * cw).toList()..sort();
  final step = steps.isEmpty ? null : steps.first;
  final regular = step != null &&
      offsets.every((o) {
        if (o <= 0.5 * cw) return true;
        final ratio = o / step;
        return (ratio - ratio.round()).abs() < 0.2;
      });
  final perStep = step == null ? 0 : math.max(2, (step / cw).round());

  final out = <String>[];
  _Line? prev;
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (prev != null &&
        prev.page == l.page &&
        l.top - prev.top > 1.6 * p.codePitch) {
      out.add('');
    }
    final o = offsets[i];
    final indent = o <= 0.5 * cw
        ? 0
        : regular
            ? (o / step).round() * perStep
            : (o / cw).round();
    out.add('${' ' * indent}${l.text}');
    prev = l;
  }
  return out.join('\n');
}

final RegExp _letterHyphenEnd = RegExp(r'\p{L}-$', unicode: true);
final RegExp _startsLower = RegExp(r'^\p{Ll}', unicode: true);
final RegExp _startsUpper = RegExp(r'^\p{Lu}', unicode: true);

/// Une las líneas de un párrafo deshaciendo el guion de corte.
///
/// "pro-" + "blema" es una palabra partida: se une sin guion. "Cuenca-" +
/// "Ecuador" es un compuesto partido por su propio guion: se conserva. El
/// guion suave (U+00AD) siempre es de corte.
String joinProseLines(List<String> lines) {
  final pieces = <String>[];
  for (final line in lines) {
    if (line.isEmpty) continue;
    if (pieces.isEmpty) {
      pieces.add(line);
      continue;
    }
    final last = pieces.last;
    if (last.endsWith('­') ||
        (_letterHyphenEnd.hasMatch(last) && _startsLower.hasMatch(line))) {
      pieces[pieces.length - 1] = last.substring(0, last.length - 1);
    } else if (!(_letterHyphenEnd.hasMatch(last) &&
        _startsUpper.hasMatch(line))) {
      pieces.add(' ');
    }
    pieces.add(line);
  }
  return pieces.join();
}

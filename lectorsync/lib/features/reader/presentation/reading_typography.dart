/// Reglas tipográficas del lector, como funciones puras.
///
/// Viven fuera del árbol de widgets para poder fijarlas con tests: antes eran
/// números sueltos dentro de un `build()` privado y cualquiera podía cambiarlos
/// sin que saltara nada.
library;

/// Sangría de primera línea de párrafo, en píxeles lógicos.
///
/// Proporcional al cuerpo (1,2 em) y no un valor fijo: una sangría de 24 px se
/// nota con el texto a 14 px y desaparece con el texto a 32.
///
/// Devuelve 0 en dos casos:
/// - **Primer párrafo del capítulo**: la sangría significa "empieza otro
///   párrafo" y después de un título no hay ninguno anterior del que
///   separarse. Es la convención de cualquier libro impreso.
/// - **Fórmula**: se presenta centrada como bloque aparte, y sangrarla la
///   descolocaría.
double paragraphIndent({
  required double fontSize,
  bool isFirstParagraph = false,
  bool isFormula = false,
}) {
  if (isFirstParagraph || isFormula) return 0;
  return fontSize * indentEm;
}

/// Sangría en ems del cuerpo.
const double indentEm = 1.2;

/// Escala del número de capítulo respecto al cuerpo.
const double chapterNumberScale = 1.6;

/// Escala del título de capítulo respecto al cuerpo.
const double chapterTitleScale = 1.25;

/// Tamaño del número de capítulo para un cuerpo de [bodyFontSize].
double chapterNumberSize(double bodyFontSize) =>
    bodyFontSize * chapterNumberScale;

/// Tamaño del título de capítulo para un cuerpo de [bodyFontSize].
///
/// Se deriva del cuerpo en vez de ser fijo porque con la fuente al máximo un
/// título clavado en 20 px acababa siendo más pequeño que el texto que
/// encabeza, invirtiendo la jerarquía.
double chapterTitleSize(double bodyFontSize) =>
    bodyFontSize * chapterTitleScale;

/// Caracteres por línea que caben aproximadamente en [width] con una fuente
/// de [fontSize].
///
/// El 0,5 es el ancho medio de un carácter en una tipografía de lectura,
/// expresado en ems. Es una aproximación grosera, pero suficiente para saber
/// si una medida de línea está dentro del rango cómodo.
double charactersPerLine({required double width, required double fontSize}) {
  if (fontSize <= 0) return 0;
  return width / (fontSize * 0.5);
}

/// Rango de medida de línea cómodo para lectura continua.
///
/// La horquilla clásica es de 45 a 75 caracteres: por debajo el ojo salta de
/// línea demasiado a menudo, por encima cuesta encontrar dónde empieza la
/// siguiente.
const int minComfortableMeasure = 45;
const int maxComfortableMeasure = 75;

/// `true` si la medida de línea resultante cae en el rango cómodo.
bool isComfortableMeasure({required double width, required double fontSize}) {
  final chars = charactersPerLine(width: width, fontSize: fontSize);
  return chars >= minComfortableMeasure && chars <= maxComfortableMeasure;
}

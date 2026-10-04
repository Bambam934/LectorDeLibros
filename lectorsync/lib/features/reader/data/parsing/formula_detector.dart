/// Detecta los párrafos que en realidad son una fórmula matemática aplanada.
///
/// Cuando se extrae texto de un PDF, una ecuación pierde su maquetación y
/// queda como una tira de símbolos: la integral de un libro de cálculo acaba
/// siendo `10.50.5(1)2+1=`. El TTS lo lee literalmente ("diez punto cincuenta
/// punto cinco...") y la pantalla lo muestra apelmazado en mitad del párrafo.
///
/// Reconocer estos bloques es el paso previo a cualquier tratamiento: sin
/// saber DÓNDE está la fórmula no se puede ni silenciarla al leer ni
/// destacarla al mostrarla.
///
/// La heurística NO intenta entender la fórmula, solo distinguirla de la
/// prosa. Se apoya en dos hechos que se cumplen siempre: una fórmula tiene
/// pocas letras en proporción a los símbolos, y casi ninguna palabra de
/// verdad.
library;

/// Símbolos que solo aparecen en notación matemática.
const _mathSymbols = '∫∑∏√±∞∂∆∇≤≥≠≈≡∈∉⊂⊆∪∩∀∃→⇒⇔×÷·';

/// Caracteres que actúan como operador o delimitador.
const _operators = r'=+-−*/^_<>()[]{}|';

/// Los mismos conjuntos, indexados por punto de código.
///
/// La heurística corre sobre cada párrafo del capítulo al abrirlo, en el mismo
/// frame que ya monta el texto entero. Recorrer el texto con `split('')` o con
/// `String.fromCharCode` asignaba dos Strings de un carácter por cada carácter
/// del capítulo —más de 200.000 en un capítulo normal— y eso se notaba como
/// uno o dos frames perdidos al cambiar de capítulo en un móvil.
final Set<int> _mathSymbolCodes = _mathSymbols.runes.toSet();
final Set<int> _operatorCodes = _operators.runes.toSet();

/// Letras aceptadas dentro de una palabra en español.
final _wordRe = RegExp(r'^[a-záéíóúüñ]{3,}$', caseSensitive: false);

final _letterRe = RegExp(r'[a-záéíóúüñ]', caseSensitive: false);
final _whitespaceRe = RegExp(r'\s+');

/// Puntuación que puede colgar de una palabra sin dejar de serlo.
final _trailingPunctRe = RegExp(r'^[¿¡("]+|[.,;:!?)"]+$');

/// Teléfonos y faxes de una página de créditos: "P.B.X. (+593 7) 2050000",
/// "Fax: (+593 7) 4 088958", "Tel. 2050000". Tienen paréntesis, un signo
/// más y casi ninguna letra, así que pasaban por fórmula y salían enmarcados.
final _phoneRe = RegExp(
  r'\b(?:tel[ée]fono|telf?|fax|p\.?\s?b\.?\s?x)\b|\(\+\d{1,3}[\d\s]*\)\s*\d[\d\s-]{4,}',
  caseSensitive: false,
);

/// Proporción máxima de letras para considerar el bloque una fórmula.
///
/// La prosa española ronda 0,80: incluso una frase cargada de cifras como
/// "El capítulo 3 trata de la integral entre 0 y 1" se queda en 0,84.
const _maxAlphaRatio = 0.5;

/// Proporción máxima de palabras reales sobre el total de tokens.
const _maxWordRatio = 0.34;

/// Igual que [_maxWordRatio], pero para bloques que ya traen símbolos
/// inequívocamente matemáticos: ahí podemos ser más permisivos con las letras
/// sueltas, que suelen ser las variables.
const _maxWordRatioWithSymbols = 0.5;

/// `true` si [paragraph] parece una fórmula y no prosa.
///
/// Es deliberadamente conservador: ante la duda devuelve `false`. Marcar texto
/// normal como fórmula haría que el lector se saltase contenido real, que es
/// peor que leer mal una ecuación.
bool looksLikeFormula(String paragraph) {
  final text = paragraph.trim();
  if (text.isEmpty) return false;
  if (_phoneRe.hasMatch(text)) return false;

  final tokens = text.split(_whitespaceRe).where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return false;

  // Sin un solo operador o símbolo matemático no es una fórmula, por muchos
  // dígitos que tenga: descarta números de página ("42") y romanos ("III").
  // Ambos se cuentan en la MISMA pasada.
  var symbolCount = 0;
  var hasOperator = false;
  for (final rune in text.runes) {
    if (_mathSymbolCodes.contains(rune)) {
      symbolCount++;
    } else if (!hasOperator && _operatorCodes.contains(rune)) {
      hasOperator = true;
    }
  }
  if (symbolCount == 0 && !hasOperator) return false;

  final nonSpace = text.replaceAll(_whitespaceRe, '');
  if (nonSpace.isEmpty) return false;

  final letters = _letterRe.allMatches(nonSpace).length;
  final alphaRatio = letters / nonSpace.length;
  if (alphaRatio >= _maxAlphaRatio) return false;

  final realWords = tokens.where(_isRealWord).length;
  final wordRatio = realWords / tokens.length;

  final threshold =
      symbolCount >= 2 ? _maxWordRatioWithSymbols : _maxWordRatio;
  return wordRatio < threshold;
}

bool _isRealWord(String token) {
  final bare = token.replaceAll(_trailingPunctRe, '');
  return _wordRe.hasMatch(bare);
}

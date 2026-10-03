/// Unidad de habla que el pipeline TTS envía al engine: un fragmento de
/// texto con su porción alineada de la lista global de palabras.
///
/// `globalStartWordIndex` es lo que permite que el seguidor de texto
/// (highlight) siga funcionando cuando el capítulo se parte en varias
/// utterances: cada segmento sabe en qué palabra del capítulo empieza.
class SpeakSegment {
  const SpeakSegment({
    required this.text,
    required this.words,
    required this.globalStartWordIndex,
    required this.audibleCharCount,
    required this.hasNumbers,
    this.isFormula = false,
  });

  final String text;
  final List<String> words;
  final int globalStartWordIndex;
  final int audibleCharCount;
  final bool hasNumbers;

  /// [text] es un aviso sintético ("Fórmula.") y NO se deriva de [words].
  ///
  /// Quien necesite rehacer el texto del segmento —la recuperación tras un
  /// utterance interrumpido— debe respetar esta marca: reconstruirlo desde
  /// [words] devolvería la ecuación aplanada que el aviso vino a sustituir.
  final bool isFormula;
}

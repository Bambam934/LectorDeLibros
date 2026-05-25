/// Lightweight language detection based on common word frequency.
///
/// Samples the first ~200 words of a text and scores against known
/// high-frequency words for each supported language. Returns an IETF
/// language tag (e.g. 'es-ES', 'en-US', 'fr-FR') suitable for TTS.
class LanguageDetector {
  LanguageDetector._();

  static const _commonWords = <String, List<String>>{
    'es': [
      'de', 'la', 'el', 'en', 'y', 'los', 'del', 'se', 'las', 'por',
      'un', 'para', 'con', 'no', 'una', 'su', 'al', 'es', 'lo', 'como',
      'más', 'pero', 'sus', 'le', 'ya', 'o', 'fue', 'este', 'ha', 'sí',
      'porque', 'esta', 'entre', 'cuando', 'muy', 'sin', 'sobre', 'ser',
      'también', 'me', 'hasta', 'hay', 'donde', 'quien', 'desde', 'todo',
      'nos', 'durante', 'todos', 'uno', 'les', 'ni', 'contra', 'otros',
      'ese', 'eso', 'ante', 'ellos', 'e', 'esto', 'mí', 'antes', 'que',
    ],
    'en': [
      'the', 'be', 'to', 'of', 'and', 'a', 'in', 'that', 'have', 'i',
      'it', 'for', 'not', 'on', 'with', 'he', 'as', 'you', 'do', 'at',
      'this', 'but', 'his', 'by', 'from', 'they', 'we', 'say', 'her',
      'she', 'or', 'an', 'will', 'my', 'one', 'all', 'would', 'there',
      'their', 'what', 'so', 'up', 'out', 'if', 'about', 'who', 'get',
      'which', 'go', 'me', 'when', 'make', 'can', 'like', 'time', 'no',
      'just', 'him', 'know', 'take', 'people', 'into', 'year', 'your',
    ],
    'fr': [
      'de', 'la', 'le', 'et', 'les', 'des', 'en', 'un', 'du', 'une',
      'que', 'est', 'pas', 'au', 'il', 'sur', 'ne', 'se', 'ce', 'qui',
      'dans', 'pour', 'plus', 'par', 'avec', 'son', 'sont', 'mais',
      'nous', 'vous', 'cette', 'ou', 'leur', 'ses', 'ont', 'été', 'tout',
      'comme', 'aussi', 'elle', 'peut', 'fait', 'entre', 'même', 'aux',
    ],
    'pt': [
      'de', 'a', 'o', 'que', 'e', 'do', 'da', 'em', 'um', 'para',
      'com', 'não', 'uma', 'os', 'no', 'se', 'na', 'por', 'mais', 'as',
      'dos', 'como', 'mas', 'foi', 'ao', 'ele', 'das', 'tem', 'à', 'seu',
      'sua', 'ou', 'ser', 'quando', 'muito', 'há', 'nos', 'já', 'está',
    ],
    'de': [
      'der', 'die', 'und', 'in', 'den', 'von', 'zu', 'das', 'mit', 'sich',
      'des', 'auf', 'für', 'ist', 'im', 'dem', 'nicht', 'ein', 'eine',
      'als', 'auch', 'es', 'an', 'werden', 'aus', 'er', 'hat', 'dass',
      'sie', 'nach', 'wird', 'bei', 'einer', 'um', 'am', 'sind', 'noch',
    ],
    'it': [
      'di', 'e', 'il', 'la', 'che', 'in', 'un', 'per', 'non', 'del',
      'una', 'si', 'da', 'con', 'le', 'dei', 'ha', 'è', 'sono', 'alla',
      'nel', 'al', 'lo', 'questo', 'gli', 'come', 'più', 'anche', 'suo',
    ],
  };

  /// Map language code to the best TTS locale tag.
  static const _localeMap = <String, String>{
    'es': 'es-ES',
    'en': 'en-US',
    'fr': 'fr-FR',
    'pt': 'pt-BR',
    'de': 'de-DE',
    'it': 'it-IT',
  };

  /// Detect the language of [text] by sampling the first ~200 words.
  /// Returns an IETF tag like 'es-ES' or 'en-US'.
  /// Falls back to [fallback] if detection is inconclusive.
  static String detect(String text, {String fallback = 'es-ES'}) {
    final words = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\s]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1)
        .take(200)
        .toList();

    if (words.length < 10) return fallback;

    final wordSet = words.toSet();
    final scores = <String, int>{};

    for (final entry in _commonWords.entries) {
      final lang = entry.key;
      final commonList = entry.value;
      var score = 0;
      for (final common in commonList) {
        if (wordSet.contains(common)) {
          // Count frequency — common words that appear multiple times
          // strengthen the signal.
          score += words.where((w) => w == common).length;
        }
      }
      scores[lang] = score;
    }

    // Find highest score.
    String? bestLang;
    int bestScore = 0;
    for (final entry in scores.entries) {
      if (entry.value > bestScore) {
        bestScore = entry.value;
        bestLang = entry.key;
      }
    }

    // Require a minimum confidence threshold.
    if (bestLang == null || bestScore < 5) return fallback;

    // Check if the top two scores are too close (ambiguous).
    final sortedScores = scores.values.toList()..sort((a, b) => b.compareTo(a));
    if (sortedScores.length >= 2 &&
        sortedScores[0] > 0 &&
        sortedScores[1] / sortedScores[0] > 0.8) {
      // Ambiguous — fall back.
      return fallback;
    }

    return _localeMap[bestLang] ?? fallback;
  }
}

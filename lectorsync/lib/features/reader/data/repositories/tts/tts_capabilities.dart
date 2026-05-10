class TtsCapabilities {
  const TtsCapabilities({
    required this.supportsWordBoundary,
    required this.supportsVoiceSelection,
    required this.supportsEngineQuery,
    required this.rateRange,
    required this.needsSpeakProbe,
    required this.needsVoicesRetry,
    required this.maxUtteranceChars,
  });

  static const mobile = TtsCapabilities(
    supportsWordBoundary: true,
    supportsVoiceSelection: true,
    supportsEngineQuery: true,
    rateRange: (0.0, 1.0),
    needsSpeakProbe: true,
    needsVoicesRetry: false,
    maxUtteranceChars: 4000,
  );

  static const web = TtsCapabilities(
    supportsWordBoundary: false,
    supportsVoiceSelection: true,
    supportsEngineQuery: false,
    rateRange: (0.0, 1.0),
    needsSpeakProbe: false,
    needsVoicesRetry: true,
    maxUtteranceChars: 180,
  );

  final bool supportsWordBoundary;
  final bool supportsVoiceSelection;
  final bool supportsEngineQuery;
  final (double, double) rateRange;
  final bool needsSpeakProbe;
  final bool needsVoicesRetry;

  /// Hard limit on characters per single utterance handed to the underlying
  /// TTS engine. Web Speech (Chrome/Edge/Firefox) silently fires
  /// `SpeechSynthesisErrorEvent("interrupted")` once an utterance exceeds an
  /// empirical threshold around ~200 chars, so we cap below it. Mobile
  /// engines (Android/iOS) tolerate large utterances comfortably.
  final int maxUtteranceChars;

  TtsCapabilities copyWith({bool? supportsWordBoundary, int? maxUtteranceChars}) =>
      TtsCapabilities(
        supportsWordBoundary:
            supportsWordBoundary ?? this.supportsWordBoundary,
        supportsVoiceSelection: supportsVoiceSelection,
        supportsEngineQuery: supportsEngineQuery,
        rateRange: rateRange,
        needsSpeakProbe: needsSpeakProbe,
        needsVoicesRetry: needsVoicesRetry,
        maxUtteranceChars: maxUtteranceChars ?? this.maxUtteranceChars,
      );
}

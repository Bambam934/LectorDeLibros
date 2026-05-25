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

  static const desktop = TtsCapabilities(
    supportsWordBoundary: false, // SAPI5/AVSpeech fire sporadic, unreliable progress events
    supportsVoiceSelection: true,
    supportsEngineQuery: false,
    rateRange: (0.0, 1.0),
    needsSpeakProbe: false,
    needsVoicesRetry: false,
    // Lowered from 4000 to 800. A 4000-char utterance on Windows SAPI5
    // takes ~80s to speak, and during that whole window the estimated
    // tracker runs on the uncalibrated default (500 ms/word) which is
    // ~25% slower than the real voice — so the highlight falls visibly
    // behind the audio for the entire first segment. By capping at 800
    // chars we get the first calibration sample after ~12-15s instead
    // of after 80s, so segments 2+ already use the measured msPerChar
    // and the highlight stays glued to the voice from there on.
    maxUtteranceChars: 800,
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

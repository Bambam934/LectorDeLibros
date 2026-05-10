export interface WordTimestamp {
  word_index: number;
  timestamp_ms: number;
}

export interface TtsResult {
  audioBuffer: Buffer;
  durationMs: number;
  wordTimestamps: WordTimestamp[];
}

export interface TtsProvider {
  readonly name: string;
  generate(text: string, voiceId: string): Promise<TtsResult>;
}

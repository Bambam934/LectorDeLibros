import type { TtsProvider, TtsResult, WordTimestamp } from './tts-provider.js';

const MS_PER_WORD = 400;

export class MockTtsProvider implements TtsProvider {
  readonly name = 'mock';

  async generate(text: string, _voiceId: string): Promise<TtsResult> {
    const words = text.split(/\s+/).filter(Boolean);
    const wordTimestamps: WordTimestamp[] = words.map((_, i) => ({
      word_index: i,
      timestamp_ms: i * MS_PER_WORD,
    }));

    const durationMs = words.length * MS_PER_WORD;
    const audioBuffer = Buffer.alloc(0);

    return { audioBuffer, durationMs, wordTimestamps };
  }
}

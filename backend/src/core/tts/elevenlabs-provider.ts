import { env } from '../env.js';
import type { TtsProvider, TtsResult, WordTimestamp } from './tts-provider.js';

interface ElevenLabsAlignment {
  alignedText: string;
  alignment: {
    chars: string[];
    charStartTimesMs: number[];
    charDurationsMs: number[];
  };
}

export class ElevenLabsTtsProvider implements TtsProvider {
  readonly name = 'elevenlabs';

  async generate(text: string, voiceId: string): Promise<TtsResult> {
    const url = `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}/with-timestamps`;

    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'xi-api-key': env.ELEVENLABS_API_KEY!,
      },
      body: JSON.stringify({
        text,
        model_id: 'eleven_multilingual_v2',
      }),
    });

    if (!response.ok) {
      throw new Error(
        `ElevenLabs API error: ${response.status} ${await response.text()}`
      );
    }

    const json = (await response.json()) as {
      audio_base64: string;
      alignment: ElevenLabsAlignment['alignment'];
      aligned_text: string;
    };

    const audioBuffer = Buffer.from(json.audio_base64, 'base64');

    const wordTimestamps = this.convertAlignmentToWords(
      json.alignment,
      json.aligned_text
    );

    const lastTimestamp =
      wordTimestamps.length > 0
        ? wordTimestamps[wordTimestamps.length - 1]!.timestamp_ms
        : 0;
    const durationMs =
      lastTimestamp +
      (json.alignment.charDurationsMs.length > 0
        ? json.alignment.charDurationsMs[json.alignment.charDurationsMs.length - 1]!
        : 0);

    return { audioBuffer, durationMs, wordTimestamps };
  }

  private convertAlignmentToWords(
    alignment: ElevenLabsAlignment['alignment'],
    _alignedText: string
  ): WordTimestamp[] {
    const { chars, charStartTimesMs } = alignment;
    const result: WordTimestamp[] = [];
    let wordIndex = 0;
    let currentWordStart: number | null = null;

    for (let i = 0; i < chars.length; i++) {
      const ch = chars[i]!;
      const startTime = charStartTimesMs[i]!;

      if (ch === ' ') {
        if (currentWordStart !== null) {
          result.push({ word_index: wordIndex++, timestamp_ms: currentWordStart });
          currentWordStart = null;
        }
      } else {
        if (currentWordStart === null) {
          currentWordStart = startTime;
        }
      }
    }

    if (currentWordStart !== null) {
      result.push({ word_index: wordIndex++, timestamp_ms: currentWordStart });
    }

    return result;
  }
}

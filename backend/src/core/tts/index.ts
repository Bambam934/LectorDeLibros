import { env } from '../env.js';
import { ElevenLabsTtsProvider } from './elevenlabs-provider.js';
import { MockTtsProvider } from './mock-provider.js';
import type { TtsProvider } from './tts-provider.js';

export function createTtsProvider(): TtsProvider {
  switch (env.TTS_PROVIDER) {
    case 'elevenlabs':
      if (!env.ELEVENLABS_API_KEY) {
        throw new Error('ELEVENLABS_API_KEY is required when TTS_PROVIDER=elevenlabs');
      }
      return new ElevenLabsTtsProvider();
    case 'mock':
    default:
      return new MockTtsProvider();
  }
}

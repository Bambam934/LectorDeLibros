import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { MockTtsProvider } from './mock-provider.js';

describe('MockTtsProvider', () => {
  const provider = new MockTtsProvider();

  it('has name "mock"', () => {
    assert.equal(provider.name, 'mock');
  });

  it('returns empty audioBuffer', async () => {
    const result = await provider.generate('Hola mundo', 'any-voice');
    assert.equal(result.audioBuffer.length, 0);
  });

  it('calculates durationMs at 400ms per word', async () => {
    const result = await provider.generate('uno dos tres', 'any-voice');
    assert.equal(result.durationMs, 3 * 400);
  });

  it('generates word_timestamps with correct indices and spacing', async () => {
    const result = await provider.generate('uno dos tres', 'any-voice');
    assert.equal(result.wordTimestamps.length, 3);
    assert.equal(result.wordTimestamps[0]?.word_index, 0);
    assert.equal(result.wordTimestamps[0]?.timestamp_ms, 0);
    assert.equal(result.wordTimestamps[1]?.word_index, 1);
    assert.equal(result.wordTimestamps[1]?.timestamp_ms, 400);
    assert.equal(result.wordTimestamps[2]?.word_index, 2);
    assert.equal(result.wordTimestamps[2]?.timestamp_ms, 800);
  });

  it('handles empty text', async () => {
    const result = await provider.generate('', 'any-voice');
    assert.equal(result.durationMs, 0);
    assert.equal(result.wordTimestamps.length, 0);
  });
});

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { ElevenLabsTtsProvider } from './elevenlabs-provider.js';

describe('ElevenLabsTtsProvider.convertAlignmentToWords (unit)', () => {
  const provider = new ElevenLabsTtsProvider();

  it('has name "elevenlabs"', () => {
    assert.equal(provider.name, 'elevenlabs');
  });

  it('convertAlignmentToWords is private but can be tested via generate (requires API key)', () => {
    assert.equal(typeof provider.generate, 'function');
  });
});

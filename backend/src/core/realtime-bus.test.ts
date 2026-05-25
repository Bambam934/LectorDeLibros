import assert from 'node:assert/strict';
import { beforeEach, describe, it } from 'node:test';

import { RealtimeBus, type RealtimeEvent } from './realtime-bus.js';

describe('RealtimeBus', () => {
  let bus: RealtimeBus;

  beforeEach(() => {
    bus = new RealtimeBus();
  });

  it('delivers events only to subscribers of the same userId', () => {
    const receivedA: RealtimeEvent[] = [];
    const receivedB: RealtimeEvent[] = [];
    bus.subscribe('user-A', (e) => receivedA.push(e));
    bus.subscribe('user-B', (e) => receivedB.push(e));

    bus.publish('user-A', {
      type: 'progress.updated',
      clientId: 'device-1',
      data: { foo: 1 }
    });

    assert.equal(receivedA.length, 1);
    assert.equal(receivedB.length, 0);
    assert.equal(receivedA[0]!.type, 'progress.updated');
    assert.equal(receivedA[0]!.clientId, 'device-1');
    // ts is enriched by publish().
    assert.match(receivedA[0]!.ts, /^\d{4}-\d{2}-\d{2}T/);
  });

  it('fans out a single publish to every listener of the same user', () => {
    const counts = [0, 0, 0];
    bus.subscribe('u', () => counts[0]!++);
    bus.subscribe('u', () => counts[1]!++);
    bus.subscribe('u', () => counts[2]!++);

    const delivered = bus.publish('u', {
      type: 'bookmark.added',
      clientId: 'device-x',
      data: {}
    });

    assert.equal(delivered, 3);
    assert.deepEqual(counts, [1, 1, 1]);
  });

  it('unsubscribe stops delivery without affecting other listeners', () => {
    const received: number[] = [];
    const unsubA = bus.subscribe('u', () => received.push(1));
    bus.subscribe('u', () => received.push(2));

    unsubA();
    bus.publish('u', { type: 'progress.updated', data: {} });

    assert.deepEqual(received, [2]);
  });

  it('cleans up empty Sets so listenerCount returns 0 after last unsubscribe', () => {
    const unsub = bus.subscribe('u', () => {});
    assert.equal(bus.listenerCount('u'), 1);
    unsub();
    assert.equal(bus.listenerCount('u'), 0);
  });

  it('a throwing listener does not break delivery to subsequent listeners', () => {
    // Silence stderr during this test only.
    const originalError = console.error;
    console.error = () => {};
    try {
      const calls: string[] = [];
      bus.subscribe('u', () => {
        throw new Error('boom');
      });
      bus.subscribe('u', () => calls.push('second'));

      const delivered = bus.publish('u', {
        type: 'progress.updated',
        data: {}
      });

      // 'second' still got the event even though the first listener threw.
      assert.deepEqual(calls, ['second']);
      // Delivery count reflects only the successful invocations.
      assert.equal(delivered, 1);
    } finally {
      console.error = originalError;
    }
  });

  it('publish on a userId with no listeners is a no-op (no throw)', () => {
    const delivered = bus.publish('ghost', {
      type: 'progress.updated',
      data: {}
    });
    assert.equal(delivered, 0);
  });

  it('totalListenerCount aggregates across users', () => {
    bus.subscribe('u1', () => {});
    bus.subscribe('u1', () => {});
    bus.subscribe('u2', () => {});
    assert.equal(bus.totalListenerCount(), 3);
  });

  it('reset() removes every subscription', () => {
    bus.subscribe('u1', () => {});
    bus.subscribe('u2', () => {});
    bus.reset();
    assert.equal(bus.totalListenerCount(), 0);
  });

  it('enriches every event with a server-side ISO timestamp', () => {
    const captured: RealtimeEvent[] = [];
    bus.subscribe('u', (e) => captured.push(e));

    const before = Date.now();
    bus.publish('u', { type: 'progress.updated', data: {} });
    const after = Date.now();

    assert.equal(captured.length, 1);
    const ts = new Date(captured[0]!.ts).getTime();
    assert.ok(ts >= before && ts <= after, 'ts is within publish window');
  });
});

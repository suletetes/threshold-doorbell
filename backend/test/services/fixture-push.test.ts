// HIGH-21 regression: the push fixture retains nothing in normal operation and
// bounds its retained history even when a test opts in.

import { describe, it, expect } from 'vitest';
import { FixturePush } from '../../src/services/fixtures/fixture-push.js';
import type { PushMessage } from '../../src/services/push.js';

function message(i: number): PushMessage {
  return {
    residentSub: `resident-${i}`,
    type: 'person_detected',
    timestamp: new Date().toISOString(),
    deviceId: `device-${i}`,
    thumbnailUrl: null,
  };
}

describe('FixturePush (HIGH-21, FR-8.3)', () => {
  it('retains no messages in normal operation (default, as wired in the container)', async () => {
    const push = new FixturePush();
    for (let i = 0; i < 50; i += 1) {
      const res = await push.send(message(i));
      expect(res.delivered).toBe(true);
    }
    expect(push.sent).toEqual([]);
  });

  it('bounds the retained history even in retention mode', async () => {
    const push = new FixturePush(true, 10);
    for (let i = 0; i < 100; i += 1) {
      await push.send(message(i));
    }
    expect(push.sent).toHaveLength(10);
    // Keeps the most recent sends.
    expect(push.sent[9]!.residentSub).toBe('resident-99');
  });
});

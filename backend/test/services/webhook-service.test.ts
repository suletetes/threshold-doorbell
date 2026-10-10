import { describe, it, expect } from 'vitest';
import { parseWebhook } from '../../src/services/webhook-service.js';
import { AppError } from '../../src/domain/errors.js';

describe('parseWebhook', () => {
  it('normalizes a valid person_detected payload', () => {
    const event = parseWebhook({
      request_id: 'r1',
      event_type: 'person_detected',
      device_id: 'd1',
      timestamp: '2026-01-01T00:00:00.000Z',
      confidence: 0.9,
      bounding_box: { x: 0, y: 0, width: 1, height: 1 },
      thumbnail_url: 'https://example/t.jpg',
    });
    expect(event.requestId).toBe('r1');
    expect(event.type).toBe('person_detected');
    expect(event.boundingBox).toEqual({ x: 0, y: 0, width: 1, height: 1 });
    expect(event.eventId).toBeTruthy();
  });

  it('defaults optional fields to null and generates a timestamp', () => {
    const event = parseWebhook({
      request_id: 'r1',
      event_type: 'motion_detected',
      device_id: 'd1',
    });
    expect(event.confidence).toBeNull();
    expect(event.boundingBox).toBeNull();
    expect(event.thumbnailUrl).toBeNull();
    expect(event.timestamp).toBeTruthy();
  });

  it('rejects malformed payloads', () => {
    expect(() => parseWebhook(null)).toThrow(AppError);
    expect(() => parseWebhook({ event_type: 'person_detected', device_id: 'd' })).toThrow();
    expect(() => parseWebhook({ request_id: 'r', device_id: 'd' })).toThrow();
    expect(() =>
      parseWebhook({ request_id: 'r', event_type: 'nope', device_id: 'd' }),
    ).toThrow();
    expect(() => parseWebhook({ request_id: 'r', event_type: 'motion_detected' })).toThrow();
  });

  it('rejects a confidence outside [0,1] or non-finite (LOW-32)', () => {
    const base = { request_id: 'r1', event_type: 'motion_detected', device_id: 'd1' };
    expect(() => parseWebhook({ ...base, confidence: 1.5 })).toThrow(AppError);
    expect(() => parseWebhook({ ...base, confidence: -0.1 })).toThrow(AppError);
    expect(() => parseWebhook({ ...base, confidence: Number.POSITIVE_INFINITY })).toThrow(AppError);
    // A valid in-range confidence still parses.
    expect(parseWebhook({ ...base, confidence: 0.5 }).confidence).toBe(0.5);
  });

  it('ignores a malformed bounding_box (sets null, not a crash)', () => {
    const event = parseWebhook({
      request_id: 'r1',
      event_type: 'motion_detected',
      device_id: 'd1',
      bounding_box: { x: 'bad' },
    });
    expect(event.boundingBox).toBeNull();
  });
});

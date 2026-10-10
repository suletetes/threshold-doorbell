// Fixture Ring adapter (design.md §11 "local"). Returns golden JSON:API-shaped
// payloads through the same schema layer the real adapter uses, so contract
// validation (FR-17) is exercised identically in tests and in local/demo.

import { createHmac } from 'node:crypto';
import { errors } from '../../domain/errors.js';
import type { Device } from '../../domain/types.js';
import type { RingAuthResult, RingPort } from '../ring.js';
import { parseDevicesDocument, parseTokenResponse } from '../ring-schema.js';

// A fixed secret used ONLY to mint opaque fixture identities. It is not a real
// credential; it exists so the fixture's resident identity is a one-way,
// account-bound value rather than the raw authorization code. The real adapter
// takes residentSub from the Ring identity/userinfo response instead.
const FIXTURE_IDENTITY_SECRET = 'threshold-fixture-identity';

/**
 * Mint an opaque, account-bound resident identity from a stable account seed.
 * The result is a one-way function of the seed, so a crafted authorization code
 * cannot be shaped into a chosen existing resident's sub (CRIT-03, LOW-41).
 */
export function fixtureResidentSub(accountSeed: string): string {
  const digest = createHmac('sha256', FIXTURE_IDENTITY_SECRET)
    .update(accountSeed)
    .digest('base64url')
    .slice(0, 24);
  return `resident-${digest}`;
}

// A golden, well-formed devices document (JSON:API).
export const GOLDEN_DEVICES_DOC = {
  data: [
    {
      id: 'ring-doorbell-001',
      type: 'device',
      attributes: {
        name: 'Front Door',
        capabilities: ['video', 'two_way_talk', 'motion_detection'],
        privacyZones: [],
      },
    },
    {
      id: 'ring-doorbell-002',
      type: 'device',
      attributes: {
        name: 'Back Gate',
        capabilities: ['video', 'motion_detection'],
        privacyZones: [{ x: 0.1, y: 0.1, width: 0.2, height: 0.2 }],
      },
    },
  ],
};

export class FixtureRing implements RingPort {
  private devicesDoc: unknown = GOLDEN_DEVICES_DOC;
  private exchangeShouldFail = false;
  private refreshShouldFail = false;
  private unauthorizedUntilRefresh = false;
  private refreshCount = 0;
  private lastAccessToken: string | null = null;
  private transientFailures = 0;
  private transientKind: 'rate_limited' | 'ring_unavailable' = 'ring_unavailable';
  private listDevicesCalls = 0;

  /** Return zero devices to exercise the empty-state path (FR-2.2). */
  setEmptyDevices(): void {
    this.devicesDoc = { data: [] };
  }

  /** Return a malformed devices document to exercise FR-17 / AT-23. */
  setMalformedDevices(): void {
    this.devicesDoc = { data: [{ id: 42, attributes: { name: 123 } }] };
  }

  /** Restore the golden devices document. */
  setGoldenDevices(): void {
    this.devicesDoc = GOLDEN_DEVICES_DOC;
  }

  /** Cause exchangeCode to fail (bad code). */
  failExchange(): void {
    this.exchangeShouldFail = true;
  }

  /** Cause refresh to fail (invalid/expired refresh token) - FR-1.4/1.5. */
  failRefresh(): void {
    this.refreshShouldFail = true;
  }

  /** Restore normal refresh behavior. */
  allowRefresh(): void {
    this.refreshShouldFail = false;
  }

  /**
   * Make listDevices reject with a 401 until a refresh has happened, then
   * succeed with the refreshed token. Exercises FR-1.4 refresh-once-and-retry.
   */
  requireRefreshOn401(): void {
    this.unauthorizedUntilRefresh = true;
  }

  /** Number of refresh() calls (assert "exactly one refresh", AT-1). */
  get refreshInvocations(): number {
    return this.refreshCount;
  }

  /** Number of listDevices() attempts (assert retry counts). */
  get listDevicesInvocations(): number {
    return this.listDevicesCalls;
  }

  /**
   * Make the next `count` listDevices calls fail transiently with `kind`
   * (429 rate_limited or 5xx ring_unavailable), then succeed. Exercises the
   * RingGateway retry/backoff policy (FR-2.3, NFR-7).
   */
  failTransiently(count: number, kind: 'rate_limited' | 'ring_unavailable'): void {
    this.transientFailures = count;
    this.transientKind = kind;
  }

  async exchangeCode(
    code: string,
    _codeVerifier: string,
    _redirectUri: string,
  ): Promise<RingAuthResult> {
    if (this.exchangeShouldFail || code === '') {
      // Route the fixture through the same schema parser as the real adapter.
      const parsed = parseTokenResponse({});
      return { ...parsed, residentSub: fixtureResidentSub('') };
    }
    // The authorization code carries the account seed. The identity is derived
    // from that seed via a one-way function and returned explicitly, modelling
    // the userinfo lookup the real adapter performs. The token strings are
    // opaque to the route (CRIT-03, LOW-41).
    const parsed = parseTokenResponse({
      access_token: `access-${randomOpaque()}`,
      refresh_token: encodeRefreshToken(code),
      expires_in: 3600,
    });
    return { ...parsed, residentSub: fixtureResidentSub(code) };
  }

  async refresh(refreshToken: string): Promise<RingAuthResult> {
    if (this.refreshShouldFail || refreshToken === '') {
      throw errors.refreshFailed();
    }
    // Recover the account seed. Tokens minted by exchangeCode/refresh carry an
    // encoded seed; a plain token (used by service-level unit tests) is treated
    // as the seed itself so the identity is still stable across refresh.
    const seed = decodeRefreshToken(refreshToken) ?? refreshToken;
    this.refreshCount += 1;
    // Rotate the opaque access/refresh strings but keep the SAME account seed so
    // the derived identity is stable across refresh (a refresh never re-derives
    // identity from the token text).
    const parsed = parseTokenResponse({
      access_token: `access-${randomOpaque()}`,
      refresh_token: encodeRefreshToken(seed),
      expires_in: 3600,
    });
    return { ...parsed, residentSub: fixtureResidentSub(seed) };
  }

  async listDevices(accessToken: string): Promise<Device[]> {
    this.lastAccessToken = accessToken;
    this.listDevicesCalls += 1;
    // Simulate transient 429/5xx failures that clear after `count` attempts.
    if (this.transientFailures > 0) {
      this.transientFailures -= 1;
      throw this.transientKind === 'rate_limited'
        ? errors.rateLimited()
        : errors.ringUnavailable();
    }
    // Simulate a token that is rejected as 401 until a refresh has happened.
    if (this.unauthorizedUntilRefresh && this.refreshCount === 0) {
      throw errors.unauthorized();
    }
    // Always through the schema layer so malformed fixtures raise
    // ring_contract_invalid exactly as the real adapter would.
    return parseDevicesDocument(this.devicesDoc);
  }
}

/** An opaque random token component so token strings carry no identity. */
function randomOpaque(): string {
  return createHmac('sha256', FIXTURE_IDENTITY_SECRET)
    .update(`${Date.now()}:${Math.random()}`)
    .digest('base64url')
    .slice(0, 16);
}

// The fixture refresh token embeds the account seed so a refresh can keep the
// same identity, but it is opaque to the route: only the fixture decodes it.
const REFRESH_PREFIX = 'refresh.';

function encodeRefreshToken(seed: string): string {
  return `${REFRESH_PREFIX}${Buffer.from(seed, 'utf8').toString('base64url')}`;
}

function decodeRefreshToken(token: string): string | null {
  if (!token.startsWith(REFRESH_PREFIX)) return null;
  try {
    return Buffer.from(token.slice(REFRESH_PREFIX.length), 'base64url').toString('utf8');
  } catch {
    return null;
  }
}

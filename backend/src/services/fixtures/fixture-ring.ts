// Fixture Ring adapter (design.md §11 "local"). Returns golden JSON:API-shaped
// payloads through the same schema layer the real adapter uses, so contract
// validation (FR-17) is exercised identically in tests and in local/demo.

import { errors } from '../../domain/errors.js';
import type { Device } from '../../domain/types.js';
import type { OAuthTokens, RingPort } from '../ring.js';
import { parseDevicesDocument, parseTokenResponse } from '../ring-schema.js';

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

  async exchangeCode(
    code: string,
    _codeVerifier: string,
    _redirectUri: string,
  ): Promise<OAuthTokens> {
    if (this.exchangeShouldFail || code === '') {
      // Route the fixture through the same schema parser as the real adapter.
      return parseTokenResponse({});
    }
    return parseTokenResponse({
      access_token: `access-${code}`,
      refresh_token: `refresh-${code}`,
      expires_in: 3600,
    });
  }

  async refresh(refreshToken: string): Promise<OAuthTokens> {
    if (this.refreshShouldFail || refreshToken === '') {
      throw errors.refreshFailed();
    }
    this.refreshCount += 1;
    return parseTokenResponse({
      access_token: `access-refreshed-${refreshToken}`,
      refresh_token: `refresh-rotated-${refreshToken}`,
      expires_in: 3600,
    });
  }

  async listDevices(accessToken: string): Promise<Device[]> {
    this.lastAccessToken = accessToken;
    // Simulate a token that is rejected as 401 until refreshed.
    if (this.unauthorizedUntilRefresh && !accessToken.includes('refreshed')) {
      throw errors.unauthorized();
    }
    // Always through the schema layer so malformed fixtures raise
    // ring_contract_invalid exactly as the real adapter would.
    return parseDevicesDocument(this.devicesDoc);
  }
}

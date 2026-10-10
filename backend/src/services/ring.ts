// Ring integration port (Task 3/6, FR-1, FR-2, FR-17). The single adapter layer
// that isolates all Ring request/response parsing behind schema validation
// (FR-17.1). Real adapter performs HTTPS calls; fixture returns golden payloads.

import type { Device } from '../domain/types.js';

export interface OAuthTokens {
  accessToken: string;
  refreshToken: string;
  expiresAt: string; // ISO-8601
}

/**
 * The result of an OAuth exchange or refresh. It carries the opaque,
 * account-bound resident identity taken from the provider's identity/userinfo
 * response, NOT parsed from the access-token string (CRIT-03, LOW-41). The route
 * scopes data by `residentSub` and never derives identity from client input or
 * from the token text.
 */
export interface RingAuthResult extends OAuthTokens {
  residentSub: string;
}

export interface RingPort {
  /** Exchange an authorization code (PKCE) for tokens + identity. Server-side only. */
  exchangeCode(code: string, codeVerifier: string, redirectUri: string): Promise<RingAuthResult>;
  /** Refresh tokens using a refresh token (FR-1.4). Returns the stable identity. */
  refresh(refreshToken: string): Promise<RingAuthResult>;
  /**
   * List authorized devices. Implementations MUST validate the Ring response
   * against the device schema and throw ring_contract_invalid on drift (FR-17).
   */
  listDevices(accessToken: string): Promise<Device[]>;
}

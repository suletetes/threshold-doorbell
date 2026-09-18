// Single Ring adapter schema layer (FR-17.1/17.2). Every Ring response is parsed
// here; drift produces a typed error (ring_contract_invalid) rather than a crash.
// Ring device payloads are JSON:API-shaped (design.md §4).

import { errors } from '../domain/errors.js';
import type { BoundingBox, Device } from '../domain/types.js';

// Shape we expect from Ring for the devices list (JSON:API).
interface RawDeviceResource {
  id: unknown;
  type?: unknown;
  attributes?: {
    name?: unknown;
    capabilities?: unknown;
    privacyZones?: unknown;
  };
}

interface RawDevicesDocument {
  data?: unknown;
}

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

function isBoundingBox(v: unknown): v is BoundingBox {
  if (!isObject(v)) return false;
  return (
    typeof v.x === 'number' &&
    typeof v.y === 'number' &&
    typeof v.width === 'number' &&
    typeof v.height === 'number'
  );
}

/**
 * Validate and normalize a Ring devices JSON:API document into Device[].
 * Throws ring_contract_invalid (FR-17.2) on any structural drift so the caller
 * can degrade the feature while keeping the process alive.
 */
export function parseDevicesDocument(doc: unknown): Device[] {
  if (!isObject(doc)) throw errors.ringContractInvalid();
  const { data } = doc as RawDevicesDocument;
  if (!Array.isArray(data)) throw errors.ringContractInvalid();

  const now = new Date().toISOString();
  return data.map((raw): Device => {
    if (!isObject(raw)) throw errors.ringContractInvalid();
    const resource = raw as unknown as RawDeviceResource;
    if (typeof resource.id !== 'string' || resource.id === '') {
      throw errors.ringContractInvalid();
    }
    const attrs = resource.attributes;
    if (!isObject(attrs)) throw errors.ringContractInvalid();
    if (typeof attrs.name !== 'string') throw errors.ringContractInvalid();

    // capabilities defaults to [] when absent, but must be string[] when present.
    let capabilities: string[] = [];
    if (attrs.capabilities !== undefined) {
      if (
        !Array.isArray(attrs.capabilities) ||
        !attrs.capabilities.every((c) => typeof c === 'string')
      ) {
        throw errors.ringContractInvalid();
      }
      capabilities = attrs.capabilities as string[];
    }

    // privacyZones defaults to [] when absent, but must be BoundingBox[] when present.
    let privacyZones: BoundingBox[] = [];
    if (attrs.privacyZones !== undefined) {
      if (!Array.isArray(attrs.privacyZones) || !attrs.privacyZones.every(isBoundingBox)) {
        throw errors.ringContractInvalid();
      }
      privacyZones = attrs.privacyZones as BoundingBox[];
    }

    return {
      id: resource.id,
      name: attrs.name,
      capabilities,
      privacyZones,
      cachedAt: now,
    };
  });
}

// Token response shape from Ring's OAuth token endpoint.
interface RawTokenResponse {
  access_token?: unknown;
  refresh_token?: unknown;
  expires_in?: unknown;
}

export interface ParsedTokens {
  accessToken: string;
  refreshToken: string;
  expiresAt: string;
}

/** Validate a Ring OAuth token response; throws code_exchange_failed on drift. */
export function parseTokenResponse(doc: unknown): ParsedTokens {
  if (!isObject(doc)) throw errors.codeExchangeFailed();
  const raw = doc as RawTokenResponse;
  if (typeof raw.access_token !== 'string' || raw.access_token === '') {
    throw errors.codeExchangeFailed();
  }
  if (typeof raw.refresh_token !== 'string' || raw.refresh_token === '') {
    throw errors.codeExchangeFailed();
  }
  const expiresIn = typeof raw.expires_in === 'number' ? raw.expires_in : 3600;
  const expiresAt = new Date(Date.now() + expiresIn * 1000).toISOString();
  return {
    accessToken: raw.access_token,
    refreshToken: raw.refresh_token,
    expiresAt,
  };
}

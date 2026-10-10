// In-memory device -> account mapping (design.md §11 "local", CRIT-04).
// Deterministic, no AWS. Used in local/demo environments and in tests. The real
// adapter persists this mapping in DynamoDB keyed by deviceId.

import type { DeviceAccountStorePort } from '../stores.js';

export class MemoryDeviceAccountStore implements DeviceAccountStorePort {
  private readonly byDevice = new Map<string, string>();

  async map(deviceId: string, residentSub: string): Promise<void> {
    if (deviceId === '' || residentSub === '') return;
    this.byDevice.set(deviceId, residentSub);
  }

  async mapAll(deviceIds: string[], residentSub: string): Promise<void> {
    for (const deviceId of deviceIds) {
      await this.map(deviceId, residentSub);
    }
  }

  async resolve(deviceId: string): Promise<string | null> {
    return this.byDevice.get(deviceId) ?? null;
  }

  async deleteAllForResident(residentSub: string): Promise<number> {
    let removed = 0;
    for (const [deviceId, owner] of this.byDevice) {
      if (owner === residentSub) {
        this.byDevice.delete(deviceId);
        removed += 1;
      }
    }
    return removed;
  }

  /** Test helper: number of device mappings currently held. */
  size(): number {
    return this.byDevice.size;
  }
}

// WS /demo/hub — the two-phone demo relay (hackathon demo only).
//
// Why this exists: the production /signaling + /asr/stream paths relay to Ring
// and Amazon Transcribe, which are fixtures in demo mode and do NOT carry data
// from one phone to the other. For the two-phone WiFi demo we need a dead-simple
// relay: Phone A (visitor page) and Phone B (Threshold app) each open a
// WebSocket to /demo/hub for the SAME deviceId ("room"). Every message from one
// role is forwarded verbatim to the other role in that room.
//
// Roles: ?role=visitor (Phone A) and ?role=resident (Phone B).
// Room:  ?deviceId=<id>  (both phones must use the same id).
//
// Message types (JSON text frames, forwarded as-is to the peer):
//   {type:'ring'}                         visitor -> resident  (doorbell pressed)
//   {type:'answer'}                       resident -> visitor  (resident answered)
//   {type:'caption', text, isFinal}       visitor -> resident  (live speech caption)
//   {type:'reply', text}                  resident -> visitor  (spoken reply)
//   {type:'hangup'}                        either -> other
//
// The hub also sends presence frames so each side knows when the other is ready:
//   {type:'peer-joined', role}            when the other role connects
//   {type:'peer-left', role}              when the other role disconnects
//   {type:'joined', role, deviceId}       ack to the socket that just joined
//
// No Ring, no Transcribe, no session-limit. Auth: demo env only, so the demo
// token (or no token) is accepted; this route is not registered outside demo.

import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { WebSocket } from '@fastify/websocket';
import { getLogger } from '../observability/logger.js';

type Role = 'visitor' | 'resident';

interface Member {
  socket: WebSocket;
  role: Role;
}

/** One room per deviceId, holding at most one visitor and one resident. */
interface Room {
  visitor?: Member;
  resident?: Member;
}

/** In-memory room registry. Exported for the /demo/status page. */
export const demoRooms = new Map<string, Room>();

function send(socket: WebSocket, payload: unknown): void {
  try {
    socket.send(JSON.stringify(payload));
  } catch {
    // socket may have closed; ignore
  }
}

function peerOf(room: Room, role: Role): Member | undefined {
  return role === 'visitor' ? room.resident : room.visitor;
}

export async function registerDemoHubRoutes(app: FastifyInstance): Promise<void> {
  const log = getLogger();

  app.get('/demo/hub', { websocket: true }, (socket: WebSocket, request: FastifyRequest) => {
    const query = request.query as Record<string, string | undefined>;
    const deviceId = (query.deviceId ?? '').trim() || 'mock-doorbell-001';
    const roleRaw = (query.role ?? '').trim();
    const role: Role = roleRaw === 'visitor' ? 'visitor' : 'resident';

    let room = demoRooms.get(deviceId);
    if (!room) {
      room = {};
      demoRooms.set(deviceId, room);
    }

    // If a socket already holds this role in the room, close the old one so the
    // newest connection wins (a phone reconnecting after a reload).
    const existing = room[role];
    if (existing) {
      try {
        existing.socket.close(1000, 'replaced by new connection');
      } catch {
        // ignore
      }
    }

    const member: Member = { socket, role };
    room[role] = member;
    log.info({ deviceId, role }, 'demo hub: member joined');

    // Ack the joiner, and tell each side whether its peer is already present.
    send(socket, { type: 'joined', role, deviceId });
    const peer = peerOf(room, role);
    if (peer) {
      // Tell the joiner the peer is already here, and tell the peer we arrived.
      send(socket, { type: 'peer-joined', role: peer.role });
      send(peer.socket, { type: 'peer-joined', role });
    }

    socket.on('message', (raw: Buffer | ArrayBuffer | Buffer[]) => {
      const text = Buffer.isBuffer(raw)
        ? raw.toString('utf8')
        : Array.isArray(raw)
          ? Buffer.concat(raw).toString('utf8')
          : Buffer.from(raw).toString('utf8');

      // Validate it is JSON with a type; forward verbatim to the peer.
      let parsed: Record<string, unknown> | null = null;
      try {
        const obj = JSON.parse(text) as Record<string, unknown>;
        if (obj && typeof obj.type === 'string') parsed = obj;
      } catch {
        parsed = null;
      }
      if (!parsed) return;

      const current = demoRooms.get(deviceId);
      if (!current) return;
      const target = peerOf(current, role);
      if (target) {
        send(target.socket, parsed);
        log.info({ deviceId, from: role, type: parsed.type }, 'demo hub: relayed');
      } else {
        // No peer yet; let the sender know so the UI can show "waiting".
        send(socket, { type: 'no-peer', forType: parsed.type });
      }
    });

    socket.on('close', () => {
      const current = demoRooms.get(deviceId);
      if (!current) return;
      // Only clear if THIS socket still occupies the role (not replaced).
      if (current[role]?.socket === socket) {
        current[role] = undefined;
        const other = peerOf(current, role);
        if (other) send(other.socket, { type: 'peer-left', role });
        log.info({ deviceId, role }, 'demo hub: member left');
      }
      // Drop empty rooms.
      if (!current.visitor && !current.resident) {
        demoRooms.delete(deviceId);
      }
    });
  });
}

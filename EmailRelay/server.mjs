// Node 22+. Keep TLS termination, request logging and rate limits under the operator's control.
import { createServer } from 'node:http';
import { pathToFileURL } from 'node:url';

function positive(value, fallback) {
  const number = Number(value ?? fallback);
  if (!Number.isSafeInteger(number) || number < 1) throw new Error('Expected a positive integer setting');
  return number;
}

export function createRelay({ key, fetchUpstream = fetch, globalRPM = 10, perPeerRPM = 3, now = Date.now } = {}) {
  const globalLimit = positive(globalRPM, 10), peerLimit = positive(perPeerRPM, 3);
  // With one sliding window, memory and the number of tracked clients are bounded by globalLimit.
  let recent = [];
  let backoffUntil = 0;
  const server = createServer(async (req, res) => {
    const finish = (status, data, extra = {}) => {
      if (res.destroyed || res.writableEnded) return;
      res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...extra });
      res.end(data);
    };
    if (req.method !== 'POST' || req.url !== '/v1/email-range') return finish(404, '{}');
    if (req.headers['content-type']?.split(';')[0].trim() !== 'application/json') return finish(415, '{}');
    try {
      let size = 0;
      const chunks = [];
      for await (const chunk of req) {
        size += chunk.length;
        if (size > 128) return finish(413, '{}');
        chunks.push(chunk);
      }
      let body;
      try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { return finish(400, '{}'); }
      if (!body || Object.keys(body).length !== 1 || typeof body.prefix !== 'string' || !/^[0-9A-Fa-f]{6}$/.test(body.prefix)) {
        return finish(400, '{}');
      }
      if (!key) return finish(503, '{}');
      const time = now();
      const peer = req.socket.remoteAddress;
      recent = recent.filter(item => item.at > time - 60_000);
      const local = recent.filter(item => item.peer === peer);
      const retryAt = Math.max(backoffUntil, recent.length >= globalLimit ? recent[0].at + 60_000 : 0,
        local.length >= peerLimit ? local[0].at + 60_000 : 0);
      if (retryAt > time) return finish(429, '{}', { 'Retry-After': String(Math.ceil((retryAt - time) / 1000)) });
      recent.push({ at: time, peer });
      const url = 'https://haveibeenpwned.com/api/v3/breachedaccount/range/' + body.prefix.toUpperCase();
      const response = await fetchUpstream(url, {
        method: 'GET', redirect: 'error', cache: 'no-store', signal: AbortSignal.timeout(10_000),
        headers: { 'hibp-api-key': key, 'User-Agent': 'Piproom-EmailRelay', Accept: 'application/json' }
      });
      if (response.status === 429) {
        const seconds = Number(response.headers.get('Retry-After'));
        const wait = Number.isSafeInteger(seconds) && seconds > 0 ? seconds : 60;
        backoffUntil = now() + wait * 1000;
        await response.body?.cancel();
        return finish(429, '{}', { 'Retry-After': String(wait) });
      }
      if (response.status !== 200 || !response.headers.get('content-type')?.toLowerCase().includes('application/json')) {
        await response.body?.cancel();
        return finish([401, 403].includes(response.status) ? 503 : 502, '{}');
      }
      // Forward only this response. No range cache, request history, logs or database.
      return finish(200, Buffer.from(await response.arrayBuffer()));
    } catch {
      return finish(502, '{}');
    }
  });
  server.requestTimeout = 12_000;
  server.headersTimeout = 10_000;
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (!process.env.HIBP_API_KEY) throw new Error('Set HIBP_API_KEY on the server before starting the relay.');
  createRelay({ key: process.env.HIBP_API_KEY, globalRPM: process.env.HIBP_GLOBAL_RPM, perPeerRPM: process.env.HIBP_PEER_RPM })
    .listen(positive(process.env.PORT, 8787), process.env.BIND_ADDRESS ?? '127.0.0.1');
}

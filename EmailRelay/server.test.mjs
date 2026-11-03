import test from 'node:test';
import assert from 'node:assert/strict';
import { createRelay } from './server.mjs';

async function run(t, options) {
  const server = createRelay(options);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const base = 'http://127.0.0.1:' + server.address().port;
  return (body, route = '/v1/email-range') => fetch(base + route, { method: 'POST', headers: {'content-type':'application/json'}, body: JSON.stringify(body) });
}

test('only a six-digit prefix reaches the fixed upstream; no cache or secret in the response', async t => {
  const calls = [];
  const send = await run(t, { key: 'test-secret', fetchUpstream: async (url, options) => {
    calls.push({ url, options }); return Response.json([{ hashSuffix: 'A'.repeat(34), websites: ['Example'] }]);
  }});
  for (const body of [{email:'a@example.com'}, {prefix:'12345'}, {prefix:'ABCDEF',email:'a@example.com'}, {prefix:'A'.repeat(40)}]) {
    assert.equal((await send(body)).status, 400);
  }
  assert.equal((await send({prefix:'ABCDEF'}, '/v1/email-range?email=a')).status, 404);
  assert.equal(calls.length, 0);
  const response = await send({prefix:'a0bcde'});
  assert.equal(response.status, 200); assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.deepEqual(await response.json(), [{hashSuffix:'A'.repeat(34),websites:['Example']}]);
  assert.equal(calls[0].url, 'https://haveibeenpwned.com/api/v3/breachedaccount/range/A0BCDE');
  assert.equal(calls[0].options.headers['hibp-api-key'], 'test-secret');
});

test('upstream failure and limits never become a clean lookup', async t => {
  let at = 0, status = 429, calls = 0;
  const send = await run(t,{key:'test',now:()=>at,globalRPM:2,perPeerRPM:2,fetchUpstream:async()=>{
    calls++; return new Response(null,{status, headers:{'Retry-After':'5'}});
  }});
  assert.equal((await send({prefix:'ABCDEF'})).status,429);
  assert.equal((await send({prefix:'123456'})).headers.get('retry-after'),'5'); assert.equal(calls,1);
  at=6000; status=403;
  assert.equal((await send({prefix:'123456'})).status,503);
  assert.equal((await send({prefix:'123456'})).status,429); assert.equal(calls,2);
  at=67000; status=404;
  assert.equal((await send({prefix:'123456'})).status,502);
});

test('unconfigured relay does not contact HIBP', async t => {
  const send = await run(t, {fetchUpstream:assert.fail});
  assert.equal((await send({prefix:'ABCDEF'})).status,503);
});

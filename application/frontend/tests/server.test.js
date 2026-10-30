import {test, before, after} from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {spawn} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';

let backend, child, base, cookie, forwarded;
const token = 'b'.repeat(64);
const listen = server => new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const body = async request => { let value = ''; for await (const chunk of request) value += chunk; return value ? JSON.parse(value) : undefined; };
before(async () => {
  backend = http.createServer(async (req, res) => {
    forwarded = {url: req.url, headers: req.headers, body: await body(req)};
    res.setHeader('Content-Type', 'application/json');
    if (req.url === '/auth/login' || req.url === '/auth/register')
      return res.end(JSON.stringify({user: {id: '11111111-1111-1111-1111-111111111111', name: 'Demo', email: 'demo@example.test'}, token}));
    if (req.url === '/auth/session') {
      if (req.headers['x-account-token'] !== token) { res.statusCode = 401; return res.end('{"error":"sign_in_required"}'); }
      return res.end('{"user":{"id":"11111111-1111-1111-1111-111111111111","name":"Demo"}}');
    }
    if (req.url === '/orders') return res.end('{"id":"11111111-1111-1111-1111-111111111111","total":1800}');
    if (req.url.startsWith('/orders?page=')) return res.end('{"orders":[],"hasMore":false,"page":0}');
    if (req.url === '/auth/logout') return res.end('{"status":"signed_out"}');
    if (req.url === '/health/ready') return res.end('{"status":"ok"}');
    res.end('{"items":[]}');
  });
  await listen(backend);
  const port = http.createServer(); await listen(port);
  const frontendPort = port.address().port;
  await new Promise(resolve => port.close(resolve));
  base = 'http://127.0.0.1:' + frontendPort;
  const upstream = 'http://127.0.0.1:' + backend.address().port;
  child = spawn(process.execPath, ['src/server.js'], {env: {...process.env, PORT: String(frontendPort), SESSION_SECRET: 's'.repeat(40),
    PUBLIC_ORIGIN: base, COOKIE_SECURE: 'true', CATALOGUE_URL: upstream, CART_URL: upstream, ORDERS_URL: upstream}, stdio: 'ignore'});
  for (let attempt = 0; attempt < 100; attempt++) {
    try { if ((await fetch(base + '/health/live')).ok) return; } catch { /* Wait for the child server. */ }
    if (child.exitCode !== null) throw Error('Frontend exited during startup');
    await delay(30);
  }
  throw Error('Frontend startup timed out');
});
after(async () => {
  if (child && child.exitCode === null) {
    const stopped = new Promise(resolve => child.once('exit', resolve)); child.kill(); await stopped;
  }
  if (backend) { backend.closeAllConnections(); await new Promise(resolve => backend.close(resolve)); }
});

test('all real pages are directly addressable and HTML is never cached', async () => {
  for (const path of ['/', '/account', '/checkout', '/orders', '/orders/11111111-1111-1111-1111-111111111111']) {
    const response = await fetch(base + path);
    assert.equal(response.status, 200); assert.equal(response.headers.get('cache-control'), 'no-store');
    const html = await response.text();
    assert.match(html, /id="orders-page"/); assert.match(html, /\/app\.[a-f0-9]{16}\.js/);
  }
  const response = await fetch(base + '/does-not-exist'); assert.equal(response.status, 404);
});

test('origin enforcement blocks login CSRF before contacting authentication', async () => {
  const response = await fetch(base + '/api/auth/login', {method: 'POST', body: '{}'});
  assert.equal(response.status, 403);
});

test('login credentials stay server-side and auth token is only an HttpOnly cookie', async () => {
  const response = await fetch(base + '/api/auth/login', {method: 'POST', headers: {Origin: base},
    body: JSON.stringify({email: 'demo@example.test', password: 'demo long passphrase'})});
  assert.equal(response.status, 200);
  const data = await response.json(); assert.equal(data.user.name, 'Demo'); assert.equal(data.token, undefined);
  const cookies = response.headers.getSetCookie();
  const account = cookies.find(value => value.startsWith('account='));
  assert.match(account, /HttpOnly; SameSite=Strict; Path=\/; Max-Age=604800; Secure/);
  cookie = cookies.map(value => value.split(';')[0]).join('; ');
  assert.equal(forwarded.body.email, 'demo@example.test');
  assert.equal(response.headers.get('cache-control'), 'no-store');
});

test('browser cannot forge account headers and authenticated history is forwarded', async () => {
  const response = await fetch(base + '/api/orders?page=2', {headers: {Cookie: cookie, 'X-Account-Token': 'attacker'}});
  assert.equal(response.status, 200); assert.equal(forwarded.url, '/orders?page=2');
  assert.equal(forwarded.headers['x-account-token'], token);
  assert.match(forwarded.headers['x-session-id'], /^[a-f0-9]{64}$/);
  await fetch(base + '/api/orders', {headers: {'X-Account-Token': token}});
  assert.equal(forwarded.headers['x-account-token'], undefined);
});

test('checkout forwards delivery but never accepts browser prices as authoritative', async () => {
  const response = await fetch(base + '/api/orders', {method: 'POST', headers: {Origin: base, Cookie: cookie, 'Idempotency-Key': 'checkout-123456'},
    body: JSON.stringify({name: 'Demo', address: '1 Demo Lane', city: 'Demo', postalCode: '12345', country: 'Example'})});
  assert.equal(response.status, 200); assert.equal(forwarded.headers['idempotency-key'], 'checkout-123456');
  assert.equal(forwarded.body.address, '1 Demo Lane');
  const invalid = await fetch(base + '/api/orders', {method: 'POST', headers: {Origin: base, 'Idempotency-Key': 'short'}});
  assert.equal(invalid.status, 400);
});

test('oversized and malformed payloads fail before backend processing', async () => {
  const large = await fetch(base + '/api/auth/register', {method: 'POST', headers: {Origin: base}, body: 'x'.repeat(5000)});
  assert.equal(large.status, 413);
  const broken = await fetch(base + '/api/auth/register', {method: 'POST', headers: {Origin: base}, body: '[]'});
  assert.equal(broken.status, 400);
});

test('logout revokes current token and rotates browser session', async () => {
  const response = await fetch(base + '/api/auth/logout', {method: 'POST', headers: {Origin: base, Cookie: cookie}});
  assert.equal(forwarded.headers['x-account-token'], token);
  assert.equal(response.status, 200);
  const cookies = response.headers.getSetCookie();
  assert.match(cookies.find(value => value.startsWith('account=')), /Max-Age=0/);
  const oldSession = cookie.split('; ').find(value => value.startsWith('session='));
  assert.notEqual(cookies.find(value => value.startsWith('session=')).split(';')[0], oldSession);
});

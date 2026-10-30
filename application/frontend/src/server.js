import {observe, exposition} from './metrics.js';
import http from 'node:http';
import {readFile} from 'node:fs/promises';
import {createHash, randomUUID, randomBytes} from 'node:crypto';
import {session, signedCookie} from './session.js';

const secret = process.env.SESSION_SECRET;
if (!secret || secret.length < 32) throw Error('SESSION_SECRET must be at least 32 characters');
const origin = process.env.PUBLIC_ORIGIN || 'http://localhost:8080';
const secure = process.env.COOKIE_SECURE === 'true';
const urls = {
  catalogue: process.env.CATALOGUE_URL || 'http://localhost:8081',
  cart: process.env.CART_URL || 'http://localhost:8082',
  orders: process.env.ORDERS_URL || 'http://localhost:8083',
};
const publicDir = new URL('../public/', import.meta.url);
const [sourceHtml, appJs, styleCss] = await Promise.all(
  ['index.html', 'app.js', 'style.css'].map(name => readFile(new URL(name, publicDir))),
);
const fingerprint = content => createHash('sha256').update(content).digest('hex').slice(0, 16);
const appPath = `/app.${fingerprint(appJs)}.js`;
const stylePath = `/style.${fingerprint(styleCss)}.css`;
const html = Buffer.from(sourceHtml.toString().replace('/app.js', appPath).replace('/style.css', stylePath));
const assets = new Map([[appPath, appJs], [stylePath, styleCss]]);
const page = path => ['/', '/account', '/checkout', '/orders', '/admin'].includes(path)
  || /^\/orders\/[a-f0-9-]{36}$/.test(path);

function reply(res, status, body) {
  res.writeHead(status, {'Content-Type': 'application/json'});
  res.end(JSON.stringify(body));
}
async function call(url, method = 'GET', headers = {}, body, timeout = 5000) {
  const response = await fetch(url, {method, headers, body, signal: AbortSignal.timeout(timeout)});
  return {status: response.status, body: await response.json()};
}
async function input(req) {
  let raw = '';
  for await (const chunk of req) {
    raw += chunk;
    if (Buffer.byteLength(raw) > 4096) throw Object.assign(Error('body_too_large'), {status: 413});
  }
  if (!raw) return undefined;
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || Array.isArray(parsed) || typeof parsed !== 'object') throw Error();
    return parsed;
  } catch { throw Object.assign(Error('invalid_json'), {status: 400}); }
}
function accountToken(cookie) {
  const raw = (cookie || '').split(';').map(value => value.trim())
    .find(value => value.startsWith('account='))?.slice(8);
  return /^[a-f0-9]{64}$/.test(raw || '') ? raw : null;
}
function accountCookie(token, age = 604800) {
  return `account=${token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${age}${secure ? '; Secure' : ''}`;
}
const server = http.createServer(async (req, res) => {
  const start = Date.now(), rid = randomUUID();
  res.setHeader('X-Request-ID', rid);
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'same-origin');
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self' https://checkout.razorpay.com; style-src 'self'; frame-src https://*.razorpay.com https://*.razorpay.in; connect-src 'self' https://*.razorpay.com https://*.razorpay.in; img-src 'self' data: https://*.razorpay.com; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
  res.once('finish', () => {
    observe(req.method, new URL(req.url, 'http://internal').pathname, res.statusCode, (Date.now() - start) / 1000);
    console.log(JSON.stringify({method: req.method, path: req.url?.split('?')[0], status: res.statusCode,
      duration_ms: Date.now() - start, request_id: rid}));
  });
  try {
    const url = new URL(req.url, 'http://internal'), path = url.pathname;
    if (path === '/health/live') return reply(res, 200, {status: 'ok'});
    if (path === '/health/ready') {
      const results = await Promise.all(Object.values(urls).map(u => call(u + '/health/ready')));
      const ok = results.every(result => result.status === 200);
      return reply(res, ok ? 200 : 503, {status: ok ? 'ok' : 'unavailable'});
    }
    if (path === '/metrics') {
      res.writeHead(200, {'Content-Type': 'text/plain; version=0.0.4'});
      return res.end(exposition());
    }
    if (req.method === 'GET' && (page(path) || assets.has(path))) {
      const htmlPage = page(path), cache = htmlPage ? 'no-store' : 'public, max-age=31536000, immutable';
      res.writeHead(200, {'Content-Type': htmlPage ? 'text/html' : path.endsWith('.js') ? 'text/javascript' : 'text/css',
        'Cache-Control': cache, 'Cloudflare-CDN-Cache-Control': cache});
      return res.end(htmlPage ? html : assets.get(path));
    }
    if (!path.startsWith('/api/')) return reply(res, 404, {error: 'not_found'});
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Cloudflare-CDN-Cache-Control', 'no-store');
    if (!['GET', 'PUT', 'DELETE', 'POST'].includes(req.method)) return reply(res, 405, {error: 'method_not_allowed'});
    if (path === '/api/payments/webhook' && req.method === 'POST') {
      const chunks = []; let size = 0;
      for await (const chunk of req) {
        size += chunk.length;
        if (size > 262144) return reply(res, 413, {error: 'body_too_large'});
        chunks.push(chunk);
      }
      const webhookHeaders = {'Content-Type': 'application/json'};
      for (const header of ['x-razorpay-signature', 'x-razorpay-event-id']) {
        if (typeof req.headers[header] === 'string') webhookHeaders[header] = req.headers[header];
      }
      const result = await call(urls.orders + '/payments/webhook', 'POST', webhookHeaders, Buffer.concat(chunks));
      return reply(res, result.status, result.body);
    }
    if (req.method !== 'GET' && req.headers.origin !== origin) return reply(res, 403, {error: 'invalid_origin'});
    const guest = session(req.headers.cookie, secret), cookies = [];
    if (guest.fresh) cookies.push(signedCookie(guest.id, secret, secure));
    const token = accountToken(req.headers.cookie);
    const headers = {'Content-Type': 'application/json', 'X-Session-ID': guest.id, 'X-Request-ID': rid};
    if (token) headers['X-Account-Token'] = token;
    let cartSession = guest.id;
    if (token && (path.startsWith('/api/cart') || path.startsWith('/api/orders'))) {
      const identity = await call(urls.orders + '/auth/session', 'GET', headers);
      if (identity.status !== 200) return reply(res, identity.status, identity.body);
      const customerId = identity.body.user?.id;
      if (typeof customerId !== 'string' || !/^[a-f0-9-]{36}$/.test(customerId)) throw Error('invalid_auth_response');
      cartSession = createHash('sha256').update('customer:' + customerId).digest('hex');
      headers['X-Session-ID'] = cartSession;
      if (path.startsWith('/api/cart') && !guest.fresh) {
        const merged = await call(urls.cart + '/carts/' + guest.id + '/merge/' + cartSession, 'POST', headers);
        if (merged.status !== 200) return reply(res, merged.status, merged.body);
      }
    }
    let result;
    if (['/api/auth/register', '/api/auth/login'].includes(path) && req.method === 'POST') {
      const body = await input(req);
      if (!body) return reply(res, 400, {error: 'invalid_json'});
      result = await call(urls.orders + path.slice(4), 'POST', headers, JSON.stringify(body), 15000);
      if (result.status === 200) {
        // The token is only sent to the browser as an HttpOnly cookie, never JSON/localStorage.
        if (!/^[a-f0-9]{64}$/.test(result.body.token || '')) throw Error('invalid_auth_response');
        cookies.push(accountCookie(result.body.token));
        result.body = {user: result.body.user};
      }
    } else if (path === '/api/auth/session' && req.method === 'GET') {
      result = token ? await call(urls.orders + '/auth/session', 'GET', headers) : {status: 200, body: {user: null}};
      if (result.status === 401) {
        cookies.push(accountCookie('', 0));
        result = {status: 200, body: {user: null}};
      }
    } else if (path === '/api/auth/logout' && req.method === 'POST') {
      result = await call(urls.orders + '/auth/logout', 'POST', headers);
      if (result.status === 200) {
        cookies.push(accountCookie('', 0), signedCookie(randomBytes(32).toString('hex'), secret, secure));
      }
    } else if (path === '/api/payments/config' && req.method === 'GET') {
      result = await call(urls.orders + '/payments/config', 'GET', headers);
    } else if (/^\/api\/orders\/[a-f0-9-]{36}\/payment\/fixture-capture$/.test(path) && req.method === 'POST') {
      result = await call(urls.orders + path.slice(4), 'POST', headers, JSON.stringify(await input(req) || {}));
    } else if (/^\/api\/orders\/[a-f0-9-]{36}\/payment(?:\/verify)?$/.test(path) && req.method === 'POST') {
      result = await call(urls.orders + path.slice(4), 'POST', headers, JSON.stringify(await input(req) || {}));
    } else if (['/api/admin/dashboard', '/api/admin/products', '/api/admin/orders', '/api/admin/audit'].includes(path) && req.method === 'GET') {
      const requestedPage = url.searchParams.get('page') || '0';
      if (!/^\d{1,5}$/.test(requestedPage)) return reply(res, 400, {error: 'invalid_page'});
      result = await call(urls.orders + path.slice(4) + (path.endsWith('/orders') ? '?page=' + requestedPage : ''), 'GET', headers);
    } else if ((/^\/api\/admin\/products\/[a-z0-9-]{1,64}$/.test(path) && req.method === 'PUT')
      || (/^\/api\/admin\/orders\/[a-f0-9-]{36}\/(?:status|refund|payment\/reconcile)$/.test(path) && req.method === 'POST')) {
      result = await call(urls.orders + path.slice(4), req.method, headers, JSON.stringify(await input(req) || {}));
    } else if (path === '/api/products' && req.method === 'GET') {
      result = await call(urls.catalogue + '/products', 'GET', headers);
    } else if (path === '/api/cart' && req.method === 'GET') {
      result = await call(urls.cart + '/carts/' + cartSession, 'GET', headers);
    } else if (/^\/api\/cart\/items\/[a-z0-9-]{1,64}$/.test(path) && ['PUT', 'DELETE'].includes(req.method)) {
      let body;
      if (req.method === 'PUT') {
        const value = await input(req);
        if (!Number.isInteger(value?.quantity) || value.quantity < 1 || value.quantity > 20)
          return reply(res, 400, {error: 'invalid_quantity'});
        const product = await call(urls.catalogue + '/products/' + path.split('/').at(-1), 'GET', headers);
        if (product.status !== 200) return reply(res, product.status, {error: 'product_not_found'});
        body = JSON.stringify({quantity: value.quantity});
      }
      result = await call(urls.cart + '/carts/' + cartSession + '/items/' + path.split('/').at(-1), req.method, headers, body);
    } else if (path === '/api/orders' && req.method === 'POST') {
      const key = req.headers['idempotency-key'];
      if (typeof key !== 'string' || !/^[A-Za-z0-9_-]{8,64}$/.test(key))
        return reply(res, 400, {error: 'invalid_idempotency_key'});
      const body = await input(req);
      result = await call(urls.orders + '/orders', 'POST', {...headers, 'Idempotency-Key': key}, body ? JSON.stringify(body) : undefined);
    } else if (path === '/api/orders' && req.method === 'GET') {
      const currentPage = url.searchParams.get('page') || '0';
      if (!/^\d{1,5}$/.test(currentPage)) return reply(res, 400, {error: 'invalid_page'});
      result = await call(urls.orders + '/orders?page=' + currentPage, 'GET', headers);
    } else if (/^\/api\/orders\/[a-f0-9-]{36}$/.test(path) && req.method === 'GET') {
      result = await call(urls.orders + '/orders/' + path.split('/').at(-1), 'GET', headers);
    } else return reply(res, 404, {error: 'not_found'});
    if (cookies.length) res.setHeader('Set-Cookie', cookies);
    return reply(res, result.status, result.body);
  } catch (error) {
    // Do not log auth payloads, cookie values or backend exception bodies.
    console.error(JSON.stringify({event: 'request_error', request_id: rid, type: error.name}));
    if (!res.headersSent) reply(res, error.status || 503, {error: error.status ? error.message : 'service_unavailable'});
    else res.end();
  }
});
server.requestTimeout = 10000;
server.headersTimeout = 10000;
server.listen(Number(process.env.PORT || 8080), '0.0.0.0');
process.on('SIGTERM', () => {
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 20000).unref();
});

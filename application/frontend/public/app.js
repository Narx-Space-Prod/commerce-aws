const $ = id => document.getElementById(id);
const money = (value, currency = products[0]?.currency || 'INR') => new Intl.NumberFormat('en-IN', {style: 'currency', currency}).format(value / 100);
let paymentConfig = {enabled: false}, adminSection = "dashboard", adminPage = 0;
let products = [], cart = {items: []}, user = null, register = false, page = 0, pending = false;
const errorMessages = {
  invalid_credentials: 'The email or password is incorrect.',
  account_unavailable: 'This account could not be created. Try signing in with your email.',
  password_length: 'Choose a passphrase between 15 and 128 characters.',
  invalid_email: 'Enter a valid email address.',
  invalid_name: 'Enter your name (up to 80 characters).',
  try_later: 'Too many attempts. Please wait 15 minutes before trying again.',
  sign_in_required: 'Your session has expired. Please sign in again.',
  invalid_delivery: 'Please check your delivery details.',
  payments_not_configured: 'Razorpay test credentials are not configured yet.',
  out_of_stock: 'One of your items is out of stock. Please update your bag.',
  product_changed: 'This product changed while you were editing it. Reload and try again.',
  invalid_order_transition: 'That order status change is not allowed.',
  payment_initialization_needs_reconciliation: 'Payment setup needs an administrator to check it. Do not create another order.',
  payment_not_captured: 'Payment has not been captured yet. Your order is still pending.',
  invalid_payment_signature: 'Payment verification failed. Your order has not been marked paid.',
  empty_cart: 'Your bag is empty. Add something you like first.',
  service_unavailable: 'We could not reach the store. Please try again shortly.',
};
async function api(path, method = 'GET', body, headers = {}) {
  const response = await fetch('/api' + path, {method, headers: {'Content-Type': 'application/json', ...headers},
    body: body === undefined ? undefined : JSON.stringify(body)});
  const data = await response.json();
  if (!response.ok) {
    const key = data.error || data.detail || data.message;
    throw Object.assign(Error(errorMessages[key] || (response.status === 401 ? errorMessages.sign_in_required
      : response.status === 429 ? errorMessages.try_later : 'We couldn’t complete that request. Please try again.')), {status: response.status});
  }
  return data;
}
function element(tag, text, className) {
  const node = document.createElement(tag);
  if (text !== undefined) node.textContent = text;
  if (className) node.className = className;
  return node;
}
function link(text, href, className = 'text-link') {
  const node = element('a', text, className); node.href = href; return node;
}
function message(text) { $('status').textContent = text; $('checkout-status').textContent = text; }
function storage(action, key, value) {
  try { return sessionStorage[action](key, value); } catch { return null; }
}
function resetCheckout() { storage('removeItem', 'checkout'); }
function randomUUID() {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  // Web Crypto's random byte API also works on plain-HTTP LAN origins.
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, value => value.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
function checkoutKey() {
  const signature = JSON.stringify(cart.items);
  let saved;
  try { saved = JSON.parse(storage('getItem', 'checkout')); } catch { /* Invalid local metadata is discarded. */ }
  if (saved?.signature === signature && saved.key) return saved.key;
  const key = randomUUID();
  storage('setItem', 'checkout', JSON.stringify({signature, key}));
  return key;
}
function summaryItems(root, items, ordered = false, currency = products[0]?.currency || 'INR') {
  let total = 0;
  for (const item of items) {
    const product = ordered ? item : products.find(product => product.id === item.productId);
    if (!product) continue;
    total += product.price * item.quantity;
    const row = element('div', undefined, 'summary-row');
    const label = element('div'); label.append(element('strong', product.name), element('p', `Quantity ${item.quantity}`, 'muted'));
    row.append(label, element('strong', money(product.price * item.quantity, product.currency || currency)));
    root.append(row);
  }
  return total;
}
function renderCart() {
  const root = $('cart-items'); root.replaceChildren();
  let total = 0, count = 0;
  for (const item of cart.items) {
    const product = products.find(product => product.id === item.productId);
    if (!product) continue;
    total += product.price * item.quantity; count += item.quantity;
    const row = element('div', undefined, 'cart-row'), info = element('div');
    info.append(element('strong', product.name), element('p', money(product.price), 'muted'));
    const controls = element('div', undefined, 'quantity-controls');
    const minus = element('button', '−', 'secondary'), plus = element('button', '+', 'secondary');
    minus.setAttribute('aria-label', 'Reduce quantity of ' + product.name);
    plus.setAttribute('aria-label', 'Increase quantity of ' + product.name);
    plus.disabled = item.quantity >= 20 || pending; minus.disabled = pending;
    minus.onclick = () => changeQuantity(product.id, item.quantity - 1);
    plus.onclick = () => changeQuantity(product.id, item.quantity + 1);
    controls.append(minus, element('span', String(item.quantity)), plus);
    const remove = element('button', 'Remove', 'quiet'); remove.disabled = pending;
    remove.onclick = () => changeQuantity(product.id, 0);
    info.append(controls, remove); row.append(info, element('strong', money(product.price * item.quantity, product.currency))); root.append(row);
  }
  if (!count) root.append(element('p', 'Your bag is waiting for something good.', 'empty-state'));
  $('count').textContent = count;
  $('total').textContent = 'Total ' + money(total);
  $('checkout').disabled = !count || pending;
}
async function changeQuantity(id, quantity) {
  if (pending) return;
  pending = true; renderCart();
  try {
    cart = await api('/cart/items/' + id, quantity ? 'PUT' : 'DELETE', quantity ? {quantity} : undefined);
    resetCheckout(); renderCheckout();
  } catch (error) { message(error.message); }
  finally { pending = false; renderCart(); }
}
function renderProducts() {
  $('products').replaceChildren();
  for (const product of products) {
    const card = element('article', undefined, 'product');
    const art = element('div', product.emoji, 'art art-' + product.id); art.setAttribute('aria-hidden', 'true');
    const details = element('div', undefined, 'details');
    details.append(element('p', 'THE EVERYDAY COLLECTION', 'eyebrow'), element('h3', product.name));
    const buy = element('div', undefined, 'buy'), button = element('button', 'Add to bag');
    button.disabled = product.stock === 0;
    if (product.stock === 0) button.textContent = 'Sold out';
    button.onclick = async () => {
      if (pending) return;
      button.disabled = true;
      await changeQuantity(product.id, (cart.items.find(item => item.productId === product.id)?.quantity || 0) + 1);
      button.disabled = false;
    };
    buy.append(element('strong', money(product.price)), button); if (product.description) details.append(element('p', product.description, 'muted'));
    details.append(buy); card.append(art, details); $('products').append(card);
  }
}
function renderAccount() {
  $('account-link').textContent = user ? 'My account' : 'Sign in';
  $('admin-link').hidden = user?.role !== 'admin';
  $('profile').hidden = !user; $('auth-panel').hidden = Boolean(user);
  $('account-title').textContent = user ? 'Your account.' : register ? 'Make yourself at home.' : 'Welcome back.';
  if (user) { $('profile-name').textContent = user.name; $('profile-email').textContent = user.email; }
}
function authMode(create) {
  register = create;
  $('name-field').hidden = !create; $('auth-name').required = create;
  $('password-help').hidden = !create; $('auth-password').minLength = create ? 15 : 1;
  $('auth-password').autocomplete = create ? 'new-password' : 'current-password';
  $('auth-submit').textContent = create ? 'Create account' : 'Sign in';
  $('login-tab').setAttribute('aria-pressed', String(!create));
  $('register-tab').setAttribute('aria-pressed', String(create));
  $('auth-error').textContent = ''; renderAccount();
}
function renderCheckout() {
  $('checkout-signin').hidden = Boolean(user); $('checkout-content').hidden = !user;
  if (!user) return;
  if (!$('delivery-name').value) $('delivery-name').value = user.name;
  const root = $('checkout-summary'); root.replaceChildren(element('h2', 'Your order'));
  const total = summaryItems(root, cart.items);
  root.append(element('p', 'Total ' + money(total), 'cart-total'), element('p', paymentConfig.mode === 'fixture' ? 'Local payment simulator. No real payment or charge occurs.' : 'Razorpay test mode. No real money is charged or goods shipped.', 'muted'));
  $('place-order').disabled = !cart.items.length || pending || !paymentConfig.enabled;
  if (!paymentConfig.enabled) root.append(element('p', errorMessages.payments_not_configured, 'form-error'));
  if (!cart.items.length) root.append(link('Your bag is empty. Explore the collection →', '/'));
}
function empty(root, title, text) {
  const box = element('div', undefined, 'surface empty-state');
  box.append(element('h2', title), element('p', text), link('Explore the collection →', '/', 'button-link')); root.append(box);
}
async function renderOrders() {
  $('orders-intro').textContent = user ? 'Your purchases, saved to your account.'
    : 'Sign in to see your account orders. Guest orders below are available only in this browser.';
  const root = $('order-list'); root.replaceChildren(element('p', 'Loading your orders…', 'muted')); $('pagination').hidden = true;
  try {
    const data = await api('/orders?page=' + page); root.replaceChildren();
    if (!user) root.append(link('Sign in to your account →', '/account'));
    if (!data.orders.length) empty(root, 'Your story starts here.', 'Once you place an order, you’ll find its details here.');
    for (const order of data.orders) {
      const card = element('article', undefined, 'surface order-card');
      const heading = element('div', undefined, 'section-heading');
      heading.append(element('h2', 'Order ' + order.id.slice(0, 8).toUpperCase()), element('span', statusText(order), 'badge'));
      const date = new Date(order.created_at).toLocaleDateString(undefined, {year: 'numeric', month: 'long', day: 'numeric'});
      const names = order.items.map(item => `${item.name} × ${item.quantity}`).join(' · ');
      card.append(heading, element('p', date, 'muted'), element('p', names));
      const actions = element('div', undefined, 'section-heading');
      actions.append(element('strong', money(order.total, order.currency)), link('View order →', '/orders/' + order.id)); card.append(actions); root.append(card);
    }
    $('pagination').hidden = page === 0 && !data.hasMore;
    $('previous-orders').disabled = page === 0; $('next-orders').disabled = !data.hasMore;
    $('page-number').textContent = 'Page ' + (page + 1);
  } catch (error) { root.replaceChildren(element('p', error.message, 'form-error')); }
}
async function renderOrder(id) {
  const root = $('order-detail'); root.replaceChildren(element('p', 'Loading order…', 'muted'));
  try {
    const order = await api('/orders/' + id), receipt = element('article', undefined, 'surface receipt');
    const confirmed = new URLSearchParams(location.search).has('confirmed');
    root.replaceChildren(element('p', confirmed ? 'THANK YOU FOR YOUR ORDER' : 'ORDER DETAILS', 'eyebrow'),
      element('h1', confirmed && order.payment_status === 'paid' ? 'It’s yours.' : 'Your order.'));
    receipt.append(element('span', statusText(order), 'badge'), element('h2', 'Order ' + order.id.slice(0, 8).toUpperCase()),
      element('p', new Date(order.created_at).toLocaleString(), 'muted'), element('p', 'Reference: ' + order.id, 'order-reference'));
    summaryItems(receipt, order.items, true, order.currency);
    receipt.append(element('p', 'Total ' + money(order.total, order.currency), 'cart-total'));
    if (order.delivery) {
      const details = element('section', undefined, 'delivery');
      details.append(element('h3', 'Delivery details'), element('p', order.delivery.name), element('p', order.delivery.address),
        element('p', order.delivery.city + ' · ' + order.delivery.postalCode), element('p', order.delivery.country)); receipt.append(details);
    }
    receipt.append(element('p', order.payment_status === 'demo' ? 'A legacy demo order. No payment was collected.' : 'Test payment. No real money is charged or goods shipped.', 'muted'));
    if (order.status === 'payment_pending' && user) {
      const pay = element('button', 'Pay with Razorpay (test)');
      pay.disabled = !paymentConfig.enabled;
      pay.onclick = async () => { pay.disabled = true; try { await payForOrder(order); } catch (error) { message(error.message); pay.disabled = false; } };
      receipt.append(pay);
    }
    root.append(receipt, link('Continue shopping →', '/', 'button-link'));
  } catch (error) {
    root.replaceChildren(element('h1', error.status === 404 ? 'Order not found.' : 'Unable to load order.'),
      element('p', error.status === 404 ? 'This order is unavailable for the current account or browser.' : error.message),
      link('Go to my orders →', '/orders'));
  }
}
async function start() {
  const path = location.pathname;
  const name = path === '/' ? 'shop' : path === '/account' ? 'account' : path === '/checkout' ? 'checkout'
    : path === '/orders' ? 'orders' : path === '/admin' ? 'admin' : 'order';
  $(name + '-page').hidden = false;
  try {
    // Establish the browser session before parallel requests can race to create cookies.
    try { cart = await api('/cart'); } catch { cart = {items: []}; }
    const identity = await api('/auth/session'); user = identity.user;
    const [catalogue, config] = await Promise.allSettled([api('/products'), api('/payments/config')]);
    products = catalogue.status === 'fulfilled' ? catalogue.value : [];
    paymentConfig = config.status === 'fulfilled' ? config.value : {enabled: false};
    if (catalogue.status !== 'fulfilled' && ['shop', 'checkout'].includes(name)) message(catalogue.reason.message);
    renderProducts(); renderCart(); renderAccount(); renderCheckout();
    if (name === 'admin') await renderAdmin();
    if (name === 'orders') await renderOrders();
    if (name === 'order') await renderOrder(path.split('/').at(-1));
  } catch (error) { message(error.message); }
}
$('login-tab').onclick = () => authMode(false);
$('register-tab').onclick = () => authMode(true);
$('auth-form').onsubmit = async event => {
  event.preventDefault(); $('auth-submit').disabled = true; $('auth-error').textContent = '';
  try {
    const identity = await api(register ? '/auth/register' : '/auth/login', 'POST', {
      email: $('auth-email').value, password: $('auth-password').value, name: $('auth-name').value,
    });
    user = identity.user; $('auth-password').value = ''; resetCheckout();
    location.assign(new URLSearchParams(location.search).get('next') === 'checkout' ? '/checkout' : '/orders');
  } catch (error) { $('auth-error').textContent = error.message; }
  finally { $('auth-submit').disabled = false; }
};
$('logout').onclick = async () => {
  $('logout').disabled = true;
  try { await api('/auth/logout', 'POST'); resetCheckout(); location.assign('/'); }
  catch (error) { message(error.message); $('logout').disabled = false; }
};
$('cart-toggle').onclick = () => $('cart-panel').showModal();
$('close-cart').onclick = () => $('cart-panel').close();
$('checkout').onclick = () => location.assign('/checkout');
$('previous-orders').onclick = () => { page--; renderOrders(); };
$('next-orders').onclick = () => { page++; renderOrders(); };
$('checkout-form').onsubmit = async event => {
  event.preventDefault(); if (pending) return;
  pending = true; $('place-order').disabled = true; $('checkout-error').textContent = '';
  try {
    const delivery = Object.fromEntries(new FormData(event.target));
    const order = await api('/orders', 'POST', delivery, {'Idempotency-Key': checkoutKey()});
    // Preserve the durable order ID if the payment window closes or verification is interrupted.
    storage('setItem', 'pending-order', order.id);
    await payForOrder(order);
  } catch (error) { $('checkout-error').textContent = error.message; }
  finally { pending = false; $('place-order').disabled = !cart.items.length || !paymentConfig.enabled; }
};

function statusText(order) {
  if (order.payment_status === 'refunding') return 'Refund pending';
  return ({payment_pending: 'Awaiting payment', confirmed: 'Confirmed', processing: 'Preparing your order',
    shipped: 'Shipped', delivered: 'Delivered', refunded: 'Refunded', cancelled: 'Cancelled'})[order.status] || order.status;
}
let checkoutScript;
function loadRazorpay() {
  if (window.Razorpay) return Promise.resolve();
  if (!checkoutScript) checkoutScript = new Promise((resolve, reject) => {
    const script = document.createElement('script'); script.src = 'https://checkout.razorpay.com/v1/checkout.js';
    script.onload = () => window.Razorpay ? resolve() : reject(Error('Payment checkout did not load.'));
    script.onerror = () => { checkoutScript = null; reject(Error('Unable to load Razorpay. Retry from My orders.')); };
    document.head.append(script);
  });
  return checkoutScript;
}
async function payForOrder(order) {
  const payment = await api('/orders/' + order.id + '/payment', 'POST');
  if (payment.mode === 'fixture') {
    if (!window.confirm('Local payment simulator: no Razorpay transaction will be made and no money will be charged. Simulate a successful test payment?')) return;
    const proof = await api('/orders/' + order.id + '/payment/fixture-capture', 'POST', {});
    await completePayment(order, proof);
    return;
  }
  await loadRazorpay();
  await new Promise((resolve, reject) => {
    const checkout = new window.Razorpay({
      key: payment.keyId, amount: payment.amount, currency: payment.currency, order_id: payment.providerOrderId,
      name: 'Shipyard Boutique', description: 'Order ' + order.id.slice(0, 8),
      prefill: {name: user.name, email: user.email},
      handler: async proof => {
        try {
          await completePayment(order, proof); resolve();
        } catch (error) { reject(error); }
      },
      modal: {ondismiss: () => { location.assign('/orders/' + order.id); resolve(); }},
      theme: {color: '#253b35'},
    });
    checkout.on('payment.failed', () => message('Payment was not completed. You can retry from this order.'));
    checkout.open();
  });
}
async function completePayment(order, proof) {
  await api('/orders/' + order.id + '/payment/verify', 'POST', proof);
  for (const item of order.items) {
    try { await api('/cart/items/' + item.productId, 'DELETE'); } catch { /* Order remains paid and visible. */ }
  }
  resetCheckout(); storage('removeItem', 'pending-order');
  location.assign('/orders/' + order.id + '?confirmed=1');
}

async function renderAdmin() {
  if (user?.role !== 'admin') {
    $('admin-error').textContent = user ? 'This page is available to store administrators.' : 'Sign in with an administrator account to continue.';
    $('admin-content').hidden = true; return;
  }
  $('admin-content').hidden = false; $('admin-error').textContent = '';
  const root = $('admin-view'); root.replaceChildren(element('p', 'Loading store data…', 'muted'));
  try {
    if (adminSection === 'dashboard') await dashboard(root);
    if (adminSection === 'products') await adminProducts(root);
    if (adminSection === 'orders') await adminOrders(root);
    if (adminSection === 'audit') {
      const records = await api('/admin/audit'); root.replaceChildren(element('h2', 'Recent administrator activity'));
      for (const record of records) root.append(element('p', `${new Date(record.created_at).toLocaleString()} · ${record.actor} · ${record.action} · ${record.resource_id}`, 'surface'));
      if (!records.length) root.append(element('p', 'No administrator actions yet.', 'muted'));
    }
  } catch (error) { root.replaceChildren(element('p', error.message, 'form-error')); }
}
async function dashboard(root) {
  const data = await api('/admin/dashboard'); root.replaceChildren();
  const metrics = element('div', undefined, 'metric-grid');
  for (const [label, value] of [['Customers', data.counts.customers], ['Orders', data.counts.orders], ['Active products', data.counts.products], ['Awaiting payment', data.counts.pending]]) {
    const card = element('div', undefined, 'surface metric'); card.append(element('p', label, 'muted'), element('strong', String(value))); metrics.append(card);
  }
  root.append(metrics);
  const sales = element('section', undefined, 'surface'); sales.append(element('h2', 'Test sales'));
  for (const sale of data.sales) sales.append(element('p', `${sale.currency}: gross ${money(sale.gross, sale.currency)} · refunded ${money(sale.refunds, sale.currency)} · net ${money(sale.net, sale.currency)} · ${sale.paid_orders} paid orders`));
  if (!data.sales.length) sales.append(element('p', 'Paid test orders will appear here. Legacy demo orders are excluded.', 'muted'));
  root.append(sales);
  const history = element('section', undefined, 'surface'); history.append(element('h2', 'Sales activity · last 30 days'));
  for (const day of data.daily) {
    const row = element('div', undefined, 'summary-row');
    row.append(element('span', new Date(day.day).toLocaleDateString(undefined, {year: 'numeric', month: 'short', day: 'numeric'})), element('strong', `${day.orders} orders · ${money(day.gross, day.currency)}`)); history.append(row);
  }
  if (!data.daily.length) history.append(element('p', 'No paid orders yet.', 'muted'));
  root.append(history);
  const low = element('section', undefined, 'surface'); low.append(element('h2', 'Stock to watch'));
  for (const product of data.lowStock) low.append(element('p', `${product.name}: ${product.stock} available`));
  if (!data.lowStock.length) low.append(element('p', 'All active products have at least 10 available.', 'muted')); root.append(low);
}
async function adminProducts(root) {
  const list = await api('/admin/products');
  const heading = element('div', undefined, 'section-heading'), add = element('button', 'Add product');
  add.onclick = () => editProduct(); heading.append(element('h2', 'Products & inventory'), add); root.replaceChildren(heading);
  for (const product of list) {
    const row = element('article', undefined, 'surface section-heading');
    const info = element('div'); info.append(element('h3', product.emoji + ' ' + product.name),
      element('p', `${money(product.price, product.currency)} · ${product.stock} available · ${product.active ? 'Visible' : 'Archived'}`, 'muted'));
    const edit = element('button', 'Edit', 'secondary'); edit.onclick = () => editProduct(product); row.append(info, edit); root.append(row);
  }
}
function editProduct(product = {}) {
  const form = $('product-form'); form.reset();
  for (const field of ['id', 'name', 'description', 'emoji', 'stock', 'version']) form.elements[field].value = product[field] ?? (field === 'emoji' ? '◈' : field === 'version' ? 0 : '');
  form.elements.id.readOnly = Boolean(product.id); form.elements.price.value = product.price ? product.price / 100 : '';
  form.elements.active.checked = product.active ?? true; $('product-error').textContent = ''; $('product-editor').showModal();
}
async function adminOrders(root) {
  const data = await api('/admin/orders?page=' + adminPage); root.replaceChildren(element('h2', 'Orders, fulfilment & refunds'));
  for (const order of data.orders) {
    const card = element('article', undefined, 'surface');
    card.append(element('h3', 'Order ' + order.id.slice(0, 8).toUpperCase()), element('span', statusText(order), 'badge'),
      element('p', `${order.customer_name || 'Guest'} · ${order.email || 'Browser session'} · ${money(order.total, order.currency)}`));
    summaryItems(card, order.items, true, order.currency);
    if (order.delivery) card.append(element('p', `${order.delivery.name} · ${order.delivery.address} · ${order.delivery.city} · ${order.delivery.postalCode} · ${order.delivery.country}`, 'muted'));
    const actions = element('div', undefined, 'actions wrap');
    const next = ({confirmed: 'processing', processing: 'shipped', shipped: 'delivered'})[order.status];
    if (next && order.payment_status === 'paid') {
      const button = element('button', 'Mark ' + next); button.onclick = () => adminAction(button, '/admin/orders/' + order.id + '/status', {status: next}); actions.append(button);
    }
    if (['paid', 'refunding'].includes(order.payment_status)) {
      const form = element('form', undefined, 'refund-form'), reason = element('input');
      reason.placeholder = 'Reason for full refund'; reason.required = true; reason.maxLength = 300; reason.setAttribute('aria-label', 'Reason for full refund');
      const button = element('button', order.payment_status === 'refunding' ? 'Refresh / retry refund' : 'Refund ' + money(order.total, order.currency), 'secondary'); button.type = 'submit';
      form.append(reason, button); form.onsubmit = event => { event.preventDefault(); if (confirm('Request a full test-mode refund for this order?')) adminAction(button, '/admin/orders/' + order.id + '/refund', {reason: reason.value}); }; actions.append(form);
    }
    if (order.status === 'payment_pending' && !order.provider_order_id && order.payment_status === 'unpaid') {
      const cancel = element('button', 'Cancel unpaid order', 'secondary'); cancel.onclick = () => adminAction(cancel, '/admin/orders/' + order.id + '/status', {status: 'cancelled'}); actions.append(cancel);
    }
    if (['initialization_unknown', 'initializing'].includes(order.payment_status)) {
      const form = element('form'), remote = element('input'); remote.placeholder = 'Verified Razorpay order_… ID'; remote.required = true;
      remote.setAttribute('aria-label', 'Razorpay order ID from the test dashboard');
      const button = element('button', 'Reconcile payment', 'secondary'); form.append(remote, button);
      form.onsubmit = event => { event.preventDefault(); adminAction(button, '/admin/orders/' + order.id + '/payment/reconcile', {providerOrderId: remote.value}); }; actions.append(form);
    }
    card.append(actions); root.append(card);
  }
  if (!data.orders.length) root.append(element('p', 'No orders yet.', 'muted'));
  const navigation = element('div', undefined, 'actions');
  const previous = element('button', 'Previous', 'secondary'), next = element('button', 'Next', 'secondary');
  previous.disabled = adminPage === 0; next.disabled = !data.hasMore;
  previous.onclick = () => { adminPage--; renderAdmin(); }; next.onclick = () => { adminPage++; renderAdmin(); };
  navigation.append(previous, element('span', 'Page ' + (adminPage + 1)), next); root.append(navigation);
}
async function adminAction(button, path, body) {
  button.disabled = true; $('admin-error').textContent = '';
  try { await api(path, 'POST', body); await renderAdmin(); }
  catch (error) { $('admin-error').textContent = error.message; button.disabled = false; }
}
for (const tab of document.querySelectorAll('[data-admin]')) tab.onclick = () => { adminSection = tab.dataset.admin; renderAdmin(); };
$('close-editor').onclick = () => $('product-editor').close();
$('product-form').onsubmit = async event => {
  event.preventDefault(); $('save-product').disabled = true;
  const form = event.target, body = Object.fromEntries(new FormData(form));
  body.price = Math.round(Number(body.price) * 100); body.stock = Number(body.stock); body.version = Number(body.version); body.active = form.elements.active.checked;
  try { await api('/admin/products/' + body.id, 'PUT', body); $('product-editor').close(); await renderAdmin(); }
  catch (error) { $('product-error').textContent = error.message; }
  finally { $('save-product').disabled = false; }
};
start();

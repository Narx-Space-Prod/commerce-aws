import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
const source = await readFile(new URL('../public/app.js', import.meta.url), 'utf8');

function screen(fetch) {
  const elements = new Map(), stored = new Map(), navigation = [];
  const element = id => {
    if (!elements.has(id)) elements.set(id, {hidden: false, disabled: false, textContent: ''});
    return elements.get(id);
  };
  const context = vm.createContext({document: {getElementById: element, querySelectorAll: () => []}, Intl,
    crypto: {randomUUID: () => 'test-checkout-key'}, fetch,
    FormData: class { *[Symbol.iterator]() { yield ['name', 'Demo']; } },
    sessionStorage: {getItem: key => stored.get(key) || null, setItem: (key, value) => stored.set(key, value), removeItem: key => stored.delete(key)},
    location: {assign: path => navigation.push(path)}, window: {},
  });
  vm.runInContext(source.replace(/\nstart\(\);\s*$/, '\n'), context);
  vm.runInContext("cart={items:[{productId:'mug',quantity:1}]}; paymentConfig={enabled:true};", context);
  return {context, element, stored, navigation};
}

test('bag checkout navigates to the separate checkout page', () => {
  const screenState = screen(); screenState.element('checkout').onclick();
  assert.deepEqual(screenState.navigation, ['/checkout']);
});

test('a failed order stays on checkout with a visible error and reusable key', async () => {
  const {element, stored} = screen(async () => ({ok: false, status: 503, json: async () => ({error: 'service_unavailable'})}));
  await element('checkout-form').onsubmit({preventDefault() {}, target: {}});
  assert.match(element('checkout-error').textContent, /try again/i);
  assert.equal(element('place-order').disabled, false);
  assert.equal(JSON.parse(stored.get('checkout')).key, 'test-checkout-key');
});

test('successful order creation hands its durable identity to payment before confirmation', async () => {
  const {context, element, stored} = screen(async () => ({ok: true, json: async () => ({id: 'order-123', items: [{productId:'mug',quantity:1}]})}));
  vm.runInContext('payForOrder=async order=>{globalThis.paymentOrder=order.id;};', context);
  await element('checkout-form').onsubmit({preventDefault() {}, target: {}});
  assert.equal(context.paymentOrder, 'order-123');
  assert.equal(stored.get('pending-order'), 'order-123');
  assert.equal(element('checkout-error').textContent, '');
});

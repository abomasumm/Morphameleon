import { describe, it, expect } from 'vitest';
import { createCart } from '../src/cart';
import { PLANTS } from '../src/catalog';

const monstera = PLANTS.find((p) => p.id === 'monstera'); // stock 4, price 38
const pothos = PLANTS.find((p) => p.id === 'pothos'); // stock 0, price 16.5
const snake = PLANTS.find((p) => p.id === 'snake'); // stock 9, price 24
const zz = PLANTS.find((p) => p.id === 'zz'); // stock 7, price 21

describe('cart', () => {
  it('adds a plant with positive stock and notifies once', () => {
    const cart = createCart();
    const calls = [];
    cart.onChange(() => { calls.push(1); });

    expect(cart.add(snake)).toBe(true);
    expect(cart.lines).toEqual([{ id: 'snake', name: 'Snake plant', price: 24, qty: 1 }]);
    expect(calls.length).toBe(1);
  });

  it('refuses a sold-out plant and does not notify', () => {
    const cart = createCart();
    let calls = 0;
    cart.onChange(() => { calls++; });

    expect(cart.add(pothos)).toBe(false);
    expect(cart.lines).toEqual([]);
    expect(calls).toBe(0);
  });

  it('increments an existing line while under the stock limit', () => {
    const cart = createCart();
    const calls = [];
    cart.onChange(() => { calls.push(1); });

    expect(cart.add(monstera)).toBe(true);
    expect(cart.add({ id: 'monstera', name: 'Monstera', price: 38, stock: 4 })).toBe(true);
    expect(cart.lines).toEqual([{ id: 'monstera', name: 'Monstera', price: 38, qty: 2 }]);
    expect(calls.length).toBe(2);
  });

  it('stops at the stock limit and leaves the cart unchanged', () => {
    const cart = createCart();
    let calls = 0;
    cart.onChange(() => { calls++; });

    for (let i = 0; i < monstera.stock; i++) {
      expect(cart.add(monstera)).toBe(true);
    }
    expect(calls).toBe(monstera.stock);
    expect(cart.lines).toEqual([{ id: 'monstera', name: 'Monstera', price: 38, qty: 4 }]);

    expect(cart.add(monstera)).toBe(false);
    expect(cart.lines).toEqual([{ id: 'monstera', name: 'Monstera', price: 38, qty: 4 }]);
    expect(calls).toBe(monstera.stock);
  });

  it('removes the first matching line and notifies once', () => {
    const cart = createCart();
    let calls = 0;
    cart.onChange(() => { calls++; });
    cart.add(snake);
    cart.add(zz);
    expect(calls).toBe(2);

    cart.remove('snake');
    expect(calls).toBe(3);
    expect(cart.lines).toEqual([{ id: 'zz', name: 'ZZ plant', price: 21, qty: 1 }]);
  });

  it('ignores removing an unknown id and does not notify', () => {
    const cart = createCart();
    let calls = 0;
    cart.onChange(() => { calls++; });
    cart.add(snake);

    cart.remove('nope');
    expect(calls).toBe(1);
    expect(cart.lines).toEqual([{ id: 'snake', name: 'Snake plant', price: 24, qty: 1 }]);
  });

  it('counts and totals an empty cart as zero', () => {
    const cart = createCart();
    expect(cart.count()).toBe(0);
    expect(cart.subtotal()).toBe(0);
  });

  it('counts and totals a multi-line cart', () => {
    const cart = createCart();
    cart.add(snake);
    cart.add(snake);
    cart.add(zz);
    expect(cart.lines.length).toBe(2);
    expect(cart.count()).toBe(3);
    expect(cart.subtotal()).toBe(24 * 2 + 21);
  });

  it('charges no shipping for an empty cart and free shipping from 75', () => {
    const cart = createCart();
    expect(cart.shipping()).toBe(0);
    expect(cart.total()).toBe(0);
    expect(cart.toFreeShipping()).toBe(75);

    cart.add(snake);
    cart.add(snake);
    cart.add(zz); // subtotal 69
    expect(cart.shipping()).toBe(6.5);
    expect(cart.total()).toBe(69 + 6.5);
    expect(cart.toFreeShipping()).toBe(75 - 69);
  });

  it('charges 6.5 just below the threshold and 0 at 75 and above', () => {
    const justBelow = createCart();
    justBelow.add({ id: 'a', name: 'A', price: 72, stock: 9 });
    expect(justBelow.subtotal()).toBe(72);
    expect(justBelow.shipping()).toBe(6.5);
    expect(justBelow.total()).toBe(78.5);
    expect(justBelow.toFreeShipping()).toBe(3);

    const atThreshold = createCart();
    atThreshold.add({ id: 'b', name: 'B', price: 75, stock: 9 });
    expect(atThreshold.shipping()).toBe(0);
    expect(atThreshold.total()).toBe(75);
    expect(atThreshold.toFreeShipping()).toBe(0);

    const above = createCart();
    above.add({ id: 'c', name: 'C', price: 80, stock: 9 });
    expect(above.shipping()).toBe(0);
    expect(above.total()).toBe(80);
    expect(above.toFreeShipping()).toBe(0);
  });

  it('exposes lines as the live mutable array used by the cart', () => {
    const cart = createCart();
    cart.add(snake);
    expect(cart.lines.length).toBe(1);
    cart.lines.splice(0, 1);
    expect(cart.count()).toBe(0);
    expect(cart.subtotal()).toBe(0);
  });
});

import { describe, it, expect, beforeEach } from 'vitest';
import { mount } from '../src/app';
import { PLANTS } from '../src/catalog';

// Characterization tests for mount(root): they pin what the app does today,
// before the jQuery removal. Everything is driven through real DOM events.

function buttonByLight(root, light) {
  return root.querySelector(`.filters button[data-light="${light}"]`);
}

function cardIds(root) {
  return Array.from(root.querySelectorAll('.grid article.card')).map((c) => c.getAttribute('data-id'));
}

function activeLights(root) {
  return Array.from(root.querySelectorAll('.filters button.active')).map((b) => b.getAttribute('data-light'));
}

function cartCount(root) {
  return root.querySelector('.cart h2').textContent;
}

describe('mount', () => {
  let root;

  beforeEach(() => {
    document.body.innerHTML = '';
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  it('empties root and renders the shop shell with an h1 and subtitle', () => {
    root.innerHTML = '<p>stale</p>';
    const cart = mount(root);
    expect(cart).toBeTruthy();
    expect(root.textContent).not.toContain('stale');
    const shop = root.querySelector('.shop');
    expect(shop.tagName).toBe('DIV');
    const h1 = shop.querySelector('h1');
    expect(h1.childNodes[0].textContent).toBe('Fern & Folly');
    expect(h1.querySelector('small').textContent).toBe('Houseplants, delivered.');
  });

  it('renders main with filters, grid and a cart slot holding aside.cart', () => {
    mount(root);
    const main = root.querySelector('.shop > main');
    expect(main.tagName).toBe('MAIN');
    expect(main.querySelector('.filters').tagName).toBe('DIV');
    expect(main.querySelector('.grid').tagName).toBe('DIV');
    const slot = root.querySelector('.shop > main + div');
    expect(slot.querySelector('aside.cart').tagName).toBe('ASIDE');
  });

  it('renders the four filter buttons with their pinned labels', () => {
    mount(root);
    const buttons = root.querySelectorAll('.filters button');
    expect(buttons).toHaveLength(4);
    expect(Array.from(buttons).map((b) => b.textContent)).toEqual([
      'All',
      'low light',
      'medium light',
      'bright light',
    ]);
    expect(Array.from(buttons).map((b) => b.getAttribute('data-light'))).toEqual([
      'all',
      'low',
      'medium',
      'bright',
    ]);
  });

  it('marks only the all button active on mount and renders all six cards in PLANTS order', () => {
    mount(root);
    expect(activeLights(root)).toEqual(['all']);
    expect(buttonByLight(root, 'all').classList.contains('active')).toBe(true);
    expect(cardIds(root)).toEqual(PLANTS.map((p) => p.id));
  });

  it('switches to the low light filter and back to all', () => {
    mount(root);
    buttonByLight(root, 'low').click();
    expect(activeLights(root)).toEqual(['low']);
    expect(cardIds(root)).toEqual(['snake', 'pothos', 'zz']);
    buttonByLight(root, 'all').click();
    expect(activeLights(root)).toEqual(['all']);
    expect(cardIds(root)).toEqual(PLANTS.map((p) => p.id));
  });

  it('returns a cart whose lines array is driven by the Add buttons', () => {
    const cart = mount(root);
    expect(Array.isArray(cart.lines)).toBe(true);
    expect(cart.lines).toHaveLength(0);
    root.querySelector('.grid article.card[data-id="snake"] button.add').click();
    expect(cart.lines).toHaveLength(1);
    expect(cart.lines[0]).toEqual({ id: 'snake', name: 'Snake plant', price: 24, qty: 1 });
    root.querySelector('.grid article.card[data-id="snake"] button.add').click();
    expect(cart.lines[0].qty).toBe(2);
  });

  it('updates the cart panel heading after each Add', () => {
    mount(root);
    root.querySelector('.grid article.card[data-id="snake"] button.add').click();
    expect(cartCount(root)).toBe('Cart (1 plant)');
    root.querySelector('.grid article.card[data-id="snake"] button.add').click();
    expect(cartCount(root)).toBe('Cart (2 plants)');
  });

  it('stops adding monstera at its stock limit and disables the button', () => {
    const cart = mount(root);
    const card = () => root.querySelector('.grid article.card[data-id="monstera"]');
    for (let i = 0; i < 4; i++) card().querySelector('button.add').click();
    expect(cart.lines[0].qty).toBe(4);
    expect(cartCount(root)).toBe('Cart (4 plants)');
    const button = card().querySelector('button.add');
    expect(button.textContent).toBe('All in cart');
    expect(button.disabled).toBe(true);
    button.click();
    expect(cart.lines[0].qty).toBe(4);
    expect(cartCount(root)).toBe('Cart (4 plants)');
  });

  it('pins the sold-out pothos as a disabled Sold out button', () => {
    mount(root);
    const card = root.querySelector('.grid article.card[data-id="pothos"]');
    const button = card.querySelector('button.add');
    expect(button.textContent).toBe('Sold out');
    expect(button.disabled).toBe(true);
    expect(card.querySelector('.meta').textContent.endsWith('sold out')).toBe(true);
  });

  it('removes a line via button.remove and renders the empty panel again', () => {
    mount(root);
    const snakeCard = root.querySelector('.grid article.card[data-id="snake"]');
    snakeCard.querySelector('button.add').click();
    expect(cartCount(root)).toBe('Cart (1 plant)');
    root.querySelector('.cart li button.remove').click();
    expect(cartCount(root)).toBe('Cart (0 plants)');
    expect(root.querySelector('.cart p.empty').textContent).toBe('Your cart is empty.');
  });
});

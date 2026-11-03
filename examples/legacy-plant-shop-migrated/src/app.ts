// Wires the page together. mount(root) renders the shop into root (a DOM element) and returns the cart.
import { PLANTS, byLight } from './catalog';
import { createCart } from './cart';
import { plantCard, cartPanel } from './view';

export function mount(root: HTMLElement) {
  const cart = createCart();
  let light = 'all';
  root.replaceChildren();

  const shop = document.createElement('div');
  shop.className = 'shop';

  const heading = document.createElement('h1');
  heading.textContent = 'Fern & Folly';
  const subtitle = document.createElement('small');
  subtitle.textContent = 'Houseplants, delivered.';
  heading.append(subtitle);
  shop.append(heading);

  const main = document.createElement('main');
  const filters = document.createElement('div');
  filters.className = 'filters';
  ['all', 'low', 'medium', 'bright'].forEach(function (l) {
    const button = document.createElement('button');
    button.setAttribute('data-light', l);
    button.textContent = l === 'all' ? 'All' : l + ' light';
    filters.append(button);
  });

  const grid = document.createElement('div');
  grid.className = 'grid';
  const cartSlot = document.createElement('div');
  main.append(filters, grid);
  shop.append(main, cartSlot);
  root.append(shop);

  function inCart(id: string): number {
    const line = cart.lines.filter(function (l) { return l.id === id; })[0];
    return line ? line.qty : 0;
  }

  function render(): void {
    filters.querySelectorAll('button').forEach(function (button) {
      button.classList.toggle('active', button.getAttribute('data-light') === light);
    });
    grid.replaceChildren();
    byLight(PLANTS, light).forEach(function (p) { grid.append(plantCard(p, inCart(p.id))); });
    cartSlot.replaceChildren(cartPanel(cart));
  }

  filters.addEventListener('click', function (event) {
    const target = event.target;
    if (!(target instanceof Element)) return;
    const button = target.closest('button[data-light]');
    if (!button || !filters.contains(button)) return;
    const next = button.getAttribute('data-light');
    if (next === null) return;
    light = next;
    render();
  });

  grid.addEventListener('click', function (event) {
    const target = event.target;
    if (!(target instanceof Element)) return;
    const button = target.closest('.add');
    if (!button || !grid.contains(button)) return;
    const card = button.closest('[data-id]');
    const id = card ? card.getAttribute('data-id') : null;
    if (id === null) return;
    const plant = PLANTS.filter(function (p) { return p.id === id; })[0];
    if (plant) cart.add(plant);
  });

  cartSlot.addEventListener('click', function (event) {
    const target = event.target;
    if (!(target instanceof Element)) return;
    const button = target.closest('.remove');
    if (!button || !cartSlot.contains(button)) return;
    const line = button.closest('[data-id]');
    const id = line ? line.getAttribute('data-id') : null;
    if (id !== null) cart.remove(id);
  });

  cart.onChange(render);
  render();
  return cart;
}

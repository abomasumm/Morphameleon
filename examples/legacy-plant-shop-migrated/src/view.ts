// Rendering with native DOM APIs. Each function returns an HTMLElement.
import { money, plural } from './format';
import type { createCart } from './cart';

interface Plant {
  id: string;
  name: string;
  art: string;
  price: number;
  light: string;
  stock: number;
}

type Cart = ReturnType<typeof createCart>;

export function plantCard(plant: Plant, inCart: number): HTMLElement {
  const soldOut = plant.stock < 1;
  const full = inCart >= plant.stock;
  const card = document.createElement('article');
  card.className = 'card';
  card.setAttribute('data-id', plant.id);

  const art = document.createElement('div');
  art.className = 'art';
  art.textContent = plant.art;
  card.append(art);

  const name = document.createElement('h3');
  name.textContent = plant.name;
  card.append(name);

  const meta = document.createElement('div');
  meta.className = 'meta';
  meta.textContent = plant.light + ' light · ' + (soldOut ? 'sold out' : plant.stock + ' left');
  card.append(meta);

  const row = document.createElement('div');
  row.className = 'row';

  const price = document.createElement('strong');
  price.textContent = money(plant.price);
  row.append(price);

  const add = document.createElement('button');
  add.className = 'add';
  add.textContent = soldOut ? 'Sold out' : full ? 'All in cart' : 'Add';
  add.disabled = soldOut || full;
  row.append(add);

  card.append(row);
  return card;
}

export function cartPanel(cart: Cart): HTMLElement {
  const panel = document.createElement('aside');
  panel.className = 'cart';

  const heading = document.createElement('h2');
  heading.textContent = 'Cart (' + plural(cart.count(), 'plant') + ')';
  panel.append(heading);

  if (cart.lines.length === 0) {
    const empty = document.createElement('p');
    empty.className = 'empty';
    empty.textContent = 'Your cart is empty.';
    panel.append(empty);
    return panel;
  }

  const ul = document.createElement('ul');
  cart.lines.forEach(function (l) {
    const li = document.createElement('li');
    li.setAttribute('data-id', l.id);

    const description = document.createElement('span');
    description.textContent = l.qty + ' × ' + l.name;
    li.append(description);

    const lineTotal = document.createElement('span');
    lineTotal.textContent = money(l.price * l.qty);
    li.append(lineTotal);

    const remove = document.createElement('button');
    remove.className = 'remove';
    remove.setAttribute('aria-label', 'Remove ' + l.name);
    remove.textContent = '✕';
    li.append(remove);

    ul.append(li);
  });
  panel.append(ul);

  const totals = document.createElement('div');
  totals.className = 'totals';

  const subtotalRow = document.createElement('div');
  const subtotalLabel = document.createElement('span');
  subtotalLabel.textContent = 'Subtotal';
  const subtotalValue = document.createElement('span');
  subtotalValue.className = 'subtotal';
  subtotalValue.textContent = money(cart.subtotal());
  subtotalRow.append(subtotalLabel, subtotalValue);
  totals.append(subtotalRow);

  const shippingRow = document.createElement('div');
  const shippingLabel = document.createElement('span');
  shippingLabel.textContent = 'Shipping';
  const shippingValue = document.createElement('span');
  shippingValue.className = 'shipping';
  shippingValue.textContent = cart.shipping() ? money(cart.shipping()) : 'Free';
  shippingRow.append(shippingLabel, shippingValue);
  totals.append(shippingRow);

  const totalRow = document.createElement('div');
  totalRow.className = 'grand';
  const totalLabel = document.createElement('span');
  totalLabel.textContent = 'Total';
  const totalValue = document.createElement('span');
  totalValue.className = 'total';
  totalValue.textContent = money(cart.total());
  totalRow.append(totalLabel, totalValue);
  totals.append(totalRow);

  panel.append(totals);

  const left = cart.toFreeShipping();
  const pct = Math.min(100, Math.round((cart.subtotal() / 75) * 100));
  const ship = document.createElement('div');
  ship.className = 'ship';
  ship.textContent = left > 0 ? money(left) + ' more for free shipping' : 'You get free shipping';

  const bar = document.createElement('div');
  bar.className = 'bar';
  const barFill = document.createElement('span');
  barFill.style.width = pct + '%';
  bar.append(barFill);
  ship.append(bar);
  panel.append(ship);

  return panel;
}

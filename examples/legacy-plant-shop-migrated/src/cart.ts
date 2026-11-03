// Cart state. Mutates in place and calls every listener after a change.
const FREE_SHIPPING_AT = 75;
const SHIPPING = 6.5;

interface Plant {
  id: string;
  name: string;
  price: number;
  stock: number;
}

interface CartLine {
  id: string;
  name: string;
  price: number;
  qty: number;
}

interface Cart {
  lines: CartLine[];
  onChange(fn: () => void): void;
  add(plant: Plant): boolean;
  remove(id: string): void;
  count(): number;
  subtotal(): number;
  shipping(this: Cart): number;
  total(this: Cart): number;
  toFreeShipping(this: Cart): number;
}

export function createCart(): Cart {
  const lines: CartLine[] = [];
  const listeners: Array<() => void> = [];

  function notify() { listeners.forEach(function (fn) { fn(); }); }

  const cart: Cart = {
    lines: lines,
    onChange: function (fn: () => void) { listeners.push(fn); },
    add: function (plant: Plant) {
      const line = lines.filter(function (l) { return l.id === plant.id; })[0];
      if (line) {
        if (line.qty >= plant.stock) return false;
        line.qty++;
      } else {
        if (plant.stock < 1) return false;
        lines.push({ id: plant.id, name: plant.name, price: plant.price, qty: 1 });
      }
      notify();
      return true;
    },
    remove: function (id: string) {
      for (let i = 0; i < lines.length; i++) {
        if (lines[i].id === id) { lines.splice(i, 1); notify(); return; }
      }
    },
    count: function () { return lines.reduce(function (s, l) { return s + l.qty; }, 0); },
    subtotal: function () { return lines.reduce(function (s, l) { return s + l.price * l.qty; }, 0); },
    shipping: function (this: Cart) {
      const sub = this.subtotal();
      return sub === 0 || sub >= FREE_SHIPPING_AT ? 0 : SHIPPING;
    },
    total: function (this: Cart) { return this.subtotal() + this.shipping(); },
    toFreeShipping: function (this: Cart) { return Math.max(0, FREE_SHIPPING_AT - this.subtotal()); }
  };

  return cart;
}

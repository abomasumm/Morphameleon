// Cart state. Mutates in place and calls every listener after a change.
var FREE_SHIPPING_AT = 75;
var SHIPPING = 6.5;

export function createCart() {
  var lines = [];
  var listeners = [];

  function notify() { listeners.forEach(function (fn) { fn(); }); }

  return {
    lines: lines,
    onChange: function (fn) { listeners.push(fn); },
    add: function (plant) {
      var line = lines.filter(function (l) { return l.id === plant.id; })[0];
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
    remove: function (id) {
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].id === id) { lines.splice(i, 1); notify(); return; }
      }
    },
    count: function () { return lines.reduce(function (s, l) { return s + l.qty; }, 0); },
    subtotal: function () { return lines.reduce(function (s, l) { return s + l.price * l.qty; }, 0); },
    shipping: function () {
      var sub = this.subtotal();
      return sub === 0 || sub >= FREE_SHIPPING_AT ? 0 : SHIPPING;
    },
    total: function () { return this.subtotal() + this.shipping(); },
    toFreeShipping: function () { return Math.max(0, FREE_SHIPPING_AT - this.subtotal()); }
  };
}

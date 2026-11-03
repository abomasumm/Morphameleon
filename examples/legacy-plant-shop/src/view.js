// Rendering with jQuery. Each function returns a jQuery element.
import $ from 'jquery';
import { money, plural } from './format';

export function plantCard(plant, inCart) {
  var soldOut = plant.stock < 1;
  var full = inCart >= plant.stock;
  var $card = $('<article class="card"></article>').attr('data-id', plant.id);
  $card.append($('<div class="art"></div>').text(plant.art));
  $card.append($('<h3></h3>').text(plant.name));
  $card.append($('<div class="meta"></div>').text(plant.light + ' light · ' + (soldOut ? 'sold out' : plant.stock + ' left')));
  var $row = $('<div class="row"></div>');
  $row.append($('<strong></strong>').text(money(plant.price)));
  $row.append($('<button class="add"></button>').text(soldOut ? 'Sold out' : full ? 'All in cart' : 'Add').prop('disabled', soldOut || full));
  return $card.append($row);
}

export function cartPanel(cart) {
  var $panel = $('<aside class="cart"></aside>');
  $panel.append($('<h2></h2>').text('Cart (' + plural(cart.count(), 'plant') + ')'));
  if (cart.lines.length === 0) {
    $panel.append('<p class="empty">Your cart is empty.</p>');
    return $panel;
  }
  var $ul = $('<ul></ul>');
  cart.lines.forEach(function (l) {
    var $li = $('<li></li>').attr('data-id', l.id);
    $li.append($('<span></span>').text(l.qty + ' × ' + l.name));
    $li.append($('<span></span>').text(money(l.price * l.qty)));
    $li.append($('<button class="remove" aria-label="Remove ' + l.name + '">✕</button>'));
    $ul.append($li);
  });
  $panel.append($ul);
  var $totals = $('<div class="totals"></div>');
  $totals.append($('<div><span>Subtotal</span><span class="subtotal"></span></div>').find('.subtotal').text(money(cart.subtotal())).end());
  $totals.append($('<div><span>Shipping</span><span class="shipping"></span></div>').find('.shipping').text(cart.shipping() ? money(cart.shipping()) : 'Free').end());
  $totals.append($('<div class="grand"><span>Total</span><span class="total"></span></div>').find('.total').text(money(cart.total())).end());
  $panel.append($totals);
  var left = cart.toFreeShipping();
  var pct = Math.min(100, Math.round((cart.subtotal() / 75) * 100));
  var $ship = $('<div class="ship"></div>').text(left > 0 ? money(left) + ' more for free shipping' : 'You get free shipping');
  $ship.append($('<div class="bar"><span></span></div>').find('span').css('width', pct + '%').end());
  return $panel.append($ship);
}

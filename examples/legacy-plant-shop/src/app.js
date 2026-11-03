// Wires the page together. mount(root) renders the shop into root (a DOM element) and returns the cart.
import $ from 'jquery';
import { PLANTS, byLight } from './catalog';
import { createCart } from './cart';
import { plantCard, cartPanel } from './view';

export function mount(root) {
  var cart = createCart();
  var light = 'all';
  var $root = $(root).empty();
  var $shop = $('<div class="shop"><h1>Fern &amp; Folly<small>Houseplants, delivered.</small></h1></div>');
  var $main = $('<main></main>');
  var $filters = $('<div class="filters"></div>');
  ['all', 'low', 'medium', 'bright'].forEach(function (l) {
    $filters.append($('<button></button>').attr('data-light', l).text(l === 'all' ? 'All' : l + ' light'));
  });
  var $grid = $('<div class="grid"></div>');
  var $cartSlot = $('<div></div>');
  $main.append($filters, $grid);
  $shop.append($main, $cartSlot);
  $root.append($shop);

  function inCart(id) {
    var line = cart.lines.filter(function (l) { return l.id === id; })[0];
    return line ? line.qty : 0;
  }

  function render() {
    $filters.find('button').each(function () { $(this).toggleClass('active', $(this).attr('data-light') === light); });
    $grid.empty();
    byLight(PLANTS, light).forEach(function (p) { $grid.append(plantCard(p, inCart(p.id))); });
    $cartSlot.empty().append(cartPanel(cart));
  }

  $filters.on('click', 'button', function () { light = $(this).attr('data-light'); render(); });
  $grid.on('click', '.add', function () {
    var id = $(this).closest('.card').attr('data-id');
    cart.add(PLANTS.filter(function (p) { return p.id === id; })[0]);
  });
  $cartSlot.on('click', '.remove', function () { cart.remove($(this).closest('li').attr('data-id')); });
  cart.onChange(render);
  render();
  return cart;
}

// The plants we sell. stock 0 means sold out.
export var PLANTS = [
  { id: 'monstera', name: 'Monstera', art: '🪴', price: 38, light: 'bright', stock: 4 },
  { id: 'snake', name: 'Snake plant', art: '🌵', price: 24, light: 'low', stock: 9 },
  { id: 'pothos', name: 'Golden pothos', art: '🌿', price: 16.5, light: 'low', stock: 0 },
  { id: 'fiddle', name: 'Fiddle-leaf fig', art: '🌳', price: 64, light: 'bright', stock: 2 },
  { id: 'calathea', name: 'Calathea', art: '🍃', price: 29.99, light: 'medium', stock: 5 },
  { id: 'zz', name: 'ZZ plant', art: '🌱', price: 21, light: 'low', stock: 7 }
];

export function byLight(plants, light) {
  if (!light || light === 'all') return plants.slice();
  return plants.filter(function (p) { return p.light === light; });
}

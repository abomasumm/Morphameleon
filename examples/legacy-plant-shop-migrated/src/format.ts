// Formatting helpers. Prices are plain numbers in dollars.

export function money(n: number): string {
  return '$' + (Math.round(n * 100) / 100).toFixed(2);
}

export function plural(n: number, word: string): string {
  return n + ' ' + (n === 1 ? word : word + 's');
}

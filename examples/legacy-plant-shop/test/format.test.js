import { describe, it, expect } from 'vitest';
import { money, plural } from '../src/format';

describe('format', () => {
  it('formats money with two decimals', () => {
    expect(money(16.5)).toBe('$16.50');
    expect(money(29.99 * 3)).toBe('$89.97');
    expect(money(0)).toBe('$0.00');
  });
  it('pluralizes', () => {
    expect(plural(1, 'plant')).toBe('1 plant');
    expect(plural(3, 'plant')).toBe('3 plants');
    expect(plural(0, 'plant')).toBe('0 plants');
  });
});

import { describe, it, expect, vi, beforeEach } from 'vitest';

// Characterization tests for src/main.js: it has no tests, so these pin what
// it does today — importing it calls mount once with the #app element.

vi.mock('../src/app', () => ({ mount: vi.fn() }));

describe('main', () => {
  let mount;

  beforeEach(async () => {
    vi.resetModules();
    mount = (await import('../src/app')).mount;
    mount.mockClear();
    document.body.innerHTML = '<div id="app"></div>';
  });

  it('calls mount with the #app element on import', async () => {
    await import('../src/main');
    expect(mount).toHaveBeenCalledTimes(1);
    const arg = mount.mock.calls[0][0];
    expect(arg).toBe(document.getElementById('app'));
    expect(arg instanceof HTMLElement).toBe(true);
    expect(arg.id).toBe('app');
  });
});

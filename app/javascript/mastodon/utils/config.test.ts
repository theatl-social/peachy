import { beforeEach, describe, expect, it, vi } from 'vitest';

/* `assetHost` is populated as a module side effect: the module asks `ready()`
   to read `<meta name="cdn-host">` as soon as the document is interactive. Each
   case therefore has to reset the module registry and rebuild the document head
   before importing, otherwise the first import's value leaks into the rest.

   This is the browser end of CDN_HOST. It is fed by the meta tag that Rails only
   renders when `config.asset_host` is set, so it silently falls back to
   same-origin whenever the runtime half of CDN_HOST is missing -- which is the
   regression these cases exist to catch. */
const importConfig = async () => import('./config');

describe('assetHost', () => {
  beforeEach(() => {
    vi.resetModules();
    document.head.innerHTML = '';
  });

  it('is empty when no cdn-host meta tag is present', async () => {
    const { assetHost } = await importConfig();

    expect(assetHost).toBe('');
  });

  it('reads the host from the cdn-host meta tag', async () => {
    document.head.innerHTML =
      '<meta name="cdn-host" content="https://cdn.example.com">';

    const { assetHost } = await importConfig();

    expect(assetHost).toBe('https://cdn.example.com');
  });

  it('is empty when the meta tag carries no content', async () => {
    document.head.innerHTML = '<meta name="cdn-host" content="">';

    const { assetHost } = await importConfig();

    expect(assetHost).toBe('');
  });

  it('builds same-origin URLs when no CDN is configured', async () => {
    const { assetHost } = await importConfig();

    // Mirrors how callers use it, e.g. the sounds middleware and emoji renderer.
    expect(`${assetHost}/sounds/boop.ogg`).toBe('/sounds/boop.ogg');
  });

  it('builds CDN URLs when a CDN is configured', async () => {
    document.head.innerHTML =
      '<meta name="cdn-host" content="https://cdn.example.com">';

    const { assetHost } = await importConfig();

    expect(`${assetHost}/sounds/boop.ogg`).toBe(
      'https://cdn.example.com/sounds/boop.ogg',
    );
  });
});

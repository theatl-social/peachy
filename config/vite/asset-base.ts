/* Resolving the CDN asset base lives in its own module rather than inline in
   `vite.config.mts` so it can be reasoned about (and exercised) on its own: the
   config factory is async and instantiates every plugin, which makes the one
   line that actually decides asset URLs hard to see and harder to check.

   Note that this only covers the *build-time* half of `CDN_HOST`. Vite bakes
   this base into CSS `url()`, the JS chunk loader, `manifest.json` and the
   service worker's chunk imports. The runtime half -- Rails' `asset_host`, the
   CSP allow-list and the `<meta name="cdn-host">` tag the front-end reads -- is
   driven separately from `ENV['CDN_HOST']` at boot. Both must be set to the
   same value for a CDN deploy to be coherent. */

import type { Plugin } from 'vite';

export interface AssetBaseOptions {
  cdnHost: string | null | undefined;
  outDirName: string;
  isProdBuild: boolean;
}

/* The single definition of what a normalised CDN host looks like. Both the base
   and the value recorded for the runtime check must agree on this: if the
   recorded host keeps a trailing slash the base has stripped, CdnHostCheck sees
   a mismatch between a host and itself and warns on every boot. */
export function normalizeCdnHost(
  cdnHost: string | null | undefined,
): string | null {
  const host = cdnHost?.trim();

  // Vite concatenates `base` with asset paths, so a trailing slash on CDN_HOST
  // would yield `https://cdn.example.com//packs/`. Most CDNs serve that, but it
  // breaks cache keys and any exact-match origin rule.
  return host ? host.replace(/\/+$/, '') : null;
}

export function resolveAssetBase({
  cdnHost,
  outDirName,
  isProdBuild,
}: AssetBaseOptions): string {
  const host = normalizeCdnHost(cdnHost);

  // Only production builds emit absolute URLs. The dev server serves assets
  // itself, so a CDN base there would point at stale (or absent) files.
  if (!isProdBuild || !host) {
    return `/${outDirName}/`;
  }

  return `${host}/${outDirName}/`;
}

/* Record what the assets were actually compiled against, so the running app can
   notice when its own CDN_HOST disagrees.

   Nothing else in the build output carries this. Vite's manifest stores output
   paths relative to the out dir, not URLs, so it looks identical whether or not
   a CDN was configured; only compiled CSS `url()` values embed the host, and
   parsing those at boot would be both slow and brittle. A single small file is
   cheaper and unambiguous. */

const ASSET_BASE_FILENAME = '.vite/asset-base.json';

export interface RecordedAssetBase {
  base: string;
  cdnHost: string | null;
}

export function RecordAssetBase(recorded: RecordedAssetBase): Plugin {
  return {
    name: 'mastodon-record-asset-base',
    apply: 'build',
    applyToEnvironment(environment) {
      // Emit only alongside the manifest, so this runs once rather than for
      // every build environment. Mirrors MastodonAssetsManifest.
      return !!environment.config.build.manifest;
    },
    generateBundle() {
      this.emitFile({
        fileName: ASSET_BASE_FILENAME,
        type: 'asset',
        source: `${JSON.stringify(recorded, null, 2)}\n`,
      });
    },
  };
}

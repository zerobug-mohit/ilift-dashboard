/**
 * Reading from a published snapshot instead of a live API.
 *
 * A snapshot is a directory of JSON files, one per view, produced by
 * `backend/scripts/export_static.R`. There is no server: the dashboard is
 * static files, and the raw programme data never left the machine that
 * published it.
 *
 * Every endpoint the live client calls has a file equivalent, so the query
 * hooks in client.ts are unchanged — only where the bytes come from differs.
 * The export writes with the same serializer settings the API uses, so the
 * payloads are byte-identical and nothing downstream can tell them apart.
 */

/** Set at build time by the publish script. */
export const IS_STATIC = (import.meta.env.VITE_DATA_MODE as string | undefined) === 'static'

/** Where the snapshot lives, relative to the page. */
const DATA_ROOT = `${import.meta.env.BASE_URL ?? '/'}data`.replace(/\/{2,}/g, '/')

/**
 * Map an API path + query onto a snapshot file.
 *
 * Must stay in step with range_key() in export_static.R — the two halves of
 * this contract are the filename, and they are written in different languages.
 * Returns null for paths a snapshot cannot answer.
 */
export function snapshotUrl(path: string, params?: Record<string, string>): string | null {
  const from = params?.from ?? ''
  const to = params?.to ?? ''
  const gender = params?.gender ?? 'all'
  const key = `${from}__${to}__${gender}`

  switch (path) {
    case '/meta':
      return `${DATA_ROOT}/manifest.json`
    case '/metrics':
      return `${DATA_ROOT}/metrics/${key}.json`
    case '/nns':
      return `${DATA_ROOT}/nns/${key}.json`
    case '/weekly':
      // No gender dimension: weekly_for_range() takes from/to only.
      return `${DATA_ROOT}/weekly/${from}__${to}.json`
    case '/health':
      return `${DATA_ROOT}/manifest.json`
    default:
      return null
  }
}

/** Write endpoints have no meaning in a snapshot. */
export function isWritePath(path: string): boolean {
  return path === '/upload' || path === '/refresh'
}

export class SnapshotError extends Error {}

/**
 * The manifest, fetched once per page load and shared by every caller.
 *
 * Deliberately revalidated (`no-cache`, not `no-store`): the browser still
 * sends a conditional request and takes a 304 when nothing has changed, so
 * this stays cheap while never serving a stale copy. It is the one file that
 * must be current, because everything else is versioned from it.
 */
let manifestPromise: Promise<Record<string, unknown> | null> | null = null

function loadManifest(): Promise<Record<string, unknown> | null> {
  if (!manifestPromise) {
    manifestPromise = fetch(`${DATA_ROOT}/manifest.json`, { cache: 'no-cache' })
      .then((r) => (r.ok ? r.json() : null))
      .catch(() => null)
  }
  return manifestPromise
}

/**
 * A stamp that changes whenever the snapshot is republished.
 *
 * Data files keep stable names, so a browser that has seen
 * `weekly/2025-07__2025-08.json` will happily serve yesterday's copy after a
 * refresh — the figures change but the reader still sees the old ones, which
 * is the one thing a dashboard must not do. Appending the publish time makes
 * each new snapshot a URL the browser has never seen, while leaving caching
 * fully effective between publishes.
 *
 * The page URL is untouched: this is added by the page to its own background
 * requests, so links and bookmarks keep working unchanged.
 */
async function snapshotVersion(): Promise<string | null> {
  const m = await loadManifest()
  const stamp = (m?.generated_at ?? m?.loaded_at) as string | undefined
  return stamp ? encodeURIComponent(stamp) : null
}

/**
 * Fetch one snapshot file.
 *
 * A 404 here is worth distinguishing from a network failure: it means the
 * requested combination was not exported, which is a stale-or-incomplete
 * snapshot rather than a connectivity problem.
 */
export async function fetchSnapshot<T>(path: string, params?: Record<string, string>): Promise<T> {
  if (isWritePath(path)) {
    throw new SnapshotError(
      'This is a published snapshot, so the data cannot be changed from here. ' +
      'New figures appear when whoever maintains the dataset publishes again.',
    )
  }

  // The manifest is what supplies the version, so it cannot itself be
  // versioned. Serving it from the shared promise also means one fetch rather
  // than two for the request that triggers the page's first render.
  if (path === '/meta' || path === '/health') {
    const m = await loadManifest()
    if (!m) throw new SnapshotError('Could not load the published data.')
    return m as T
  }

  const base = snapshotUrl(path, params)
  if (!base) throw new SnapshotError(`No published data for ${path}`)

  // No stamp (an older snapshot, or a manifest that failed to load) simply
  // means no cache-busting — the previous behaviour, rather than a broken page.
  const version = await snapshotVersion()
  const url = version ? `${base}?v=${version}` : base

  let res: Response
  try {
    res = await fetch(url)
  } catch (e) {
    throw new SnapshotError(`Could not load ${base}. The published data may be incomplete.`)
  }

  if (res.status === 404) {
    throw new SnapshotError(
      `This combination of months and gender is not in the published snapshot. ` +
      `It may have been published from a shorter reporting period.`,
    )
  }
  if (!res.ok) {
    throw new SnapshotError(`Failed to load published data (${res.status}).`)
  }

  return (await res.json()) as T
}

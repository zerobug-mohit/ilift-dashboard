/**
 * Client-side credential storage.
 *
 * One secret is held at a time. Whether it grants viewing or also uploading is
 * decided by the server and reported back on /api/meta as `auth.level`, so the
 * UI never has to guess which kind of secret was entered — the same box accepts
 * the team password or the admin token.
 *
 * Stored in localStorage, which means it persists across reloads and is
 * readable by any script running on this origin. That is an accepted trade for
 * a shared team password on a single-purpose page; it is not a substitute for
 * per-user accounts, and the README says so.
 */

const KEY = 'ilift.credential'

export type AuthLevel = 'admin' | 'viewer' | 'anonymous'

export function getCredential(): string {
  return localStorage.getItem(KEY) ?? ''
}

export function setCredential(secret: string): void {
  const t = secret.trim()
  if (t) localStorage.setItem(KEY, t)
  else localStorage.removeItem(KEY)
}

export function clearCredential(): void {
  localStorage.removeItem(KEY)
}

export function hasCredential(): boolean {
  return getCredential().length > 0
}

/** Authorization header, or nothing when no credential is stored. */
export function authHeaders(): Record<string, string> {
  const c = getCredential()
  return c ? { Authorization: `Bearer ${c}` } : {}
}

/**
 * Where the API lives.
 *
 * Three deployments, three answers:
 *
 *  - `npm run dev`      → "/api", proxied to the backend by Vite (same origin).
 *  - built and served
 *    alongside the API  → "/api", same origin.
 *  - built and hosted
 *    on GitHub Pages    → an absolute URL to the viewer's own machine,
 *                         because the backend runs locally, not on Pages.
 *
 * The Pages case needs a runtime value rather than a build-time one: the page
 * is served from github.io but must talk to 127.0.0.1, and different people may
 * run the backend on different ports. So the URL is stored in localStorage and
 * editable from the UI.
 *
 * MIXED CONTENT: a page served over HTTPS calling http://… is normally blocked.
 * `localhost` and `127.0.0.1` are exempt — the spec treats them as potentially
 * trustworthy — and Chrome and Edge implement that exemption. Firefox and
 * Safari are stricter and may block it. See README.
 */

const STORAGE_KEY = 'ilift.apiBase'

/** Build-time default, settable via VITE_API_BASE at build time. */
const BUILD_DEFAULT = (import.meta.env.VITE_API_BASE as string | undefined) ?? ''

/** True when the page is served by Vite dev or from the same origin as the API. */
const isSameOriginDeployment = (): boolean => {
  if (BUILD_DEFAULT) return false
  const h = window.location.hostname
  return h === 'localhost' || h === '127.0.0.1' || h === ''
}

export const DEFAULT_LOCAL_API = 'http://127.0.0.1:8000'

/** Normalise a user-entered URL to an origin with no trailing slash. */
export function normaliseBase(input: string): string {
  const t = input.trim().replace(/\/+$/, '')
  if (!t) return ''
  if (t === '/api') return t
  const withScheme = /^https?:\/\//i.test(t) ? t : `http://${t}`
  return withScheme.replace(/\/api$/, '')
}

/** Current API root, e.g. "/api" or "http://127.0.0.1:8000/api". */
export function getApiBase(): string {
  const stored = localStorage.getItem(STORAGE_KEY)
  if (stored) return `${normaliseBase(stored)}/api`

  if (BUILD_DEFAULT) return `${normaliseBase(BUILD_DEFAULT)}/api`
  if (isSameOriginDeployment()) return '/api'

  // Hosted somewhere else (GitHub Pages): the backend is on the viewer's machine
  return `${DEFAULT_LOCAL_API}/api`
}

/** True when requests go to this page's own origin (dev proxy, or co-hosted). */
export function isProxied(): boolean {
  return getApiBase() === '/api'
}

/**
 * The origin part, for display and for the settings field.
 * Under the dev proxy there is no separate origin to show, so this reports the
 * backend the proxy forwards to rather than the page's own address — showing
 * `localhost:5173` there reads as "the backend is on 5173", which it is not.
 */
export function getApiOrigin(): string {
  const base = getApiBase()
  if (base === '/api') return DEFAULT_LOCAL_API
  return base.replace(/\/api$/, '')
}

/** Has the user pinned an explicit API URL? */
export function hasExplicitBase(): boolean {
  return localStorage.getItem(STORAGE_KEY) !== null
}

export function setApiBase(url: string): void {
  const n = normaliseBase(url)
  if (n) localStorage.setItem(STORAGE_KEY, n)
  else localStorage.removeItem(STORAGE_KEY)
}

export function clearApiBase(): void {
  localStorage.removeItem(STORAGE_KEY)
}

/** True when the page is HTTPS but the API is plain HTTP on a non-local host. */
export function hasMixedContentRisk(): boolean {
  if (window.location.protocol !== 'https:') return false
  const base = getApiBase()
  if (base.startsWith('/')) return false
  try {
    const u = new URL(base)
    if (u.protocol === 'https:') return false
    // localhost and 127.0.0.1 are exempt from mixed-content blocking
    return !['localhost', '127.0.0.1', '::1', '[::1]'].includes(u.hostname)
  } catch {
    return false
  }
}

/** True when this page is hosted remotely and expects a local backend. */
export function isRemoteHostedWithLocalApi(): boolean {
  const h = window.location.hostname
  if (h === 'localhost' || h === '127.0.0.1' || h === '') return false
  const base = getApiBase()
  return base.includes('127.0.0.1') || base.includes('localhost')
}

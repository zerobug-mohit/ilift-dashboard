import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { getApiBase } from './base'
import { authHeaders } from './auth'
import { IS_STATIC, fetchSnapshot } from './staticSource'
import type {
  Gender, MetaResponse, MetricsResponse, NnsResponse, WeeklyResponse,
  SputumResponse, UploadResponse, UploadSlot,
} from './types'

class HttpError extends Error {
  constructor(public status: number, message: string, public body?: unknown) {
    super(message)
  }
}

/** A failed fetch (backend not running, blocked, offline) rather than an HTTP error. */
export class ConnectionError extends Error {
  constructor(public apiBase: string, cause?: unknown) {
    super(
      `Could not reach the API at ${apiBase}. ` +
      `Check the backend is running (npm run dev:api).`,
    )
    this.cause = cause
  }
}

/** 401 — no credential, or the wrong one. */
export class AuthError extends Error {
  constructor(message: string) { super(message) }
}

/** 403 — a valid viewer credential, but this action needs admin. */
export class ForbiddenError extends Error {
  constructor(message: string) { super(message) }
}

async function request<T>(path: string, init?: RequestInit, params?: Record<string, string>): Promise<T> {
  // A published snapshot answers from files. Diverting here rather than in each
  // hook keeps every caller identical between the two modes.
  if (IS_STATIC) return fetchSnapshot<T>(path, params)

  const base = getApiBase()
  const qs = params ? `?${new URLSearchParams(params)}` : ''

  let res: Response
  try {
    res = await fetch(`${base}${path}${qs}`, {
      ...init,
      headers: { ...authHeaders(), ...(init?.headers ?? {}) },
    })
  } catch (e) {
    // Network-level failure: server down, CORS refused, mixed content blocked
    throw new ConnectionError(base, e)
  }

  const body = await res.json().catch(() => null)
  const msg = (body as { message?: string })?.message ?? res.statusText

  if (res.status === 401) throw new AuthError(msg)
  if (res.status === 403 && (body as { error?: string })?.error === 'forbidden') {
    throw new ForbiddenError(msg)
  }

  if (!res.ok && res.status !== 207) {
    // The backend returns { error, message } on 4xx/503
    throw new HttpError(res.status, msg, body)
  }
  return body as T
}

const get = <T,>(path: string, params?: Record<string, string>) =>
  request<T>(path, undefined, params)

export interface Filters {
  from: string
  to: string
  gender: Gender
}

const filterParams = (f: Filters) => ({ from: f.from, to: f.to, gender: f.gender })

/**
 * A range is only fetchable once both ends are known.
 *
 * On first render the filters are still empty, and firing then asked for
 * `metrics/____all.json` — a 404 on every page load, and in the snapshot build
 * a request that could never succeed. The real request follows a moment later
 * once the months arrive.
 */
const hasRange = (f: Filters) => Boolean(f.from) && Boolean(f.to)

export function useMeta() {
  return useQuery({
    queryKey: ['meta'],
    queryFn: () => get<MetaResponse>('/meta'),
    // Poll so a file dropped into data/incoming/ is noticed without a reload.
    // A published snapshot cannot change under us, so don't poll it.
    refetchInterval: IS_STATIC ? false : 30_000,
    retry: false,
  })
}

export function useMetrics(f: Filters, enabled = true) {
  return useQuery({
    queryKey: ['metrics', f.from, f.to, f.gender],
    queryFn: () => get<MetricsResponse>('/metrics', filterParams(f)),
    enabled: enabled && hasRange(f),
    placeholderData: (prev) => prev,   // keep the old numbers visible while refetching
    retry: false,
  })
}

export function useNns(f: Filters, enabled = true) {
  return useQuery({
    queryKey: ['nns', f.from, f.to, f.gender],
    queryFn: () => get<NnsResponse>('/nns', filterParams(f)),
    enabled: enabled && hasRange(f),
    placeholderData: (prev) => prev,
    retry: false,
  })
}

export function useWeekly(f: Filters, enabled = true) {
  return useQuery({
    queryKey: ['weekly', f.from, f.to],
    queryFn: () => get<WeeklyResponse>('/weekly', { from: f.from, to: f.to }),
    enabled: enabled && hasRange(f),
    placeholderData: (prev) => prev,
    retry: false,
  })
}

export function useSputum(f: Filters, enabled = true) {
  return useQuery({
    queryKey: ['sputum', f.from, f.to, f.gender],
    queryFn: () => get<SputumResponse>('/sputum', filterParams(f)),
    enabled: enabled && hasRange(f),
    placeholderData: (prev) => prev,
    retry: false,
  })
}

/** Force the backend to re-read data/incoming/ and drop every cached result. */
export function useRefresh() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () => request<unknown>('/refresh', { method: 'POST' }),
    onSuccess: () => qc.invalidateQueries(),
  })
}

/**
 * Upload source workbooks. Writes them into the backend's data/incoming/
 * folder and triggers a recompute — the same effect as dropping the files in
 * by hand and clicking Refresh.
 */
export function useUpload() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ slot, files }: { slot: UploadSlot; files: File[] }) => {
      const fd = new FormData()
      files.forEach((f, i) => fd.append(`file${i}`, f, f.name))
      return request<UploadResponse>('/upload', { method: 'POST', body: fd }, { slot })
    },
    onSuccess: () => qc.invalidateQueries(),
  })
}

export { HttpError }

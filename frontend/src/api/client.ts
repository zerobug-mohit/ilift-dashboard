import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { getApiBase } from './base'
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

async function request<T>(path: string, init?: RequestInit, params?: Record<string, string>): Promise<T> {
  const base = getApiBase()
  const qs = params ? `?${new URLSearchParams(params)}` : ''

  let res: Response
  try {
    res = await fetch(`${base}${path}${qs}`, init)
  } catch (e) {
    // Network-level failure: server down, CORS refused, mixed content blocked
    throw new ConnectionError(base, e)
  }

  const body = await res.json().catch(() => null)

  if (!res.ok && res.status !== 207) {
    // The backend returns { error, message } on 4xx/503
    const msg = (body as { message?: string })?.message ?? res.statusText
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

export function useMeta() {
  return useQuery({
    queryKey: ['meta'],
    queryFn: () => get<MetaResponse>('/meta'),
    // Poll so a file dropped into data/incoming/ is noticed without a reload.
    refetchInterval: 30_000,
    retry: false,
  })
}

export function useMetrics(f: Filters, enabled = true) {
  return useQuery({
    queryKey: ['metrics', f.from, f.to, f.gender],
    queryFn: () => get<MetricsResponse>('/metrics', filterParams(f)),
    enabled,
    placeholderData: (prev) => prev,   // keep the old numbers visible while refetching
    retry: false,
  })
}

export function useNns(f: Filters, enabled = true) {
  return useQuery({
    queryKey: ['nns', f.from, f.to, f.gender],
    queryFn: () => get<NnsResponse>('/nns', filterParams(f)),
    enabled,
    placeholderData: (prev) => prev,
    retry: false,
  })
}

export function useWeekly(f: Filters, enabled = true) {
  return useQuery({
    queryKey: ['weekly', f.from, f.to],
    queryFn: () => get<WeeklyResponse>('/weekly', { from: f.from, to: f.to }),
    enabled,
    placeholderData: (prev) => prev,
    retry: false,
  })
}

export function useSputum(f: Filters, enabled = true) {
  return useQuery({
    queryKey: ['sputum', f.from, f.to, f.gender],
    queryFn: () => get<SputumResponse>('/sputum', filterParams(f)),
    enabled,
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

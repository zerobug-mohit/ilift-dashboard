import { useCallback, useEffect, useState } from 'react'
import type { Filters } from '../api/client'
import type { Gender } from '../api/types'

/**
 * Filter state synced to the URL query string, so a filtered view can be
 * shared as a link. The legacy dashboard held this in module-level JS
 * variables (build_v3.py fmth/tmth/gfilt), which made views unshareable.
 */

const isGender = (v: string | null): v is Gender => v === 'all' || v === 'F' || v === 'M'

function readUrl(): Partial<Filters> {
  const p = new URLSearchParams(window.location.search)
  const out: Partial<Filters> = {}
  // Only set keys that are actually present — an explicit `undefined` would
  // overwrite the default when this object is spread.
  const from = p.get('from')
  const to = p.get('to')
  const g = p.get('gender')
  if (from) out.from = from
  if (to) out.to = to
  if (isGender(g)) out.gender = g
  return out
}

function writeUrl(f: Filters, defaults: Filters) {
  const p = new URLSearchParams(window.location.search)
  const set = (k: keyof Filters) => {
    if (f[k] && f[k] !== defaults[k]) p.set(k, f[k])
    else p.delete(k)
  }
  set('from'); set('to'); set('gender')
  const qs = p.toString()
  window.history.replaceState(null, '', qs ? `?${qs}` : window.location.pathname)
}

/**
 * @param months  available months from /api/meta, ascending "YYYY-MM"
 */
export function useFilters(months: string[]) {
  const defaults: Filters = {
    from: months[0] ?? '',
    to: months[months.length - 1] ?? '',
    gender: 'all',
  }

  const [filters, setFilters] = useState<Filters>(() => ({ ...defaults, ...readUrl() }))

  // Once months arrive, fill in any bound not supplied by the URL.
  useEffect(() => {
    if (months.length === 0) return
    setFilters((f) => ({
      from: f.from || months[0],
      to: f.to || months[months.length - 1],
      gender: f.gender,
    }))
  }, [months.join(',')])

  useEffect(() => {
    if (months.length > 0) writeUrl(filters, defaults)
  }, [filters.from, filters.to, filters.gender, months.length])

  const update = useCallback((patch: Partial<Filters>) => {
    setFilters((f) => {
      const next = { ...f, ...patch }
      // Keep the range ordered if the user picks an end before the start
      if (next.from && next.to && next.from > next.to) {
        if (patch.from) next.to = next.from
        else next.from = next.to
      }
      return next
    })
  }, [])

  const reset = useCallback(() => setFilters(defaults), [defaults.from, defaults.to])

  const isDefault =
    filters.from === defaults.from && filters.to === defaults.to && filters.gender === 'all'

  /** Months inside the active range — used to slice monthly series for charts. */
  const activeMonths = months.filter((m) => m >= filters.from && m <= filters.to)

  return { filters, update, reset, isDefault, activeMonths, defaults }
}

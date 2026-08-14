import type { Filters } from '../api/client'
import type { MetricsResponse, MetricMap } from '../api/types'

export interface TabProps {
  filters: Filters
  months: string[]
}

/** Safe metric lookup — a missing key reads 0 rather than undefined. */
export const m = (map: MetricMap | undefined, key: string): number =>
  Number(map?.[key] ?? 0)

/** Monthly series for one metric key, aligned to the given month list. */
export function series(res: MetricsResponse, key: string, months: string[]): number[] {
  return months.map((mo) => Number(res.monthly?.[mo]?.[key] ?? 0))
}

/** Build monthly table rows: [label, total, ...monthly values]. */
export interface MonthlyRow {
  label: string
  total: number | string
  values: (number | string)[]
  /** Rendered as a shaded sub-total row. */
  emphasis?: boolean
}

export function monthlyRow(
  res: MetricsResponse,
  months: string[],
  label: string,
  key: string,
  emphasis = false,
): MonthlyRow {
  return {
    label,
    total: m(res.total, key),
    values: series(res, key, months),
    emphasis,
  }
}

/** Percentage row derived from two metric keys. */
export function pctRow(
  res: MetricsResponse,
  months: string[],
  label: string,
  numKey: string,
  denKey: string,
): MonthlyRow {
  const p = (num: number, den: number) => (den ? `${((num / den) * 100).toFixed(1)}%` : '—')
  return {
    label,
    total: p(m(res.total, numKey), m(res.total, denKey)),
    values: months.map((mo) =>
      p(Number(res.monthly?.[mo]?.[numKey] ?? 0), Number(res.monthly?.[mo]?.[denKey] ?? 0)),
    ),
  }
}

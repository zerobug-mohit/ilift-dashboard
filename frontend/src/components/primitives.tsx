import type { ReactNode } from 'react'

/** Formatting helpers shared across every tab. */
export const fmt = (n: number | undefined | null): string =>
  n === undefined || n === null || Number.isNaN(n) ? '—' : Math.round(n).toLocaleString('en-IN')

export const pct = (num: number, den: number, dp = 1): string =>
  !den ? '—' : `${((num / den) * 100).toFixed(dp)}%`

/** Number needed to screen. Returns "NA" when nothing was found, matching
 *  the legacy nns_str() in build_v3.py:40-43. */
export const nns = (n: number, out: number, dp = 1): string =>
  !out ? 'NA' : (n / out).toFixed(dp)

type Accent = 'b' | 'o' | 'g' | 'p' | 't'

export function KpiTile(props: {
  label: string
  value: ReactNode
  sub?: ReactNode
  accent?: Accent
}) {
  const { label, value, sub, accent = 'b' } = props
  return (
    <div className={`kc ${accent === 'b' ? '' : accent}`}>
      <div className="kl">{label}</div>
      <div className="kv">{value}</div>
      {sub ? <div className="ks">{sub}</div> : null}
    </div>
  )
}

export function KpiGrid({ children }: { children: ReactNode }) {
  return <div className="kg">{children}</div>
}

export function Section(props: {
  title: ReactNode
  accent?: Accent | 'n'
  actions?: ReactNode
  children: ReactNode
}) {
  const { title, accent = 'n', actions, children } = props
  return (
    <div className="sec">
      <div className={`sh ${accent} ${actions ? 'sh-row' : ''}`}>
        <span>{title}</span>
        {actions ? <span style={{ display: 'flex', gap: 8 }}>{actions}</span> : null}
      </div>
      {children}
    </div>
  )
}

export function ChipBar<T extends string>(props: {
  options: readonly { value: T; label: string }[]
  selected: readonly T[]
  onToggle: (value: T) => void
}) {
  return (
    <div className="chip-bar">
      {props.options.map((o) => (
        <button
          key={o.value}
          className={`chip ${props.selected.includes(o.value) ? 'on' : ''}`}
          onClick={() => props.onToggle(o.value)}
        >
          {o.label}
        </button>
      ))}
    </div>
  )
}

/** Column definition for DataTable. */
export interface Column<R> {
  key: string
  header: ReactNode
  /** Cell renderer. Return a string/number/element. */
  cell: (row: R, index: number) => ReactNode
  /** Right-aligned tabular numerals. Defaults to true for all but the first column. */
  numeric?: boolean
  className?: string
}

export function DataTable<R>(props: {
  id?: string
  columns: Column<R>[]
  rows: R[]
  rowClassName?: (row: R, index: number) => string | undefined
  empty?: ReactNode
}) {
  const { id, columns, rows, rowClassName, empty } = props

  if (rows.length === 0) {
    return (
      <div className="tw">
        <div style={{ padding: '18px 14px', fontSize: 12, color: 'var(--grey)' }}>
          {empty ?? 'No rows for the selected filters.'}
        </div>
      </div>
    )
  }

  return (
    <div className="tw">
      <table id={id}>
        <thead>
          <tr>
            {columns.map((c) => (
              <th key={c.key} className={c.className}>{c.header}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, i) => (
            <tr key={i} className={rowClassName?.(row, i)}>
              {columns.map((c, ci) => (
                <td
                  key={c.key}
                  className={`${(c.numeric ?? ci > 0) ? 'num' : 'ind'} ${c.className ?? ''}`}
                >
                  {c.cell(row, i)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

export function Note({ children }: { children: ReactNode }) {
  return <div className="note">{children}</div>
}

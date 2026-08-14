import { fmt } from './primitives'
import { monthLabel } from './charts'
import type { MonthlyRow } from '../features/shared'

/**
 * Indicator × month table with a range-total column.
 *
 * The Total column comes from the API's range-deduplicated total, NOT from
 * summing the monthly cells. Those two differ whenever a beneficiary appears
 * in more than one month, and the deduplicated figure is the correct one.
 */
export function MonthlyTable(props: {
  id: string
  months: string[]
  rows: MonthlyRow[]
  indicatorHeader?: string
}) {
  const { id, months, rows, indicatorHeader = 'Indicator' } = props

  return (
    <div className="tw">
      <table id={id}>
        <thead>
          <tr>
            <th style={{ textAlign: 'left' }}>{indicatorHeader}</th>
            <th className="toth" title="Deduplicated across the selected range">Total</th>
            {months.map((mo) => <th key={mo}>{monthLabel(mo)}</th>)}
          </tr>
        </thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={`${r.label}-${i}`} className={r.emphasis ? 'cas-sub' : undefined}>
              <td className="ind">{r.label}</td>
              <td className="tot">{typeof r.total === 'number' ? fmt(r.total) : r.total}</td>
              {r.values.map((v, j) => (
                <td key={j} className="num">{typeof v === 'number' ? fmt(v) : v}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

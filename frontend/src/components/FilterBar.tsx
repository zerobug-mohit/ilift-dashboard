import type { Filters } from '../api/client'
import type { Gender } from '../api/types'
import { monthLabel } from './charts'

/**
 * Range + gender filters. Unlike the legacy dashboard, changing these refetches
 * from the API rather than re-summing pre-baked monthly buckets — which is what
 * makes multi-month totals correct.
 */
export function FilterBar(props: {
  months: string[]
  filters: Filters
  onChange: (patch: Partial<Filters>) => void
  onReset: () => void
  isDefault: boolean
  activeCount: number
}) {
  const { months, filters, onChange, onReset, isDefault, activeCount } = props
  const min = months[0]
  const max = months[months.length - 1]

  return (
    <div className="filter-bar">
      <span aria-hidden>📅</span>

      <label htmlFor="f-from">FROM</label>
      <input
        id="f-from" type="month" min={min} max={max}
        value={filters.from}
        onChange={(e) => onChange({ from: e.target.value })}
      />

      <label htmlFor="f-to">TO</label>
      <input
        id="f-to" type="month" min={min} max={max}
        value={filters.to}
        onChange={(e) => onChange({ to: e.target.value })}
      />

      <label htmlFor="f-gender">GENDER</label>
      <select
        id="f-gender"
        value={filters.gender}
        onChange={(e) => onChange({ gender: e.target.value as Gender })}
      >
        <option value="all">All</option>
        <option value="F">Female</option>
        <option value="M">Male</option>
      </select>

      <button className="btn-r" onClick={onReset} disabled={isDefault}>Reset</button>

      <span className="fstat">
        {isDefault
          ? `Showing all ${months.length} months`
          : `Showing ${activeCount} of ${months.length} months (${monthLabel(filters.from)} – ${monthLabel(filters.to)})`}
        {filters.gender !== 'all' && ` · ${filters.gender === 'F' ? 'Female' : 'Male'} only`}
      </span>
    </div>
  )
}

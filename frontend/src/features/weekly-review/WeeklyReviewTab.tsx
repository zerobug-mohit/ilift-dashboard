import { useWeekly } from '../../api/client'
import { QueryGate } from '../../components/SubTabs'
import { KpiGrid, KpiTile, Section, DataTable, Note, fmt } from '../../components/primitives'
import { exportTableToXlsx } from '../../export'
import type { Filters } from '../../api/client'
import type { WeeklyResponse } from '../../api/types'

const shortDate = (iso: string) =>
  new Date(iso).toLocaleDateString('en-IN', { day: '2-digit', month: 'short' })

export function WeeklyReviewTab({ filters }: { filters: Filters }) {
  const weekly = useWeekly(filters)

  return (
    <div className="main">
      <QueryGate query={weekly}>{(d) => <WeeklyView data={d} />}</QueryGate>
    </div>
  )
}

function WeeklyView({ data }: { data: WeeklyResponse }) {
  if (data.weeks.length === 0) {
    return (
      <div className="state">
        <h2>No complete weeks in range</h2>
        <p>The weekly review shows the most recent <em>complete</em> weeks. Widen the date filter.</p>
      </div>
    )
  }

  const latest = data.weeks[0]
  const prior  = data.weeks[1]
  const delta = (cur: number, prev?: number) =>
    prev === undefined || prev === 0 ? undefined
      : `${cur >= prev ? '▲' : '▼'} ${Math.abs(((cur - prev) / prev) * 100).toFixed(0)}% vs prior week`

  return (
    <>
      <KpiGrid>
        <KpiTile label="Camps (latest week)" value={fmt(latest.n_camps)}
                 sub={delta(latest.n_camps, prior?.n_camps)} />
        <KpiTile label="Screened" value={fmt(latest.n_screen)}
                 sub={delta(latest.n_screen, prior?.n_screen)} accent="o" />
        <KpiTile label="Avg. Footfall / Camp" value={latest.avg_ff.toFixed(1)} accent="g" />
        <KpiTile label="Sputum Collected" value={fmt(latest.n_coll)}
                 sub={`${latest.pct_coll}% of eligible`} accent="p" />
        <KpiTile label="Sputum Tested" value={fmt(latest.n_test)}
                 sub={`${latest.pct_test}% of collected`} accent="t" />
      </KpiGrid>

      <Section
        title="Weekly Reporting"
        accent="n"
        actions={<button className="dl-btn" onClick={() => exportTableToXlsx('T-wkl', 'Weekly_Reporting')}>⬇ Excel</button>}
      >
        <Note>
          Shows the most recent complete weeks (Monday–Sunday). The current partial
          week is excluded so figures are not misread as a drop in activity.
        </Note>
        <DataTable
          id="T-wkl"
          rows={data.weeks}
          columns={[
            { key: 'week',   header: 'Week',           cell: (w) => `${shortDate(w.week)} – ${shortDate(w.week_end)}`, numeric: false },
            { key: 'camps',  header: 'Camps',          cell: (w) => fmt(w.n_camps) },
            { key: 'scr',    header: 'Screened',       cell: (w) => fmt(w.n_screen) },
            { key: 'ff',     header: 'Avg/Camp',       cell: (w) => w.avg_ff.toFixed(1) },
            { key: 'male',   header: '% Male',         cell: (w) => `${w.pct_male}%` },
            { key: 'elig',   header: 'Sputum Elig.',   cell: (w) => fmt(w.n_elig) },
            { key: 'coll',   header: 'Collected',      cell: (w) => fmt(w.n_coll) },
            { key: 'collp',  header: '% Coll.',        cell: (w) => `${w.pct_coll}%` },
            { key: 'test',   header: 'Tested',         cell: (w) => fmt(w.n_test) },
            { key: 'testp',  header: '% Tested',       cell: (w) => `${w.pct_test}%` },
            { key: 'spo2',   header: '% SpO₂ rec.',    cell: (w) => `${w.pct_spo2}%` },
            { key: 'rbs',    header: '% RBS rec.',     cell: (w) => `${w.pct_rbs}%` },
            { key: 'bp',     header: '% BP rec.',      cell: (w) => `${w.pct_bp}%` },
            { key: 'le40',   header: 'Age ≤ 40',       cell: (w) => fmt(w.n_le40) },
            { key: 'scd',    header: 'SCD +ve',        cell: (w) => fmt(w.n_scd_pos) },
          ]}
        />
      </Section>

      {data.camps.map((cw, i) => (
        <Section
          key={cw.week}
          title={`Week of ${shortDate(cw.week)} — Per Camp (${cw.camps.length} camps)`}
          accent={i === 0 ? 'b' : 'g'}
          actions={<button className="dl-btn" onClick={() => exportTableToXlsx(`t-camps-${i}`, `Camps_${cw.week}`)}>⬇ Excel</button>}
        >
          <DataTable
            id={`t-camps-${i}`}
            rows={[...cw.camps].sort((a, b) => b.n_screen - a.n_screen)}
            columns={[
              { key: 'camp',  header: 'Camp ID',   cell: (c) => c.camp_id, numeric: false },
              { key: 'date',  header: 'Date',      cell: (c) => shortDate(c.camp_date), numeric: false },
              { key: 'dist',  header: 'District',  cell: (c) => c.district ?? '—', numeric: false },
              { key: 'scr',   header: 'Screened',  cell: (c) => fmt(c.n_screen) },
              { key: 'male',  header: 'Male',      cell: (c) => fmt(c.n_male) },
              { key: 'fem',   header: 'Female',    cell: (c) => fmt(c.n_female) },
              { key: 'elig',  header: 'Elig.',     cell: (c) => fmt(c.n_elig) },
              { key: 'coll',  header: 'Collected', cell: (c) => fmt(c.n_coll) },
              { key: 'test',  header: 'Tested',    cell: (c) => fmt(c.n_test) },
              ...(data.has_coordinates ? [{
                key: 'loc', header: 'Location',
                cell: (c: typeof cw.camps[number]) =>
                  c.lat !== undefined && c.lon !== undefined
                    ? `${c.lat.toFixed(3)}, ${c.lon.toFixed(3)}`
                    : '—',
                numeric: false,
              }] : []),
            ]}
          />
        </Section>
      ))}

      {!data.has_coordinates && (
        <div className="banner">
          <strong>No camp coordinates.</strong> The export has no latitude/longitude
          headers, so per-camp locations are omitted. The legacy weekly script read
          columns 73 and 74 as coordinates, but those positions hold symptom flags in
          this export — reading them would have produced empty map pins rather than an error.
        </div>
      )}
    </>
  )
}

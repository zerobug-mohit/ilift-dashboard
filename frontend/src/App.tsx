import { useState } from 'react'
import { useMeta, useRefresh, AuthError } from './api/client'
import { hasCredential } from './api/auth'
import { useFilters } from './state/filters'
import { FilterBar } from './components/FilterBar'
import { NoData, LoadFailed, SchemaWarnings } from './components/States'
import { TbCascadeTab } from './features/tb-cascade/TbCascadeTab'
import { DonorCascadeTab } from './features/donor-cascade/DonorCascadeTab'
import { NcdScdTab } from './features/ncd-scd/NcdScdTab'
import { OthersTab } from './features/others/OthersTab'
import { WeeklyReviewTab } from './features/weekly-review/WeeklyReviewTab'
import { DataManager } from './components/DataManager'
import { Login, AuthBadge } from './components/Login'
import { monthLabel } from './components/charts'

const MAIN_TABS = [
  { id: 'tbc',  label: 'TB Cascade' },
  { id: 'dc',   label: 'Donor Cascade' },
  { id: 'ncd',  label: 'NCD / SCD' },
  { id: 'oth',  label: 'Others' },
  { id: 'wr',   label: 'Weekly Review' },
  { id: 'data', label: 'Data' },
] as const

type TabId = typeof MAIN_TABS[number]['id']

export default function App() {
  const [tab, setTab] = useState<TabId>('tbc')
  const meta = useMeta()
  const refresh = useRefresh()

  const months = meta.data?.months ?? []
  const { filters, update, reset, isDefault, activeMonths } = useFilters(months)

  const hasData = !!meta.data && months.length > 0

  // A protected deployment answers 401 until a password is stored.
  const needsLogin = meta.isError && meta.error instanceof AuthError
  if (needsLogin) {
    return (
      <>
        <header>
          <div>
            <h1>iLIFT Programme — Integrated Dashboard</h1>
            <div className="sub">
              Integrated Lung Health for Tribals &nbsp;|&nbsp; William J Clinton Foundation
            </div>
          </div>
        </header>
        <Login wrong={hasCredential()} onSignedIn={() => meta.refetch()} />
      </>
    )
  }

  const level = meta.data?.auth?.level ?? 'admin'
  const isAdmin = level === 'admin'
  const protectedMode = !!meta.data?.auth?.read_protected

  return (
    <>
      <header>
        <div>
          <h1>iLIFT Programme — Integrated Dashboard</h1>
          <div className="sub">
            Integrated Lung Health for Tribals &nbsp;|&nbsp; William J Clinton Foundation
          </div>
        </div>
        <div className="header-right">
          {hasData && (
            <span className="badge">
              Data through {monthLabel(months[months.length - 1])}
            </span>
          )}
          {/* Refresh mutates server state, so viewers don't get the button —
              the server would refuse it anyway, but offering it would mislead. */}
          {isAdmin && (
            <button
              className="btn-r"
              onClick={() => refresh.mutate()}
              disabled={refresh.isPending}
              title="Re-read the data folder and recompute"
            >
              {refresh.isPending ? 'Refreshing…' : '⟳ Refresh data'}
            </button>
          )}
          <AuthBadge level={level} protectedMode={protectedMode} />
        </div>
      </header>

      {meta.isLoading && (
        <div className="state"><p>Loading…</p></div>
      )}

      {meta.isError && <LoadFailed error={meta.error} onRetry={() => meta.refetch()} />}

      {/* No data yet: explain what's missing, and offer the uploader inline so
          the problem is fixable without hunting for a tab that isn't reachable. */}
      {meta.data && months.length === 0 && (
        <>
          <NoData sources={meta.data.sources} />
          <DataManager meta={meta.data} isAdmin={isAdmin} />
        </>
      )}

      {hasData && meta.data && (
        <>
          {meta.data.schema.warnings.length > 0 && (
            <SchemaWarnings warnings={meta.data.schema.warnings} />
          )}

          <FilterBar
            months={months}
            filters={filters}
            onChange={update}
            onReset={reset}
            isDefault={isDefault}
            activeCount={activeMonths.length}
          />

          <nav className="main-tabs">
            {MAIN_TABS.map((t) => (
              <button
                key={t.id}
                className={`mt ${tab === t.id ? 'on' : ''}`}
                onClick={() => setTab(t.id)}
              >
                {t.label}
              </button>
            ))}
          </nav>

          {tab === 'tbc'  && <TbCascadeTab filters={filters} months={activeMonths} />}
          {tab === 'dc'   && <DonorCascadeTab filters={filters} months={activeMonths} />}
          {tab === 'ncd'  && <NcdScdTab filters={filters} months={activeMonths} />}
          {tab === 'oth'  && <OthersTab filters={filters} months={activeMonths} />}
          {tab === 'wr'   && <WeeklyReviewTab filters={filters} />}
          {tab === 'data' && <DataManager meta={meta.data} isAdmin={isAdmin} />}

          <footer>
            <div className="prov">
              Sources loaded {new Date(meta.data.loaded_at).toLocaleString()} ·{' '}
              {meta.data.rows.toLocaleString('en-IN')} rows ·{' '}
              {meta.data.beneficiaries.toLocaleString('en-IN')} beneficiaries ·{' '}
              {meta.data.sources.filter((s) => s.present).map((s) => s.key).join(', ')}
            </div>
            <div style={{ marginTop: 4 }}>
              Totals are deduplicated across the selected range.
            </div>
          </footer>
        </>
      )}
    </>
  )
}

import { useRef, useState } from 'react'
import { useMetrics, useNns } from '../../api/client'
import { SubTabs, QueryGate } from '../../components/SubTabs'
import { KpiGrid, KpiTile, Section, DataTable, Note, ChipBar, fmt, pct, nns } from '../../components/primitives'
import { TrendChart, BarChart } from '../../components/charts'
import { MonthlyTable } from '../../components/MonthlyTable'
import { CascadePyramid, ContextPanel } from '../../components/CascadePyramid'
import { exportTableToXlsx, exportSvg, exportSvgAsPng, exportImageToPptx, svgToPngDataUrl } from '../../export'
import { m, series, monthlyRow, pctRow, type TabProps } from '../shared'
import type { MetricsResponse, NnsCohort } from '../../api/types'

export function TbCascadeTab({ filters, months }: TabProps) {
  const metrics = useMetrics(filters)
  const nnsQuery = useNns(filters)

  return (
    <SubTabs tabs={[
      { id: 'cas', label: 'TB Cascade',        render: () => <QueryGate query={metrics}>{(d) => <CascadeView data={d} months={months} />}</QueryGate> },
      { id: 'sp',  label: 'Sputum',            render: () => <QueryGate query={metrics}>{(d) => <SputumView data={d} months={months} />}</QueryGate> },
      { id: 'nns', label: 'NNS',               render: () => <QueryGate query={nnsQuery}>{(d) => <NnsView cohorts={d.cohorts} />}</QueryGate> },
      { id: 'mon', label: 'Monthly Dashboard', render: () => <QueryGate query={metrics}>{(d) => <MonthlyView data={d} months={months} />}</QueryGate> },
    ]} />
  )
}

/* ── TB Cascade ─────────────────────────────────────────────────────────── */

function CascadeView({ data, months }: { data: MetricsResponse; months: string[] }) {
  const svgRef = useRef<SVGSVGElement>(null)
  const t = data.total

  const screened = m(t, 'n_screened')
  const camps    = m(t, 'n_camps')
  const cxr      = m(t, 'n_cxr')
  const presump  = m(t, 'n_elig_sp')
  const coll     = m(t, 'n_sp_coll')
  const tested   = m(t, 'n_sp_test')
  const notified = m(t, 'n_notified')
  const mbc      = m(t, 'n_mbc')
  const cd       = m(t, 'n_cd')
  const tx       = m(t, 'n_tx_started')
  const aiTb     = m(t, 'n_ai_tb')
  const aiOca    = m(t, 'n_ai_oca')

  const layers = [
    { label: 'Total Footfall',    value: screened, sub: `${fmt(camps)} Camps` },
    { label: 'CXR Taken',         value: cxr,      sub: `${pct(cxr, screened)} of Footfall` },
    { label: 'TB Presumptive',    value: presump,  sub: `${pct(presump, screened)} of Footfall` },
    { label: 'Sample Collection', value: coll,     sub: `${pct(coll, presump)} of Presumptive` },
    { label: 'Sample Tested',     value: tested,   sub: `${pct(tested, coll)} of Collected` },
    { label: 'TB Confirmed',      value: notified, sub: `NNS = ${nns(screened, notified)}` },
  ]

  const badges = [
    { label: 'NNS (MBC+CD)', value: nns(screened, notified) },
    { label: 'NNS (MBC)',    value: nns(screened, mbc) },
    { label: 'NNT',          value: nns(presump, notified) },
  ]

  const exportPptx = async () => {
    if (!svgRef.current) return
    const dataUrl = await svgToPngDataUrl(svgRef.current)
    await exportImageToPptx({
      dataUrl,
      title: 'TB Detection Cascade',
      subtitle: `${filtersLabel(data)} · totals deduplicated across the range`,
    })
  }

  return (
    <>
      <KpiGrid>
        <KpiTile label="Total Screened" value={fmt(screened)} sub={`${fmt(camps)} camps`} />
        <KpiTile label="CXR Taken"      value={fmt(cxr)} sub={pct(cxr, screened)} accent="o" />
        <KpiTile label="Presumptive"    value={fmt(presump)} sub={pct(presump, screened)} accent="o" />
        <KpiTile label="Sputum Tested"  value={fmt(tested)} sub={`${pct(tested, coll)} of collected`} accent="g" />
        <KpiTile label="TB Notified"    value={fmt(notified)} sub={`${fmt(mbc)} MB+ · ${fmt(cd)} CD`} accent="p" />
        <KpiTile label="Treatment Started" value={fmt(tx)} sub={pct(tx, notified)} accent="t" />
      </KpiGrid>

      <Section
        title="TB Detection Cascade — Inverted Pyramid"
        accent="o"
        actions={<>
          <button className="dl-btn" onClick={() => exportSvgAsPng(svgRef.current, 'TB_Cascade')}>⬇ PNG</button>
          <button className="dl-btn" onClick={() => exportSvg(svgRef.current, 'TB_Cascade')}>⬇ SVG</button>
          <button className="dl-btn" onClick={exportPptx}>⬇ PPTX</button>
        </>}
      >
        <div style={{
          display: 'flex', gap: 28, alignItems: 'flex-start', padding: '14px',
          flexWrap: 'wrap', background: '#fff', borderRadius: '0 0 8px 8px',
        }}>
          <div style={{ flex: '0 0 auto', boxShadow: '0 2px 12px rgba(0,0,0,0.10)', borderRadius: 8, overflow: 'hidden' }}>
            <CascadePyramid ref={svgRef} layers={layers} badges={badges} />
          </div>
          <ContextPanel boxes={[
            {
              icon: '🔬', title: 'What are the AI Results?', color: '#2E3F78',
              rows: [
                { label: 'AI-TB Suggestive',          n: aiTb,  den: cxr },
                { label: 'Other Chest Abnormalities', n: aiOca, den: cxr },
                { label: 'No Abnormality',            n: Math.max(0, cxr - aiTb - aiOca), den: cxr },
              ],
            },
            {
              icon: '👥', title: 'What are the presumptive cohorts?', color: '#3A5296',
              rows: [
                { label: 'AI Suggestive + Symptomatic', n: m(t, 'n_elig_as'), den: presump },
                { label: 'AI Suggestive only',          n: m(t, 'n_elig_ao'), den: presump },
                { label: 'Symptomatic only',            n: m(t, 'n_elig_so'), den: presump },
              ],
            },
            {
              icon: '✅', title: 'How many TB confirmations?', color: '#1F2D5A',
              rows: [
                { label: 'MB+ (Bacteriologically Confirmed)', n: mbc, den: notified },
                { label: 'Clinically Diagnosed',              n: cd,  den: notified },
              ],
            },
          ]} />
        </div>
      </Section>

      <Section title="Monthly Trends" accent="b">
        <div className="cg">
          <TrendChart
            title="CXR & AI Results"
            months={months}
            series={[
              { label: 'CXR Taken',        data: series(data, 'n_cxr', months) },
              { label: 'AI-TB Suggestive', data: series(data, 'n_ai_tb', months) },
              { label: 'AI Other Chest',   data: series(data, 'n_ai_oca', months) },
            ]}
          />
          <TrendChart
            title="Sputum Pathway"
            months={months}
            series={[
              { label: 'Eligible',  data: series(data, 'n_elig_sp', months) },
              { label: 'Collected', data: series(data, 'n_sp_coll', months) },
              { label: 'Tested',    data: series(data, 'n_sp_test', months) },
            ]}
          />
        </div>
      </Section>

      <Section
        title="Monthly TB Summary"
        accent="n"
        actions={<button className="dl-btn" onClick={() => exportTableToXlsx('t-tbc-cas', 'Monthly_TB_Summary')}>⬇ Excel</button>}
      >
        <MonthlyTable
          id="t-tbc-cas"
          months={months}
          rows={[
            monthlyRow(data, months, 'Camps',              'n_camps'),
            monthlyRow(data, months, 'Total Screened',     'n_screened', true),
            monthlyRow(data, months, 'CXR Taken',          'n_cxr'),
            pctRow(data, months,     '  CXR coverage',     'n_cxr', 'n_screened'),
            monthlyRow(data, months, 'AI-TB Suggestive',   'n_ai_tb'),
            monthlyRow(data, months, 'Symptomatic',        'n_symptomatic'),
            monthlyRow(data, months, 'Sputum Eligible',    'n_elig_sp', true),
            monthlyRow(data, months, 'Sputum Collected',   'n_sp_coll'),
            pctRow(data, months,     '  Collection rate',  'n_sp_coll', 'n_elig_sp'),
            monthlyRow(data, months, 'Sputum Tested',      'n_sp_test'),
            pctRow(data, months,     '  Testing rate',     'n_sp_test', 'n_sp_coll'),
            monthlyRow(data, months, 'MB+',                'n_mbc', true),
            monthlyRow(data, months, 'Clinically Diagnosed','n_cd'),
            monthlyRow(data, months, 'TB Notified',        'n_notified', true),
            monthlyRow(data, months, 'Treatment Started',  'n_tx_started'),
          ]}
        />
      </Section>

      <OvercountNote data={data} />
    </>
  )
}

/* ── Sputum ─────────────────────────────────────────────────────────────── */

const SPUTUM_CATS = [
  { value: 'as', label: 'AI suggestive + Symptomatic' },
  { value: 'ao', label: 'AI suggestive only' },
  { value: 'so', label: 'Symptomatic only' },
  { value: 'nn', label: 'None' },
] as const

type CatId = typeof SPUTUM_CATS[number]['value']

function SputumView({ data, months }: { data: MetricsResponse; months: string[] }) {
  const [selected, setSelected] = useState<CatId[]>(SPUTUM_CATS.map((c) => c.value))
  const t = data.total

  const toggle = (v: CatId) =>
    setSelected((s) => (s.includes(v) ? (s.length > 1 ? s.filter((x) => x !== v) : s) : [...s, v]))

  const sum = (suffix: string) =>
    selected.reduce((acc, c) => acc + m(t, `n_${suffix}_${c}`), 0)

  const scr = sum('scr'), elig = sum('elig'), coll = sum('coll')
  const test = sum('test'), mbc = sum('mbc'), cd = sum('cd')

  const rows = SPUTUM_CATS.filter((c) => selected.includes(c.value)).map((c) => ({
    cohort: c.label,
    n:    m(t, `n_scr_${c.value}`),
    elig: m(t, `n_elig_${c.value}`),
    coll: m(t, `n_coll_${c.value}`),
    test: m(t, `n_test_${c.value}`),
    mbp:  m(t, `n_mbc_${c.value}`),
    cd:   m(t, `n_cd_${c.value}`),
  }))

  return (
    <>
      <KpiGrid>
        <KpiTile label="Screened (selected)" value={fmt(scr)} />
        <KpiTile label="Eligible"  value={fmt(elig)} sub={pct(elig, scr)} accent="o" />
        <KpiTile label="Collected" value={fmt(coll)} sub={pct(coll, elig)} accent="o" />
        <KpiTile label="Tested"    value={fmt(test)} sub={pct(test, coll)} accent="g" />
        <KpiTile label="MB+"       value={fmt(mbc)}  sub={pct(mbc, test)}  accent="p" />
        <KpiTile label="NNS (MB+)" value={nns(scr, mbc)} sub="screened per MB+ case" accent="t" />
      </KpiGrid>

      <Section title="Filter by Category" accent="o">
        <ChipBar options={SPUTUM_CATS} selected={selected} onToggle={toggle} />
        <Note>
          <strong>Category definitions (select one or more; default = All):</strong><br />
          <b>AI suggestive + Symptomatic</b> — X-ray flagged as TB-related abnormality <em>and</em> patient reported TB symptoms<br />
          <b>AI suggestive only</b> — X-ray flagged as TB-related abnormality, no TB symptoms reported<br />
          <b>Symptomatic only</b> — TB symptoms reported, X-ray not flagged (or no X-ray)<br />
          <b>None</b> — Neither AI-flagged nor symptomatic
        </Note>
      </Section>

      <Section
        title="Sputum Indicators"
        accent="n"
        actions={<button className="dl-btn" onClick={() => exportTableToXlsx('TBL-sp', 'Sputum_Indicators')}>⬇ Excel</button>}
      >
        <DataTable
          id="TBL-sp"
          rows={[...rows, {
            cohort: 'Total (selected)', n: scr, elig, coll, test, mbp: mbc, cd,
          }]}
          rowClassName={(_, i) => (i === rows.length ? 'cas-sub' : undefined)}
          columns={[
            { key: 'cohort', header: 'Category', cell: (r) => r.cohort, numeric: false },
            { key: 'n',      header: 'Screened',  cell: (r) => fmt(r.n) },
            { key: 'elig',   header: 'Eligible',  cell: (r) => fmt(r.elig) },
            { key: 'eligp',  header: '% Eligible',cell: (r) => pct(r.elig, r.n) },
            { key: 'coll',   header: 'Collected', cell: (r) => fmt(r.coll) },
            { key: 'collp',  header: '% Collected',cell: (r) => pct(r.coll, r.elig) },
            { key: 'test',   header: 'Tested',    cell: (r) => fmt(r.test) },
            { key: 'testp',  header: '% Tested',  cell: (r) => pct(r.test, r.coll) },
            { key: 'mbp',    header: 'MB+',       cell: (r) => fmt(r.mbp) },
            { key: 'cd',     header: 'Clin. Dx',  cell: (r) => fmt(r.cd) },
            { key: 'nns',    header: 'NNS (MB+)', cell: (r) => nns(r.n, r.mbp) },
          ]}
        />
      </Section>

      <Section title="Sputum Pathway by Month" accent="b">
        <div className="cg one">
          <BarChart
            months={months}
            series={[
              { label: 'Collected', data: series(data, 'n_sp_coll', months) },
              { label: 'Tested',    data: series(data, 'n_sp_test', months) },
            ]}
          />
        </div>
      </Section>
    </>
  )
}

/* ── NNS ────────────────────────────────────────────────────────────────── */

function NnsView({ cohorts }: { cohorts: NnsCohort[] }) {
  const themes = Array.from(new Set(cohorts.map((c) => c.theme)))
  const [theme, setTheme] = useState(themes[0])

  const shown = cohorts.filter((c) => c.theme === theme)

  return (
    <>
      <Section title="NNS Charts — Select a Theme to Plot" accent="o">
        <div className="chip-bar">
          {themes.map((th) => (
            <button key={th} className={`chip ${th === theme ? 'on' : ''}`} onClick={() => setTheme(th)}>
              {th}
            </button>
          ))}
        </div>
        <div className="cg">
          <ThemeBar title="NNS for TB (screened per TB case)" cohorts={shown} outcome="tb" />
          <ThemeBar title="NNS for CRD (screened per CRD diagnosis)" cohorts={shown} outcome="crd_dx" />
        </div>
      </Section>

      <Section
        title="NNS Full Table"
        accent="n"
        actions={<button className="dl-btn" onClick={() => exportTableToXlsx('TBL-nns', 'NNS_Table')}>⬇ Excel</button>}
      >
        <DataTable
          id="TBL-nns"
          rows={cohorts}
          columns={[
            { key: 'theme',  header: 'Theme',  cell: (c) => c.theme, numeric: false },
            { key: 'label',  header: 'Cohort', cell: (c) => c.label, numeric: false },
            { key: 'n',      header: 'Screened',   cell: (c) => fmt(c.total.n) },
            { key: 'tb',     header: 'TB',         cell: (c) => fmt(c.total.tb) },
            { key: 'nnstb',  header: 'NNS (TB)',   cell: (c) => nns(c.total.n, c.total.tb) },
            { key: 'mbc',    header: 'MB+',        cell: (c) => fmt(c.total.mbc) },
            { key: 'nnsmbc', header: 'NNS (MB+)',  cell: (c) => nns(c.total.n, c.total.mbc) },
            { key: 'crd',    header: 'CRD Dx',     cell: (c) => fmt(c.total.crd_dx) },
            { key: 'nnscrd', header: 'NNS (CRD)',  cell: (c) => nns(c.total.n, c.total.crd_dx) },
            { key: 'copd',   header: 'COPD',       cell: (c) => fmt(c.total.copd) },
            { key: 'asthma', header: 'Asthma',     cell: (c) => fmt(c.total.asthma) },
          ]}
        />
      </Section>
    </>
  )
}

/** Horizontal comparison of NNS across cohorts within one theme. */
function ThemeBar({ title, cohorts, outcome }: {
  title: string
  cohorts: NnsCohort[]
  outcome: 'tb' | 'crd_dx'
}) {
  const values = cohorts.map((c) => {
    const out = c.total[outcome]
    return out ? Number((c.total.n / out).toFixed(1)) : null
  })

  return (
    <BarChart
      title={title}
      months={cohorts.map((c) => c.label)}
      series={[{ label: 'Number needed to screen', data: values }]}
      yTitle="NNS"
    />
  )
}

/* ── Monthly Dashboard ──────────────────────────────────────────────────── */

function MonthlyView({ data, months }: { data: MetricsResponse; months: string[] }) {
  return (
    <>
      <KpiGrid>
        <KpiTile label="Camps"    value={fmt(m(data.total, 'n_camps'))} />
        <KpiTile label="Screened" value={fmt(m(data.total, 'n_screened'))} accent="o" />
        <KpiTile
          label="Avg. Footfall / Camp"
          value={fmt(m(data.total, 'n_screened') / Math.max(1, m(data.total, 'n_camps')))}
          accent="g"
        />
        <KpiTile label="TB Notified" value={fmt(m(data.total, 'n_notified'))} accent="p" />
        <KpiTile label="CRD Diagnosed" value={fmt(m(data.total, 'n_crd_dx'))} accent="t" />
      </KpiGrid>

      <Section title="Camp Activity" accent="b">
        <div className="cg">
          <BarChart title="Camps per month" months={months}
                    series={[{ label: 'Camps', data: series(data, 'n_camps', months) }]} />
          <TrendChart title="Footfall per month" months={months}
                      series={[{ label: 'Screened', data: series(data, 'n_screened', months), fill: true }]} />
        </div>
      </Section>

      <Section title="TB Trends" accent="o">
        <div className="cg">
          <TrendChart title="TB confirmations" months={months}
                      series={[
                        { label: 'MB+',          data: series(data, 'n_mbc', months) },
                        { label: 'Clinical Dx',  data: series(data, 'n_cd', months) },
                        { label: 'Tx started',   data: series(data, 'n_tx_started', months) },
                      ]} />
          <TrendChart title="Presumptive & tested" months={months}
                      series={[
                        { label: 'Presumptive', data: series(data, 'n_elig_sp', months) },
                        { label: 'Tested',      data: series(data, 'n_sp_test', months) },
                      ]} />
        </div>
      </Section>

      <Section title="CRD Trends" accent="g">
        <div className="cg">
          <TrendChart title="Facility & spirometry" months={months}
                      series={[
                        { label: 'Facility visited', data: series(data, 'n_facility', months) },
                        { label: 'Spirometry done',  data: series(data, 'n_spiro', months) },
                      ]} />
          <TrendChart title="CRD diagnoses" months={months}
                      series={[
                        { label: 'COPD',   data: series(data, 'n_copd', months) },
                        { label: 'Asthma', data: series(data, 'n_asthma', months) },
                      ]} />
        </div>
      </Section>

      <Section
        title="Full Monthly Summary"
        accent="n"
        actions={<button className="dl-btn" onClick={() => exportTableToXlsx('t-mon', 'Full_Monthly_Summary')}>⬇ Excel</button>}
      >
        <MonthlyTable
          id="t-mon"
          months={months}
          rows={[
            monthlyRow(data, months, 'Camps',             'n_camps'),
            monthlyRow(data, months, 'Screened',          'n_screened', true),
            monthlyRow(data, months, 'CXR Taken',         'n_cxr'),
            monthlyRow(data, months, 'AI-TB Suggestive',  'n_ai_tb'),
            monthlyRow(data, months, 'AI Other Chest',    'n_ai_oca'),
            monthlyRow(data, months, 'Symptomatic',       'n_symptomatic'),
            monthlyRow(data, months, 'Vulnerable',        'n_vuln'),
            monthlyRow(data, months, 'Sputum Eligible',   'n_elig_sp', true),
            monthlyRow(data, months, 'Sputum Collected',  'n_sp_coll'),
            monthlyRow(data, months, 'Sputum Tested',     'n_sp_test'),
            monthlyRow(data, months, 'MB+',               'n_mbc'),
            monthlyRow(data, months, 'TB Notified',       'n_notified', true),
            monthlyRow(data, months, 'Treatment Started', 'n_tx_started'),
            monthlyRow(data, months, 'Facility Visited',  'n_facility', true),
            monthlyRow(data, months, 'Spirometry Done',   'n_spiro'),
            monthlyRow(data, months, 'COPD',              'n_copd'),
            monthlyRow(data, months, 'Asthma',            'n_asthma'),
            monthlyRow(data, months, 'CRD Diagnosed',     'n_crd_dx', true),
            monthlyRow(data, months, 'Past TB',           'n_past_tb'),
          ]}
        />
      </Section>
    </>
  )
}

/* ── Shared bits ────────────────────────────────────────────────────────── */

const filtersLabel = (d: MetricsResponse) =>
  `${d.filters.from} to ${d.filters.to}${d.filters.gender !== 'all' ? ` · ${d.filters.gender}` : ''}`

/**
 * Shows how much double-counting the range dedup removed, so the difference
 * from the old dashboard is explained rather than mysterious.
 */
export function OvercountNote({ data }: { data: MetricsResponse }) {
  const diff = m(data.overcount, 'n_screened')
  if (!diff) return null

  const correct = m(data.total, 'n_screened')
  return (
    <div className="banner" style={{ borderRadius: 6 }}>
      <strong>Note on totals.</strong> For this range, {fmt(diff)} screening
      {diff === 1 ? '' : 's'} would have been double-counted by the previous dashboard,
      which added up monthly figures ({fmt(correct + diff)}) instead of counting each
      beneficiary once ({fmt(correct)}). Beneficiaries attending camps in more than one
      month are now counted once.
    </div>
  )
}

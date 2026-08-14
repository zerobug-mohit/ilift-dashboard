import { useMetrics } from '../../api/client'
import { SubTabs, QueryGate } from '../../components/SubTabs'
import { KpiGrid, KpiTile, Section, DataTable, Note, fmt, pct } from '../../components/primitives'
import { BarChart } from '../../components/charts'
import { exportTableToXlsx } from '../../export'
import { m, series, type TabProps } from '../shared'
import type { MetricsResponse } from '../../api/types'

/**
 * Lung-health pathway groupings, ported from the donor cascade tab
 * (build_v3.py:469-500). Group definitions come from calc_logic()'s
 * lhp_g() sub-cohorts — see metrics_core.R.
 */

const LH_GROUPS = [
  { key: 'lh1', label: 'TB presumptive only' },
  { key: 'lh2', label: 'TB + CRD (mMRC+, no AI-OCA)' },
  { key: 'lh3', label: 'TB + CRD (AI-OCA, mMRC 0)' },
  { key: 'lh4', label: 'TB + CRD (mMRC+ and AI-OCA)' },
  { key: 'lh5', label: 'CRD only (mMRC+, no AI-OCA)' },
  { key: 'lh6', label: 'CRD only (AI-OCA, mMRC 0)' },
  { key: 'lh7', label: 'CRD only (mMRC+ and AI-OCA)' },
  { key: 'lh8', label: 'Neither' },
] as const

const LH_GROUPS_NEW = LH_GROUPS.map((g) => ({
  key: `${g.key}n`,
  label: g.label.replace('AI-OCA', 'Past TB'),
}))

export function DonorCascadeTab({ filters, months }: TabProps) {
  const metrics = useMetrics(filters)

  return (
    <SubTabs tabs={[
      {
        id: 'scr', label: 'LH Pathway at Screening',
        render: () => <QueryGate query={metrics}>{(d) => <ScreeningView data={d} months={months} />}</QueryGate>,
      },
      {
        id: 'fac', label: 'LH Pathway at Facility',
        render: () => <QueryGate query={metrics}>{(d) => (
          <PathwayView data={d} groups={LH_GROUPS} tableId="t-dc-fac"
                       title="LH Pathway at Facility — By Referral Category" />
        )}</QueryGate>,
      },
      {
        id: 'facn', label: 'LH Pathway at Facility (New CRD definition)',
        render: () => <QueryGate query={metrics}>{(d) => (
          <PathwayView data={d} groups={LH_GROUPS_NEW} tableId="t-dc-facn"
                       title="LH Pathway at Facility — New CRD Definition (Past TB replaces AI-OCA)"
                       note="In this definition a beneficiary counts as CRD-presumptive if they are mMRC grade 1+ OR report past TB, rather than mMRC 1+ OR AI-flagged other chest abnormality." />
        )}</QueryGate>,
      },
      {
        id: 'tbp', label: 'TB Pathway from Camp',
        render: () => <QueryGate query={metrics}>{(d) => <TbPathwayView data={d} months={months} />}</QueryGate>,
      },
    ]} />
  )
}

function ScreeningView({ data, months }: { data: MetricsResponse; months: string[] }) {
  const t = data.total
  const tbOnly  = m(t, 'n_tb_only')
  const tbCrd   = m(t, 'n_tb_crd')
  const crdOnly = m(t, 'n_crd_only')
  const neither = m(t, 'n_neither')
  const total   = tbOnly + tbCrd + crdOnly + neither

  const rows = [
    { label: 'TB presumptive only',      n: tbOnly,  tb: m(t, 'n_lh1_tb') },
    { label: 'TB + CRD presumptive',     n: tbCrd,   tb: m(t, 'n_tbc_tb') },
    { label: 'CRD presumptive only',     n: crdOnly, tb: m(t, 'n_crd_tb') },
    { label: 'Neither',                  n: neither, tb: m(t, 'n_nne_tb') },
  ]

  return (
    <>
      <KpiGrid>
        <KpiTile label="Screened"          value={fmt(m(t, 'n_screened'))} />
        <KpiTile label="TB Presumptive"    value={fmt(tbOnly + tbCrd)} sub={pct(tbOnly + tbCrd, total)} accent="o" />
        <KpiTile label="CRD Presumptive"   value={fmt(crdOnly + tbCrd)} sub={pct(crdOnly + tbCrd, total)} accent="g" />
        <KpiTile label="Both"              value={fmt(tbCrd)} sub={pct(tbCrd, total)} accent="p" />
        <KpiTile label="Neither"           value={fmt(neither)} sub={pct(neither, total)} accent="t" />
      </KpiGrid>

      <Section
        title="LH Pathway at Screening"
        accent="b"
        actions={<button className="dl-btn" onClick={() => exportTableToXlsx('t-dc-scr', 'LH_Pathway_Screening')}>⬇ Excel</button>}
      >
        <DataTable
          id="t-dc-scr"
          rows={rows}
          columns={[
            { key: 'label', header: 'Category',       cell: (r) => r.label, numeric: false },
            { key: 'n',     header: 'Beneficiaries',  cell: (r) => fmt(r.n) },
            { key: 'share', header: '% of Screened',  cell: (r) => pct(r.n, total) },
            { key: 'tb',    header: 'TB Confirmed',   cell: (r) => fmt(r.tb) },
            { key: 'yield', header: 'TB Yield',       cell: (r) => pct(r.tb, r.n, 2) },
          ]}
        />
      </Section>

      <Section title="Pathway split by month" accent="b">
        <div className="cg one">
          <BarChart
            months={months}
            stacked
            series={[
              { label: 'TB only',   data: series(data, 'n_tb_only', months) },
              { label: 'TB + CRD',  data: series(data, 'n_tb_crd', months) },
              { label: 'CRD only',  data: series(data, 'n_crd_only', months) },
              { label: 'Neither',   data: series(data, 'n_neither', months) },
            ]}
          />
        </div>
      </Section>
    </>
  )
}

function PathwayView(props: {
  data: MetricsResponse
  groups: readonly { key: string; label: string }[]
  tableId: string
  title: string
  note?: string
}) {
  const { data, groups, tableId, title, note } = props
  const t = data.total

  const rows = groups.map((g) => ({
    label: g.label,
    tot:   m(t, `n_${g.key}_tot`),
    fac:   m(t, `n_${g.key}_fac`),
    spiro: m(t, `n_${g.key}_spiro`),
    cpd:   m(t, `n_${g.key}_cpd`),
    ast:   m(t, `n_${g.key}_ast`),
    oth:   m(t, `n_${g.key}_oth`),
  }))

  const totals = rows.reduce((a, r) => ({
    label: 'Total', tot: a.tot + r.tot, fac: a.fac + r.fac, spiro: a.spiro + r.spiro,
    cpd: a.cpd + r.cpd, ast: a.ast + r.ast, oth: a.oth + r.oth,
  }), { label: 'Total', tot: 0, fac: 0, spiro: 0, cpd: 0, ast: 0, oth: 0 })

  return (
    <>
      <KpiGrid>
        <KpiTile label="Referred"        value={fmt(totals.tot)} />
        <KpiTile label="Facility Visited" value={fmt(totals.fac)} sub={pct(totals.fac, totals.tot)} accent="o" />
        <KpiTile label="Spirometry Done"  value={fmt(totals.spiro)} sub={pct(totals.spiro, totals.fac)} accent="g" />
        <KpiTile label="COPD"             value={fmt(totals.cpd)} sub={pct(totals.cpd, totals.spiro)} accent="p" />
        <KpiTile label="Asthma"           value={fmt(totals.ast)} sub={pct(totals.ast, totals.spiro)} accent="t" />
      </KpiGrid>

      <Section
        title={title}
        accent="g"
        actions={<button className="dl-btn" onClick={() => exportTableToXlsx(tableId, 'LH_Pathway_Facility')}>⬇ Excel</button>}
      >
        {note ? <Note>{note}</Note> : null}
        <DataTable
          id={tableId}
          rows={[...rows, totals]}
          rowClassName={(_, i) => (i === rows.length ? 'cas-sub' : undefined)}
          columns={[
            { key: 'label', header: 'Referral category', cell: (r) => r.label, numeric: false },
            { key: 'tot',   header: 'Referred',   cell: (r) => fmt(r.tot) },
            { key: 'fac',   header: 'Facility',   cell: (r) => fmt(r.fac) },
            { key: 'facp',  header: '% Visited',  cell: (r) => pct(r.fac, r.tot) },
            { key: 'spiro', header: 'Spirometry', cell: (r) => fmt(r.spiro) },
            { key: 'sprp',  header: '% Spiro',    cell: (r) => pct(r.spiro, r.fac) },
            { key: 'cpd',   header: 'COPD',       cell: (r) => fmt(r.cpd) },
            { key: 'ast',   header: 'Asthma',     cell: (r) => fmt(r.ast) },
            { key: 'oth',   header: 'Other CRD',  cell: (r) => fmt(r.oth) },
          ]}
        />
      </Section>
    </>
  )
}

function TbPathwayView({ data, months }: { data: MetricsResponse; months: string[] }) {
  const t = data.total

  const CXR_CATS = [
    { key: 'ts', label: 'CXR TB-suggestive, symptomatic' },
    { key: 'tn', label: 'CXR TB-suggestive, not symptomatic' },
    { key: 'os', label: 'CXR other abnormality, symptomatic' },
    { key: 'on', label: 'CXR other abnormality, not symptomatic' },
    { key: 'ns', label: 'CXR normal, symptomatic' },
    { key: 'nn', label: 'CXR normal, not symptomatic' },
  ] as const

  const rows = CXR_CATS.map((c) => ({
    label:  c.label,
    test:   m(t, `n_cxr_${c.key}_test`),
    mbc:    m(t, `n_cxr_${c.key}_mbc`),
    cd:     m(t, `n_cxr_${c.key}_cd`),
    tx:     m(t, `n_cxr_${c.key}_tx`),
    mbc_tx: m(t, `n_cxr_${c.key}_mbc_tx`),
  }))

  const totals = rows.reduce((a, r) => ({
    label: 'Total', test: a.test + r.test, mbc: a.mbc + r.mbc,
    cd: a.cd + r.cd, tx: a.tx + r.tx, mbc_tx: a.mbc_tx + r.mbc_tx,
  }), { label: 'Total', test: 0, mbc: 0, cd: 0, tx: 0, mbc_tx: 0 })

  return (
    <>
      <KpiGrid>
        <KpiTile label="Tested"            value={fmt(totals.test)} />
        <KpiTile label="MB+"               value={fmt(totals.mbc)} sub={pct(totals.mbc, totals.test, 2)} accent="o" />
        <KpiTile label="Clinically Dx"     value={fmt(totals.cd)} accent="g" />
        <KpiTile label="Notified"          value={fmt(totals.mbc + totals.cd)} accent="p" />
        <KpiTile label="Treatment Started" value={fmt(totals.tx)} sub={pct(totals.tx, totals.mbc + totals.cd)} accent="t" />
      </KpiGrid>

      <Section
        title="TB Pathway from Camp — by CXR result and symptom status"
        accent="o"
        actions={<button className="dl-btn" onClick={() => exportTableToXlsx('t-dc-tbp', 'TB_Pathway_Camp')}>⬇ Excel</button>}
      >
        <DataTable
          id="t-dc-tbp"
          rows={[...rows, totals]}
          rowClassName={(_, i) => (i === rows.length ? 'cas-sub' : undefined)}
          columns={[
            { key: 'label',  header: 'CXR × symptom category', cell: (r) => r.label, numeric: false },
            { key: 'test',   header: 'Tested',        cell: (r) => fmt(r.test) },
            { key: 'mbc',    header: 'MB+',           cell: (r) => fmt(r.mbc) },
            { key: 'yield',  header: 'MB+ Yield',     cell: (r) => pct(r.mbc, r.test, 2) },
            { key: 'cd',     header: 'Clinical Dx',   cell: (r) => fmt(r.cd) },
            { key: 'ntf',    header: 'Notified',      cell: (r) => fmt(r.mbc + r.cd) },
            { key: 'tx',     header: 'Tx Started',    cell: (r) => fmt(r.tx) },
            { key: 'txp',    header: '% on Tx',       cell: (r) => pct(r.tx, r.mbc + r.cd) },
          ]}
        />
      </Section>

      <Section title="Notification trend" accent="b">
        <div className="cg one">
          <BarChart
            months={months}
            stacked
            series={[
              { label: 'MB+',         data: series(data, 'n_mbc', months) },
              { label: 'Clinical Dx', data: series(data, 'n_cd', months) },
            ]}
          />
        </div>
      </Section>
    </>
  )
}

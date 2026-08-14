import { useMetrics } from '../../api/client'
import { SubTabs, QueryGate } from '../../components/SubTabs'
import { KpiGrid, KpiTile, Section, DataTable, Note, fmt, pct } from '../../components/primitives'
import { BarChart } from '../../components/charts'
import { exportTableToXlsx } from '../../export'
import { m, type TabProps } from '../shared'
import type { MetricsResponse } from '../../api/types'

export function OthersTab({ filters, months }: TabProps) {
  const metrics = useMetrics(filters)

  return (
    <SubTabs tabs={[
      { id: 'mrc',  label: 'mMRC Cascade',              render: () => <QueryGate query={metrics}>{(d) => <MmrcView data={d} months={months} />}</QueryGate> },
      { id: 'crd',  label: 'CRD Cascade — Old Definition', render: () => <QueryGate query={metrics}>{(d) => <CrdOldView data={d} />}</QueryGate> },
      { id: 'crdp', label: 'CRD Cascade — New Definition', render: () => <QueryGate query={metrics}>{(d) => <CrdNewView data={d} />}</QueryGate> },
    ]} />
  )
}

const MMRC_GRADES = [
  { key: 'g0', label: 'Grade 0 — breathless only on strenuous exercise' },
  { key: 'g1', label: 'Grade 1 — short of breath hurrying on the level' },
  { key: 'g2', label: 'Grade 2 — walks slower than peers' },
  { key: 'g3', label: 'Grade 3 — stops after ~100 m' },
  { key: 'g4', label: 'Grade 4 — too breathless to leave the house' },
  { key: 'g5', label: 'Grade 5' },
] as const

function MmrcView({ data, months }: { data: MetricsResponse; months: string[] }) {
  const t = data.total
  const rows = MMRC_GRADES.map((g, i) => ({
    label:  g.label,
    n:      m(t, `n_mmrc_${i}`),
    fac:    m(t, `n_${g.key}_fac`),
    spiro:  m(t, `n_${g.key}_spiro`),
    copd:   m(t, `n_${g.key}_copd`),
    asthma: m(t, `n_${g.key}_asthma`),
    crd:    m(t, `n_${g.key}_crd`),
    tb:     m(t, `n_${g.key}_tb`),
  }))

  const totals = rows.reduce((a, r) => ({
    label: 'Total', n: a.n + r.n, fac: a.fac + r.fac, spiro: a.spiro + r.spiro,
    copd: a.copd + r.copd, asthma: a.asthma + r.asthma, crd: a.crd + r.crd, tb: a.tb + r.tb,
  }), { label: 'Total', n: 0, fac: 0, spiro: 0, copd: 0, asthma: 0, crd: 0, tb: 0 })

  return (
    <>
      <KpiGrid>
        <KpiTile label="Screened"       value={fmt(m(t, 'n_screened'))} />
        <KpiTile label="mMRC Grade 1+"  value={fmt(m(t, 'n_mmrc_pos'))} sub={pct(m(t, 'n_mmrc_pos'), m(t, 'n_screened'))} accent="o" />
        <KpiTile label="Grade 0"        value={fmt(m(t, 'n_mmrc_0'))} accent="g" />
        <KpiTile label="CRD Diagnosed"  value={fmt(m(t, 'n_crd_dx'))} accent="p" />
      </KpiGrid>

      <Section
        title="mMRC Cascade Breakdown"
        accent="g"
        actions={<button className="dl-btn" onClick={() => exportTableToXlsx('t-mmrc-cas', 'mMRC_Cascade')}>⬇ Excel</button>}
      >
        <Note>
          The mMRC breathlessness scale grades functional limitation. Higher grades should
          concentrate CRD diagnoses — this table shows whether they do.
        </Note>
        <DataTable
          id="t-mmrc-cas"
          rows={[...rows, totals]}
          rowClassName={(_, i) => (i === rows.length ? 'cas-sub' : undefined)}
          columns={[
            { key: 'label',  header: 'mMRC grade',  cell: (r) => r.label, numeric: false },
            { key: 'n',      header: 'Beneficiaries', cell: (r) => fmt(r.n) },
            { key: 'fac',    header: 'Facility',    cell: (r) => fmt(r.fac) },
            { key: 'spiro',  header: 'Spirometry',  cell: (r) => fmt(r.spiro) },
            { key: 'copd',   header: 'COPD',        cell: (r) => fmt(r.copd) },
            { key: 'asthma', header: 'Asthma',      cell: (r) => fmt(r.asthma) },
            { key: 'crd',    header: 'CRD Dx',      cell: (r) => fmt(r.crd) },
            { key: 'crdr',   header: 'CRD Rate',    cell: (r) => pct(r.crd, r.spiro) },
            { key: 'tb',     header: 'TB',          cell: (r) => fmt(r.tb) },
          ]}
        />
      </Section>

      <Section title="Grade distribution" accent="b">
        <div className="cg one">
          <BarChart
            months={MMRC_GRADES.map((_, i) => `Grade ${i}`)}
            series={[
              { label: 'Beneficiaries', data: rows.map((r) => r.n) },
              { label: 'CRD diagnosed', data: rows.map((r) => r.crd) },
            ]}
          />
        </div>
      </Section>
      <div style={{ display: 'none' }}>{months.length}</div>
    </>
  )
}

/** Screening variables and their contribution to COPD diagnosis. */
const CRD_VARS_OLD = [
  { key: 'cough',      label: 'Cough' },
  { key: 'chest',      label: 'Chest pain' },
  { key: 'aitb',       label: 'AI-TB suggestive' },
  { key: 'aioca',      label: 'AI other chest abnormality' },
  { key: 'tobacco',    label: 'Tobacco (any)' },
  { key: 'smoking',    label: 'Smoking' },
  { key: 'bmi',        label: 'BMI < 18.5' },
  { key: 'rbs',        label: 'RBS > 200' },
  { key: 'mine',       label: 'Mine worker' },
  { key: 'factory',    label: 'Factory worker' },
  { key: 'miningcamp', label: 'Camp in mining area' },
  { key: 'spo295',     label: 'SpO₂ < 95%' },
  { key: 'ainorm',     label: 'AI normal' },
  { key: 'notaken',    label: 'No X-ray taken' },
] as const

function CrdOldView({ data }: { data: MetricsResponse }) {
  const t = data.total
  const totalCopd = m(t, 'n_copd')

  const rows = CRD_VARS_OLD.map((v) => ({
    label: v.label,
    fac:   m(t, `n_crdv_${v.key}_fac`),
    copd:  m(t, `n_crdv_${v.key}_copd`),
  })).sort((a, b) => b.copd - a.copd)

  return (
    <>
      <KpiGrid>
        <KpiTile label="Facility Visited" value={fmt(m(t, 'n_facility'))} />
        <KpiTile label="Spirometry Done"  value={fmt(m(t, 'n_spiro'))} accent="o" />
        <KpiTile label="COPD"             value={fmt(totalCopd)} accent="g" />
        <KpiTile label="Asthma"           value={fmt(m(t, 'n_asthma'))} accent="p" />
        <KpiTile label="Other CRD"        value={fmt(m(t, 'n_crd_other'))} accent="t" />
      </KpiGrid>

      <Section title="Contribution to COPD Diagnosis by Screening Variable" accent="g">
        <div className="cg one">
          <BarChart
            months={rows.map((r) => r.label)}
            series={[
              { label: 'Visited facility', data: rows.map((r) => r.fac) },
              { label: 'Diagnosed COPD',   data: rows.map((r) => r.copd) },
            ]}
          />
        </div>
      </Section>

      <Section
        title="Understanding Who Got Diagnosed — Overall Contribution to COPD Diagnosis"
        accent="g"
        actions={<button className="dl-btn" onClick={() => exportTableToXlsx('t-crd', 'CRD_Cascade_Old')}>⬇ Excel</button>}
      >
        <Note>
          Categories overlap — a beneficiary can appear in several rows — so the column
          does not sum to the COPD total. <b>% of all COPD</b> shows how much of the total
          COPD caseload each screening variable touches.
        </Note>
        <DataTable
          id="t-crd"
          rows={rows}
          columns={[
            { key: 'label', header: 'Screening variable', cell: (r) => r.label, numeric: false },
            { key: 'fac',   header: 'Visited facility',   cell: (r) => fmt(r.fac) },
            { key: 'copd',  header: 'Diagnosed COPD',     cell: (r) => fmt(r.copd) },
            { key: 'rate',  header: 'COPD rate',          cell: (r) => pct(r.copd, r.fac) },
            { key: 'share', header: '% of all COPD',      cell: (r) => pct(r.copd, totalCopd) },
          ]}
        />
      </Section>
    </>
  )
}

const CRD_PRESUMPTIVE = [
  { key: 'mmrc',       label: 'mMRC grade 1+' },
  { key: 'pasttb',     label: 'Past TB' },
  { key: 'aioca',      label: 'AI other chest abnormality' },
  { key: 'aitb',       label: 'AI-TB suggestive' },
  { key: 'tobacco',    label: 'Tobacco (any)' },
  { key: 'smoking',    label: 'Smoking' },
  { key: 'bmi',        label: 'BMI < 18.5' },
  { key: 'cough',      label: 'Cough' },
  { key: 'chestpain',  label: 'Chest pain' },
  { key: 'mineworker', label: 'Mine worker' },
  { key: 'factory',    label: 'Factory worker' },
  { key: 'miningcamp', label: 'Camp in mining area' },
  { key: 'spo295',     label: 'SpO₂ < 95%' },
] as const

function CrdNewView({ data }: { data: MetricsResponse }) {
  const t = data.total
  const screened = m(t, 'n_screened')

  const rows = CRD_PRESUMPTIVE.map((v) => ({
    label: v.label,
    n:     m(t, `n_crdp_${v.key}`),
  })).sort((a, b) => b.n - a.n)

  return (
    <>
      <KpiGrid>
        <KpiTile label="Screened"        value={fmt(screened)} />
        <KpiTile label="CRD Presumptive" value={fmt(m(t, 'n_crd_pres'))} sub={pct(m(t, 'n_crd_pres'), screened)} accent="o" />
        <KpiTile label="Spirometry Done" value={fmt(m(t, 'n_spiro'))} accent="g" />
        <KpiTile label="CRD Diagnosed"   value={fmt(m(t, 'n_crd_dx'))} accent="p" />
      </KpiGrid>

      <Section title="CRD Cascade — New Definition (Visualisation)" accent="g">
        <div className="cg one">
          <BarChart
            months={rows.map((r) => r.label)}
            series={[{ label: 'Beneficiaries meeting criterion', data: rows.map((r) => r.n) }]}
          />
        </div>
      </Section>

      <Section
        title="CRD Cascade — New Definition (by Criterion)"
        accent="g"
        actions={<button className="dl-btn" onClick={() => exportTableToXlsx('t-crdp', 'CRD_Cascade_New')}>⬇ Excel</button>}
      >
        <Note>
          Criteria overlap, so the counts do not sum to the presumptive total.
          Under the new definition a beneficiary is CRD-presumptive if mMRC grade 1+
          <em> or</em> reporting past TB.
        </Note>
        <DataTable
          id="t-crdp"
          rows={rows}
          columns={[
            { key: 'label', header: 'Criterion',      cell: (r) => r.label, numeric: false },
            { key: 'n',     header: 'Beneficiaries',  cell: (r) => fmt(r.n) },
            { key: 'share', header: '% of Screened',  cell: (r) => pct(r.n, screened) },
          ]}
        />
      </Section>
    </>
  )
}

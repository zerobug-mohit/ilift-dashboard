import { useMetrics } from '../../api/client'
import { SubTabs, QueryGate } from '../../components/SubTabs'
import { KpiGrid, KpiTile, Section, DataTable, Note, fmt, pct } from '../../components/primitives'
import { TrendChart, BarChart } from '../../components/charts'
import { MonthlyTable } from '../../components/MonthlyTable'
import { exportTableToXlsx } from '../../export'
import { m, series, monthlyRow, pctRow, type TabProps } from '../shared'
import type { MetricsResponse } from '../../api/types'

export function NcdScdTab({ filters, months }: TabProps) {
  const metrics = useMetrics(filters)

  return (
    <SubTabs tabs={[
      { id: 'dm',  label: 'Diabetes',     render: () => <QueryGate query={metrics}>{(d) => <DiabetesView data={d} months={months} />}</QueryGate> },
      { id: 'ht',  label: 'Hypertension', render: () => <QueryGate query={metrics}>{(d) => <HypertensionView data={d} months={months} />}</QueryGate> },
      { id: 'scd', label: 'SCD Cascade',  render: () => <QueryGate query={metrics}>{(d) => <ScdView data={d} months={months} />}</QueryGate> },
    ]} />
  )
}

function DiabetesView({ data, months }: { data: MetricsResponse; months: string[] }) {
  const t = data.total
  const screened = m(t, 'n_screened')
  const tested   = m(t, 'n_rbs')
  const above140 = m(t, 'n_rbs_140p')
  const above200 = m(t, 'n_rbs_200p')

  return (
    <>
      <KpiGrid>
        <KpiTile label="Screened"     value={fmt(screened)} />
        <KpiTile label="RBS Recorded" value={fmt(tested)} sub={pct(tested, screened)} accent="o" />
        <KpiTile label="RBS > 140"    value={fmt(above140)} sub={pct(above140, tested)} accent="g" />
        <KpiTile label="RBS > 200"    value={fmt(above200)} sub={pct(above200, tested)} accent="p" />
      </KpiGrid>

      <Section title="Diabetes Screening Cascade" accent="t">
        <Note>
          Random blood sugar is recorded at camp. <b>&gt; 140 mg/dL</b> is treated as raised;
          <b> &gt; 200 mg/dL</b> as strongly suggestive of diabetes and warranting referral.
        </Note>
      </Section>

      <Section title="Monthly Trends" accent="b">
        <div className="cg one">
          <TrendChart
            months={months}
            series={[
              { label: 'RBS recorded', data: series(data, 'n_rbs', months) },
              { label: 'RBS > 140',    data: series(data, 'n_rbs_140p', months) },
              { label: 'RBS > 200',    data: series(data, 'n_rbs_200p', months) },
            ]}
          />
        </div>
      </Section>

      <Section
        title="Diabetes Monthly Table"
        accent="n"
        actions={<button className="dl-btn" onClick={() => exportTableToXlsx('t-dm', 'Diabetes_Monthly')}>⬇ Excel</button>}
      >
        <MonthlyTable
          id="t-dm"
          months={months}
          rows={[
            monthlyRow(data, months, 'Screened',     'n_screened', true),
            monthlyRow(data, months, 'RBS Recorded', 'n_rbs'),
            pctRow(data, months,     '  Coverage',   'n_rbs', 'n_screened'),
            monthlyRow(data, months, 'RBS > 140',    'n_rbs_140p'),
            pctRow(data, months,     '  % of tested','n_rbs_140p', 'n_rbs'),
            monthlyRow(data, months, 'RBS > 200',    'n_rbs_200p'),
            pctRow(data, months,     '  % of tested','n_rbs_200p', 'n_rbs'),
          ]}
        />
      </Section>
    </>
  )
}

function HypertensionView({ data, months }: { data: MetricsResponse; months: string[] }) {
  const t = data.total
  const screened = m(t, 'n_screened')
  const tested   = m(t, 'n_bp')
  const above140 = m(t, 'n_bp_140p')
  const above160 = m(t, 'n_bp_160p')

  return (
    <>
      <KpiGrid>
        <KpiTile label="Screened"    value={fmt(screened)} />
        <KpiTile label="BP Recorded" value={fmt(tested)} sub={pct(tested, screened)} accent="o" />
        <KpiTile label="SBP ≥ 140"   value={fmt(above140)} sub={pct(above140, tested)} accent="g" />
        <KpiTile label="SBP ≥ 160"   value={fmt(above160)} sub={pct(above160, tested)} accent="p" />
      </KpiGrid>

      <Section title="Hypertension Screening Cascade" accent="t">
        <Note>
          Systolic blood pressure measured at camp. <b>≥ 140 mmHg</b> indicates raised BP;
          <b> ≥ 160 mmHg</b> indicates markedly raised BP requiring referral.
        </Note>
      </Section>

      <Section title="Monthly Trends" accent="b">
        <div className="cg one">
          <TrendChart
            months={months}
            series={[
              { label: 'BP recorded', data: series(data, 'n_bp', months) },
              { label: 'SBP ≥ 140',   data: series(data, 'n_bp_140p', months) },
              { label: 'SBP ≥ 160',   data: series(data, 'n_bp_160p', months) },
            ]}
          />
        </div>
      </Section>

      <Section
        title="Hypertension Monthly Table"
        accent="n"
        actions={<button className="dl-btn" onClick={() => exportTableToXlsx('t-ht', 'Hypertension_Monthly')}>⬇ Excel</button>}
      >
        <MonthlyTable
          id="t-ht"
          months={months}
          rows={[
            monthlyRow(data, months, 'Screened',      'n_screened', true),
            monthlyRow(data, months, 'BP Recorded',   'n_bp'),
            pctRow(data, months,     '  Coverage',    'n_bp', 'n_screened'),
            monthlyRow(data, months, 'SBP ≥ 140',     'n_bp_140p'),
            pctRow(data, months,     '  % of tested', 'n_bp_140p', 'n_bp'),
            monthlyRow(data, months, 'SBP ≥ 160',     'n_bp_160p'),
            pctRow(data, months,     '  % of tested', 'n_bp_160p', 'n_bp'),
          ]}
        />
      </Section>
    </>
  )
}

function ScdView({ data, months }: { data: MetricsResponse; months: string[] }) {
  const t = data.total
  const screened = m(t, 'n_scd_screen')
  const positive = m(t, 'n_scd_pos')
  const poct     = m(t, 'n_scd_poct')
  const poctPos  = m(t, 'n_scd_poct_pos')
  const sol      = m(t, 'n_scd_sol')
  const solPos   = m(t, 'n_scd_sol_pos')

  const methodRows = [
    { label: 'Point-of-care test (POCT)', tested: poct, positive: poctPos },
    { label: 'Solubility test',           tested: sol,  positive: solPos },
  ]

  return (
    <>
      <KpiGrid>
        <KpiTile label="SCD Screened" value={fmt(screened)} sub={pct(screened, m(t, 'n_screened'))} />
        <KpiTile label="Positive"     value={fmt(positive)} sub={pct(positive, screened)} accent="p" />
        <KpiTile label="POCT"         value={fmt(poct)} sub={`${fmt(poctPos)} positive`} accent="o" />
        <KpiTile label="Solubility"   value={fmt(sol)} sub={`${fmt(solPos)} positive`} accent="g" />
      </KpiGrid>

      <Section
        title="SCD Screening Summary"
        accent="t"
        actions={<button className="dl-btn" onClick={() => exportTableToXlsx('t-scd-sum', 'SCD_Summary')}>⬇ Excel</button>}
      >
        <DataTable
          id="t-scd-sum"
          rows={[...methodRows, {
            label: 'All methods', tested: screened, positive,
          }]}
          rowClassName={(_, i) => (i === methodRows.length ? 'cas-sub' : undefined)}
          columns={[
            { key: 'label',    header: 'Method',     cell: (r) => r.label, numeric: false },
            { key: 'tested',   header: 'Tested',     cell: (r) => fmt(r.tested) },
            { key: 'positive', header: 'Positive',   cell: (r) => fmt(r.positive) },
            { key: 'rate',     header: '% Positive', cell: (r) => pct(r.positive, r.tested, 2) },
          ]}
        />
      </Section>

      <Section title="Monthly Trends" accent="b">
        <div className="cg">
          <BarChart
            title="SCD screening by method"
            months={months}
            stacked
            series={[
              { label: 'POCT',       data: series(data, 'n_scd_poct', months) },
              { label: 'Solubility', data: series(data, 'n_scd_sol', months) },
            ]}
          />
          <TrendChart
            title="Positives detected"
            months={months}
            series={[{ label: 'SCD positive', data: series(data, 'n_scd_pos', months), fill: true }]}
          />
        </div>
      </Section>

      <Section
        title="SCD Monthly Table"
        accent="n"
        actions={<button className="dl-btn" onClick={() => exportTableToXlsx('t-scd', 'SCD_Monthly')}>⬇ Excel</button>}
      >
        <MonthlyTable
          id="t-scd"
          months={months}
          rows={[
            monthlyRow(data, months, 'SCD Screened',       'n_scd_screen', true),
            monthlyRow(data, months, 'POCT tested',        'n_scd_poct'),
            monthlyRow(data, months, 'POCT positive',      'n_scd_poct_pos'),
            monthlyRow(data, months, 'Solubility tested',  'n_scd_sol'),
            monthlyRow(data, months, 'Solubility positive','n_scd_sol_pos'),
            monthlyRow(data, months, 'Total positive',     'n_scd_pos', true),
            pctRow(data, months,     '  Positivity rate',  'n_scd_pos', 'n_scd_screen'),
          ]}
        />
      </Section>
    </>
  )
}

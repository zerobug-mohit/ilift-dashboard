import { useMemo } from 'react'
import {
  Chart as ChartJS, CategoryScale, LinearScale, PointElement, LineElement,
  BarElement, Title, Tooltip, Legend, Filler,
} from 'chart.js'
import { Line, Bar } from 'react-chartjs-2'
import type { ChartOptions } from 'chart.js'

ChartJS.register(
  CategoryScale, LinearScale, PointElement, LineElement, BarElement,
  Title, Tooltip, Legend, Filler,
)

/* ───────────────────────────────────────────────────────────────────────────
   SERIES PALETTE

   The dashboard's brand colors are kept for UI chrome (headers, tile borders,
   section bars) exactly as before. But the brand set is not safe as a *series*
   palette: validated with the dataviz palette checker, navy #1F4E79 and blue
   #2E75B6 separate by only ΔE 14.0 for normal vision — below the 15 floor, so
   two lines in those colors are hard to tell apart even with full color vision.
   Brand green #375623 against orange #C55A11 is worse under protanopia (ΔE 2.9).

   This order is re-stepped from the brand hues and passes all six checks in
   light mode: lightness band, chroma floor, CVD separation, normal-vision
   floor, and contrast against the surface. Assign in order; never cycle.

   The dashboard commits to light mode, matching the existing design.
   ─────────────────────────────────────────────────────────────────────────── */
export const SERIES = [
  '#2E75B6', // blue    — brand
  '#C55A11', // orange  — brand
  '#7030A0', // purple  — brand
  '#4E7A32', // green   — brand green, lightened into the readable band
  '#00A0B0', // teal
  '#B5476B', // rose
] as const

const INK = { primary: '#333', secondary: '#595959', muted: '#8A8A8A' }
const GRID = 'rgba(0,0,0,0.06)'

/** Series beyond the palette length fold into a single "Other" gray rather
 *  than cycling hues, which would reuse a color for a different entity. */
export const seriesColor = (i: number): string => SERIES[i] ?? '#9AA3AB'

const MONTH_LABEL: Record<string, string> = {}
export function monthLabel(ym: string | undefined | null): string {
  if (!ym) return '—'
  if (MONTH_LABEL[ym]) return MONTH_LABEL[ym]
  const [y, m] = ym.split('-')
  if (!y || !m) return ym
  const names = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']
  const out = `${names[Number(m) - 1] ?? m}-${y.slice(2)}`
  MONTH_LABEL[ym] = out
  return out
}

export interface Series {
  label: string
  data: (number | null)[]
  /** Override the palette slot; defaults to assignment order. */
  color?: string
  /** Render as a filled area under the line. */
  fill?: boolean
}

function baseOptions<T extends 'line' | 'bar'>(opts: {
  yTitle?: string
  showLegend: boolean
  percent?: boolean
}): ChartOptions<T> {
  const options = {
    responsive: true,
    maintainAspectRatio: false,
    interaction: { mode: 'index', intersect: false },
    plugins: {
      legend: {
        display: opts.showLegend,
        position: 'bottom',
        labels: {
          boxWidth: 10, boxHeight: 10, usePointStyle: true, pointStyle: 'rectRounded',
          font: { size: 10, family: 'Arial' },
          // Legend text stays ink-colored; the swatch carries identity.
          color: INK.secondary,
          padding: 12,
        },
      },
      tooltip: {
        backgroundColor: 'rgba(31,78,121,0.95)',
        titleFont: { size: 11, family: 'Arial', weight: 'bold' },
        bodyFont: { size: 11, family: 'Arial' },
        padding: 9,
        cornerRadius: 4,
        displayColors: true,
        boxWidth: 9,
        boxHeight: 9,
        usePointStyle: true,
        callbacks: {
          label: (ctx: { parsed: { y: number | null }; dataset: { label?: string } }) => {
            const v = ctx.parsed.y
            if (v === null || v === undefined) return `${ctx.dataset.label}: —`
            const s = opts.percent ? `${v.toFixed(1)}%` : v.toLocaleString('en-IN')
            return `${ctx.dataset.label}: ${s}`
          },
        },
      },
    },
    scales: {
      x: {
        grid: { display: false },
        border: { color: GRID },
        ticks: { font: { size: 10, family: 'Arial' }, color: INK.muted, maxRotation: 0 },
      },
      y: {
        beginAtZero: true,
        title: opts.yTitle
          ? { display: true, text: opts.yTitle, font: { size: 10, family: 'Arial' }, color: INK.muted }
          : undefined,
        grid: { color: GRID },
        border: { display: false },
        ticks: {
          font: { size: 10, family: 'Arial' },
          color: INK.muted,
          callback: (v: unknown) => (opts.percent ? `${v}%` : Number(v).toLocaleString('en-IN')),
        },
      },
    },
  }
  return options as unknown as ChartOptions<T>
}

export function TrendChart(props: {
  title?: string
  months: string[]
  series: Series[]
  yTitle?: string
  percent?: boolean
}) {
  const { months, series, yTitle, percent } = props

  const data = useMemo(() => ({
    labels: months.map(monthLabel),
    datasets: series.map((s, i) => ({
      label: s.label,
      data: s.data,
      borderColor: s.color ?? seriesColor(i),
      backgroundColor: s.fill ? `${s.color ?? seriesColor(i)}22` : (s.color ?? seriesColor(i)),
      borderWidth: 2,              // thin marks
      pointRadius: 0,              // clean line; points appear on hover
      pointHoverRadius: 5,
      pointHitRadius: 14,          // hit target larger than the mark
      pointBackgroundColor: s.color ?? seriesColor(i),
      pointBorderColor: '#fff',
      pointBorderWidth: 2,         // surface ring on overlapping marks
      fill: s.fill ?? false,
      tension: 0.25,
    })),
  }), [months.join(','), JSON.stringify(series)])

  return (
    <div className="cc">
      {props.title ? <ChartTitle>{props.title}</ChartTitle> : null}
      <div style={{ position: 'absolute', inset: props.title ? '32px 14px 14px' : 14 }}>
        <Line data={data} options={baseOptions<'line'>({ yTitle, showLegend: series.length >= 2, percent })} />
      </div>
    </div>
  )
}

export function BarChart(props: {
  title?: string
  months: string[]
  series: Series[]
  yTitle?: string
  stacked?: boolean
  percent?: boolean
}) {
  const { months, series, yTitle, stacked, percent } = props

  const data = useMemo(() => ({
    labels: months.map(monthLabel),
    datasets: series.map((s, i) => ({
      label: s.label,
      data: s.data,
      backgroundColor: s.color ?? seriesColor(i),
      borderColor: '#fff',
      // 2px surface gap between adjacent/stacked fills
      borderWidth: stacked ? { top: 2, right: 0, bottom: 0, left: 0 } : 0,
      borderRadius: 4,             // rounded data-end
      borderSkipped: 'start' as const,
      maxBarThickness: 34,
    })),
  }), [months.join(','), JSON.stringify(series), stacked])

  const options = baseOptions<'bar'>({ yTitle, showLegend: series.length >= 2, percent })
  if (stacked && options.scales) {
    options.scales.x = { ...options.scales.x, stacked: true }
    options.scales.y = { ...options.scales.y, stacked: true }
  }

  return (
    <div className="cc">
      {props.title ? <ChartTitle>{props.title}</ChartTitle> : null}
      <div style={{ position: 'absolute', inset: props.title ? '32px 14px 14px' : 14 }}>
        <Bar data={data} options={options as ChartOptions<'bar'>} />
      </div>
    </div>
  )
}

function ChartTitle({ children }: { children: React.ReactNode }) {
  return (
    <div style={{
      position: 'absolute', top: 12, left: 14, right: 14,
      fontSize: 11.5, fontWeight: 700, color: 'var(--navy)',
    }}>
      {children}
    </div>
  )
}

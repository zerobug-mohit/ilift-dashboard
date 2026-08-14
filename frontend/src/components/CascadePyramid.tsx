import { forwardRef } from 'react'
import { fmt, pct as pctStr } from './primitives'

/**
 * TB detection cascade as an inverted pyramid.
 * Ported from the inline SVG builder in build_v3.py:845-915 into a real
 * component, so it can be measured, tested and exported without string
 * concatenation.
 *
 * The ramp is a single indigo hue stepping light→dark, which is the correct
 * encoding for a magnitude cascade (sequential, not categorical).
 */

const RAMP: [string, string][] = [
  ['#1F2D5A', '#161f40'],
  ['#2E3F78', '#22305c'],
  ['#3A5296', '#2c3f74'],
  ['#4A6AAF', '#385287'],
  ['#6685C0', '#4e6699'],
  ['#8DA5CF', '#6d85aa'],
]

const SVG_W = 560
const MAX_W = 460
const STEP = 58
const LAY_H = 56
const PAD_TOP = 10
const BADGE_H = 52

export interface CascadeLayer {
  label: string
  value: number
  sub: string
}

export interface CascadeBadge {
  label: string
  value: string
}

export const CascadePyramid = forwardRef<SVGSVGElement, {
  layers: CascadeLayer[]
  badges: CascadeBadge[]
}>(function CascadePyramid({ layers, badges }, ref) {
  const n = layers.length
  const totalH = PAD_TOP + n * LAY_H + BADGE_H
  const widths = layers.map((_, i) => MAX_W - i * STEP)

  const badgeW = 150
  const gap = 14
  const totalBadgeW = badges.length * (badgeW + gap) - gap
  const badgeStartX = (SVG_W - totalBadgeW) / 2
  const badgeY = PAD_TOP + n * LAY_H + 8

  return (
    <svg
      ref={ref}
      xmlns="http://www.w3.org/2000/svg"
      viewBox={`0 0 ${SVG_W} ${totalH}`}
      width={SVG_W}
      height={totalH}
      style={{
        display: 'block',
        fontFamily: 'Arial, Helvetica, sans-serif',
        background: '#fafcff',
        borderRadius: 10,
        maxWidth: '100%',
      }}
      role="img"
      aria-label={`TB detection cascade: ${layers.map((l) => `${l.label} ${l.value}`).join(', ')}`}
    >
      <defs>
        {RAMP.map(([from, to], i) => (
          <linearGradient key={i} id={`casgrad${i}`} x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%" stopColor={from} />
            <stop offset="100%" stopColor={to} />
          </linearGradient>
        ))}
        <filter id="casShadow">
          <feDropShadow dx="0" dy="1" stdDeviation="2" floodColor="rgba(0,0,0,0.12)" />
        </filter>
      </defs>

      {/* Recessive background rules */}
      {layers.map((_, i) => (
        <line key={`g${i}`} x1={0} y1={PAD_TOP + i * LAY_H} x2={SVG_W} y2={PAD_TOP + i * LAY_H}
              stroke="#e8edf2" strokeWidth={1} />
      ))}

      {layers.map((l, i) => {
        const w = widths[i]
        const nw = i < n - 1 ? widths[i + 1] : w - STEP
        const xL = (SVG_W - w) / 2
        const xR = xL + w
        const nxL = (SVG_W - nw) / 2
        const nxR = nxL + nw
        const yT = PAD_TOP + i * LAY_H
        const yB = yT + LAY_H
        const cy = yT + LAY_H / 2

        return (
          <g key={l.label}>
            <polygon
              points={`${xL},${yT} ${xR},${yT} ${nxR},${yB} ${nxL},${yB}`}
              fill={`url(#casgrad${Math.min(i, RAMP.length - 1)})`}
              filter="url(#casShadow)"
            />
            {i < n - 1 && (
              <line x1={nxL} y1={yB} x2={nxR} y2={yB}
                    stroke="rgba(255,255,255,0.7)" strokeWidth={2} />
            )}
            {/* Direct labels — the cascade needs no legend */}
            <text x={SVG_W / 2} y={cy - 6} textAnchor="middle" fill="#fff"
                  fontSize={12.5} fontWeight={700} letterSpacing={0.2}>
              {l.label}: {fmt(l.value)}
            </text>
            <text x={SVG_W / 2} y={cy + 10} textAnchor="middle"
                  fill="rgba(255,255,255,0.80)" fontSize={10.5}>
              ({l.sub})
            </text>
          </g>
        )
      })}

      {badges.map((b, i) => {
        const bx = badgeStartX + i * (badgeW + gap)
        return (
          <g key={b.label}>
            <rect x={bx} y={badgeY} width={badgeW} height={34} rx={8}
                  fill="#2E3F78" opacity={0.95} />
            <text x={bx + badgeW / 2} y={badgeY + 13} textAnchor="middle"
                  fill="rgba(255,255,255,0.78)" fontSize={9.5} fontWeight={600} letterSpacing={0.5}>
              {b.label}
            </text>
            <text x={bx + badgeW / 2} y={badgeY + 28} textAnchor="middle"
                  fill="#fff" fontSize={13} fontWeight={700}>
              {b.value}
            </text>
          </g>
        )
      })}
    </svg>
  )
})

/** Contextual breakdown panel beside the pyramid (build_v3.py:940-958). */
export function ContextPanel(props: {
  boxes: {
    icon: string
    title: string
    color: string
    rows: { label: string; n: number; den: number }[]
  }[]
}) {
  return (
    <div style={{ flex: 1, minWidth: 240, display: 'flex', flexDirection: 'column', gap: 12 }}>
      {props.boxes.map((box) => (
        <div key={box.title} style={{
          borderRadius: 8, overflow: 'hidden', boxShadow: '0 1px 6px rgba(0,0,0,0.08)',
        }}>
          <div style={{
            background: box.color, color: '#fff', padding: '7px 14px',
            fontSize: 12, fontWeight: 700, display: 'flex', alignItems: 'center', gap: 6,
          }}>
            <span style={{ fontSize: 15 }} aria-hidden>{box.icon}</span>
            <span style={{ fontStyle: 'italic' }}>{box.title}</span>
          </div>
          <div style={{ background: '#fff', padding: '4px 14px 6px', fontSize: 12, color: '#444' }}>
            {box.rows.map((r) => {
              const width = r.den > 0 ? Math.min(100, Math.round((r.n / r.den) * 100)) : 0
              return (
                <div key={r.label} style={{ padding: '5px 0', borderBottom: '1px solid #f0f0f0' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 3 }}>
                    <span style={{ color: '#555' }}>{r.label}</span>
                    <span style={{ fontWeight: 700, color: '#2E3F78' }}>
                      {fmt(r.n)}
                      <span style={{ color: '#999', fontWeight: 400, fontSize: 11 }}>
                        {' '}({pctStr(r.n, r.den)})
                      </span>
                    </span>
                  </div>
                  <div style={{ height: 5, background: '#eef2f7', borderRadius: 3 }}>
                    <div style={{ height: 5, background: '#4A6AAF', borderRadius: 3, width: `${width}%` }} />
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      ))}
    </div>
  )
}

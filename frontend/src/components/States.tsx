import { useState } from 'react'
import { ConnectionError, HttpError } from '../api/client'
import { getApiOrigin, setApiBase, hasMixedContentRisk, isRemoteHostedWithLocalApi } from '../api/base'
import type { SourceStatus } from '../api/types'

/** Shown when the backend is up but no RIS export has been dropped in yet. */
export function NoData({ sources }: { sources: SourceStatus[] }) {
  return (
    <div className="state">
      <h2>No data loaded</h2>
      <p>
        Drop the source exports into <code>backend/data/incoming/</code> and click{' '}
        <strong>Refresh data</strong>.
      </p>
      <table style={{ margin: '18px auto 0', maxWidth: 520 }}>
        <thead>
          <tr><th>Source</th><th>Expected filename</th><th>Status</th></tr>
        </thead>
        <tbody>
          {EXPECTED.map((e) => {
            const s = sources.find((x) => x.key === e.key)
            return (
              <tr key={e.key}>
                <td className="ind">{e.label}</td>
                <td className="ind"><code>{e.pattern}</code></td>
                <td className="ind" style={{ color: s?.present ? 'var(--grn)' : 'var(--org)' }}>
                  {s?.present ? `✓ ${s.files.join(', ')}` : '— missing'}
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
      <p style={{ marginTop: 16, fontSize: 11 }}>
        No real export yet? Generate synthetic data to explore the interface:<br />
        <code>Rscript backend/scripts/make_fixtures.R</code>
      </p>
    </div>
  )
}

const EXPECTED = [
  { key: 'ris',     label: 'RIS Hub export',  pattern: 'incoming/ris*.xlsx' },
  { key: 'crd_mis', label: 'CRD MIS',         pattern: 'incoming/crd*.xlsx' },
  { key: 'nikshay', label: 'Nikshay quarters',pattern: 'incoming/nikshay/*.xlsx' },
] as const

export function LoadFailed({ error, onRetry }: { error: unknown; onRetry: () => void }) {
  const message = error instanceof Error ? error.message : String(error)
  const connection = error instanceof ConnectionError
  const remote = isRemoteHostedWithLocalApi()
  const mixed = hasMixedContentRisk()
  const [url, setUrl] = useState(getApiOrigin())

  // The backend is running and reachable, but it refuses this origin.
  // Distinguishable because the CORS filter deliberately makes its 403 readable.
  const blockedOrigin =
    error instanceof HttpError && (error.body as { error?: string })?.error === 'origin_not_allowed'

  if (blockedOrigin) {
    return (
      <div className="state error">
        <h2>The backend refused this dashboard</h2>
        <p style={{ marginBottom: 12 }}>
          The API at <code>{getApiOrigin()}</code> is running, but it does not accept
          requests from <code>{window.location.origin}</code>. That allowlist is what
          stops other websites reading your data, so it has to be told about this one.
        </p>
        <p style={{ margin: '14px 0 6px', fontWeight: 700, color: 'var(--navy)' }}>
          Restart the backend with this dashboard allowed:
        </p>
        <pre style={{
          background: 'var(--vlblue)', padding: '10px 12px', borderRadius: 5,
          fontSize: 11, overflowX: 'auto', color: 'var(--navy)',
        }}>
{`ILIFT_ALLOWED_ORIGINS=${window.location.origin} npm run dev:api`}
        </pre>
        <p style={{ fontSize: 11, marginTop: 10 }}>
          To make it permanent, add this line to <code>.Renviron</code> in the project root:
          <br />
          <code>ILIFT_ALLOWED_ORIGINS={window.location.origin}</code>
        </p>
        <button className="btn-r" style={{ marginTop: 14 }} onClick={onRetry}>Retry</button>
      </div>
    )
  }

  if (!connection) {
    return (
      <div className="state error">
        <h2>Could not load data</h2>
        <p style={{ marginBottom: 14 }}>{message}</p>
        <button className="btn-r" onClick={onRetry}>Retry</button>
      </div>
    )
  }

  return (
    <div className="state error">
      <h2>Can't reach the backend</h2>
      <p style={{ marginBottom: 12 }}>
        The dashboard is running, but no API is answering at{' '}
        <code>{getApiOrigin()}</code>.
      </p>

      {remote && (
        <p style={{ marginBottom: 12 }}>
          This page is hosted on the web, but the data lives on your machine — so you
          need the backend running locally for anything to appear. It is not something
          the site can start for you.
        </p>
      )}

      <p style={{ margin: '14px 0 6px', fontWeight: 700, color: 'var(--navy)' }}>
        Start it:
      </p>
      <pre style={{
        background: 'var(--vlblue)', padding: '10px 12px', borderRadius: 5,
        fontSize: 11, overflowX: 'auto', color: 'var(--navy)',
      }}>
{`cd "path/to/LIFT Dashboard"
npm run dev:api`}
      </pre>

      {mixed && (
        <p style={{ marginTop: 12, color: 'var(--org)' }}>
          <strong>Your browser may be blocking this.</strong> This page is served over
          HTTPS and the API is plain HTTP on a non-local address, which browsers block
          as mixed content. Use an address on <code>127.0.0.1</code>, or open the
          dashboard over HTTP.
        </p>
      )}

      <div style={{
        marginTop: 16, paddingTop: 14, borderTop: '1px solid var(--bdr)',
        display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap',
      }}>
        <label htmlFor="fix-api" style={{ fontSize: 11, fontWeight: 700, color: 'var(--navy)' }}>
          API URL
        </label>
        <input
          id="fix-api" value={url} onChange={(e) => setUrl(e.target.value)}
          style={{
            border: '1.5px solid var(--blue)', borderRadius: 4, padding: '5px 9px',
            fontSize: 11, minWidth: 240, fontFamily: 'monospace',
          }}
        />
        <button className="btn-r" onClick={() => { setApiBase(url); window.location.reload() }}>
          Save &amp; reload
        </button>
        <button className="dl-btn" onClick={onRetry}>Retry</button>
      </div>
    </div>
  )
}

/**
 * Column-resolution warnings. The legacy scripts addressed columns by position
 * with no validation, so a reordered export silently changed every number.
 * Surfacing this is the point of schema.R.
 */
export function SchemaWarnings({ warnings }: { warnings: string[] }) {
  return (
    <div className="banner">
      <strong>Column mapping needs review.</strong>{' '}
      {warnings.length} column{warnings.length === 1 ? '' : 's'} could not be confirmed
      from the export headers and fell back to the legacy position. Verify these before
      relying on the affected metrics:
      <ul style={{ margin: '6px 0 0 18px' }}>
        {warnings.slice(0, 6).map((w) => <li key={w}>{w}</li>)}
        {warnings.length > 6 && <li>…and {warnings.length - 6} more</li>}
      </ul>
    </div>
  )
}

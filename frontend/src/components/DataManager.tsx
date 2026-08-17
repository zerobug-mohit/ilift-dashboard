import { useRef, useState } from 'react'
import { useUpload } from '../api/client'
import {
  getApiOrigin, setApiBase, clearApiBase, DEFAULT_LOCAL_API,
  isRemoteHostedWithLocalApi, isProxied, hasExplicitBase,
} from '../api/base'
import type { MetaResponse, UploadSlot, UploadResponse } from '../api/types'

const SLOTS: { id: UploadSlot; label: string; hint: string; multiple: boolean }[] = [
  {
    id: 'ris',
    label: 'RIS Hub export',
    hint: 'The workbook with the "Logic sheet" and "RAW DATA (paste here)" tabs. Replaces the current file.',
    multiple: false,
  },
  {
    id: 'crd_mis',
    label: 'CRD MIS',
    hint: 'Google Sheet exported as .xlsx, containing the "New Master Sheet" tab. Replaces the current file.',
    multiple: false,
  },
  {
    id: 'nikshay',
    label: 'Nikshay quarterly files',
    hint: 'One file per quarter. These accumulate — uploading 26Q3 keeps the earlier quarters.',
    multiple: true,
  },
]

const fmtBytes = (n: number) =>
  n > 1024 * 1024 ? `${(n / 1024 / 1024).toFixed(1)} MB` : `${Math.round(n / 1024)} KB`

const fmtWhen = (iso: string | null) => {
  if (!iso) return '—'
  const d = new Date(iso)
  const days = Math.floor((Date.now() - d.getTime()) / 86_400_000)
  const rel = days === 0 ? 'today' : days === 1 ? 'yesterday' : `${days} days ago`
  return `${d.toLocaleDateString()} (${rel})`
}

export function DataManager({ meta, isAdmin = true }: { meta: MetaResponse; isAdmin?: boolean }) {
  return (
    <div className="main">
      <div className="sec">
        <div className="sh n">Loaded data</div>
        <div className="tw">
          <table>
            <thead>
              <tr>
                <th style={{ textAlign: 'left' }}>Source</th>
                <th style={{ textAlign: 'left' }}>File(s)</th>
                <th>Last updated</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {SLOTS.map((s) => {
                const st = meta.sources.find((x) => x.key === s.id)
                return (
                  <tr key={s.id}>
                    <td className="ind"><strong>{s.label}</strong></td>
                    <td className="ind" style={{ fontSize: 11 }}>
                      {st?.present ? st.files.join(', ') : <em style={{ color: 'var(--grey)' }}>none</em>}
                    </td>
                    <td className="num" style={{ fontSize: 11 }}>{fmtWhen(st?.modified ?? null)}</td>
                    <td className="num" style={{ color: st?.present ? 'var(--grn)' : 'var(--org)' }}>
                      {st?.present ? 'loaded' : 'missing'}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      </div>

      {isAdmin ? (
        <div className="sec">
          <div className="sh b">Upload new data</div>
          <div style={{
            background: '#fff', padding: 14, borderRadius: '0 0 7px 7px',
            display: 'grid', gap: 12, boxShadow: '0 1px 4px rgba(0,0,0,.07)',
          }}>
            {SLOTS.map((s) => <UploadSlotCard key={s.id} slot={s} />)}
          </div>
        </div>
      ) : (
        <div className="sec">
          <div className="sh g">Updating the data</div>
          <div style={{
            background: '#fff', padding: 14, borderRadius: '0 0 7px 7px',
            boxShadow: '0 1px 4px rgba(0,0,0,.07)', fontSize: 12,
            color: 'var(--grey)', lineHeight: 1.8,
          }}>
            You have viewing access. New exports are uploaded by whoever holds the
            admin token — the figures above update for everyone as soon as they do.
            <br />
            If you need to upload data yourself, ask them for the admin token and
            sign in with it instead of the viewing password.
          </div>
        </div>
      )}

      <ConnectionSettings meta={meta} canEdit={isAdmin} />
    </div>
  )
}

function UploadSlotCard({ slot }: { slot: typeof SLOTS[number] }) {
  const input = useRef<HTMLInputElement>(null)
  const [dragging, setDragging] = useState(false)
  const [result, setResult] = useState<UploadResponse | null>(null)
  const upload = useUpload()

  const send = (files: FileList | File[] | null) => {
    const list = Array.from(files ?? []).filter((f) => /\.xlsx?$/i.test(f.name))
    if (list.length === 0) return
    setResult(null)
    upload.mutate(
      { slot: slot.id, files: slot.multiple ? list : [list[0]] },
      { onSuccess: (r) => setResult(r) },
    )
  }

  const busy = upload.isPending

  return (
    <div
      onDragOver={(e) => { e.preventDefault(); setDragging(true) }}
      onDragLeave={() => setDragging(false)}
      onDrop={(e) => { e.preventDefault(); setDragging(false); send(e.dataTransfer.files) }}
      style={{
        border: `2px dashed ${dragging ? 'var(--blue)' : 'var(--bdr)'}`,
        background: dragging ? 'var(--vlblue)' : '#fcfdff',
        borderRadius: 8, padding: '12px 14px', transition: 'background .15s',
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap' }}>
        <div style={{ flex: 1, minWidth: 220 }}>
          <div style={{ fontWeight: 700, fontSize: 12, color: 'var(--navy)' }}>{slot.label}</div>
          <div style={{ fontSize: 11, color: 'var(--grey)', marginTop: 2 }}>{slot.hint}</div>
        </div>
        <input
          ref={input} type="file" accept=".xlsx,.xls" multiple={slot.multiple}
          style={{ display: 'none' }}
          onChange={(e) => { send(e.target.files); e.target.value = '' }}
        />
        <button className="btn-r" disabled={busy} onClick={() => input.current?.click()}>
          {busy ? 'Uploading…' : 'Choose file' + (slot.multiple ? 's' : '')}
        </button>
      </div>

      {upload.isError && (
        <div style={{ marginTop: 10, fontSize: 11, color: 'var(--red)' }}>
          {upload.error instanceof Error ? upload.error.message : 'Upload failed'}
        </div>
      )}

      {result && <UploadResult result={result} />}
    </div>
  )
}

function UploadResult({ result }: { result: UploadResponse }) {
  const { saved, failed, reload } = result
  return (
    <div style={{ marginTop: 10, fontSize: 11, lineHeight: 1.7 }}>
      {saved.map((s) => (
        <div key={s.stored} style={{ color: 'var(--grn)' }}>
          ✓ {s.original} ({fmtBytes(s.bytes)}) saved as <code>{s.stored}</code>
          {s.archived.length > 0 && (
            <span style={{ color: 'var(--grey)' }}>
              {' '}· replaced {s.archived.join(', ')} (moved to <code>incoming/archive/</code>)
            </span>
          )}
        </div>
      ))}

      {failed.map((f, i) => (
        <div key={i} style={{ color: 'var(--red)' }}>✗ {f.original}: {f.error}</div>
      ))}

      {reload?.ok ? (
        <div style={{ marginTop: 4, color: 'var(--navy)', fontWeight: 700 }}>
          Recomputed: {reload.rows?.toLocaleString('en-IN')} rows ·{' '}
          {reload.beneficiaries?.toLocaleString('en-IN')} beneficiaries ·{' '}
          {reload.months?.length} months. The dashboard is showing the new numbers.
        </div>
      ) : reload ? (
        <div style={{ marginTop: 4, color: 'var(--red)' }}>
          File saved, but it could not be read: {reload.message}
        </div>
      ) : null}

      {(reload?.schema_warnings?.length ?? 0) > 0 && (
        <div style={{ marginTop: 4, color: 'var(--org)' }}>
          {reload!.schema_warnings!.length} column(s) could not be confirmed from the
          headers — see the banner at the top of the page.
        </div>
      )}
    </div>
  )
}

function ConnectionSettings({ meta, canEdit = true }: { meta: MetaResponse; canEdit?: boolean }) {
  const proxied = isProxied()
  const remote = isRemoteHostedWithLocalApi()
  const [value, setValue] = useState(getApiOrigin())
  // Under the dev proxy there is nothing to configure, so keep the field out of
  // the way rather than inviting an edit that would break a working setup.
  // Viewers never get it: pointing the dashboard elsewhere is not their job,
  // and a wrong value looks identical to the server being down.
  const [showAdvanced, setShowAdvanced] = useState(canEdit && (!proxied || hasExplicitBase()))

  return (
    <div className="sec">
      <div className="sh g">Backend connection</div>
      <div style={{
        background: '#fff', padding: 14, borderRadius: '0 0 7px 7px',
        boxShadow: '0 1px 4px rgba(0,0,0,.07)', fontSize: 12,
      }}>
        {remote && (
          <p style={{ marginBottom: 10, color: 'var(--grey)', lineHeight: 1.7 }}>
            This page is hosted on the web, but your data stays on your machine — the
            dashboard reads it from a backend you run locally. Nothing is uploaded to
            the web host.
          </p>
        )}

        <div style={{ color: 'var(--grey)', lineHeight: 1.8, marginBottom: showAdvanced ? 12 : 0 }}>
          <strong style={{ color: 'var(--grn)' }}>Connected</strong>
          {proxied
            ? <> via this page's own address, forwarded to the backend on <code>{DEFAULT_LOCAL_API}</code>.</>
            : <> to <code>{getApiOrigin()}</code>.</>}
          <br />
          {meta.rows.toLocaleString('en-IN')} rows loaded{' '}
          {new Date(meta.loaded_at).toLocaleString()}.
        </div>

        {!showAdvanced && canEdit && (
          <button className="dl-btn" onClick={() => setShowAdvanced(true)}>
            Change API address
          </button>
        )}

        {showAdvanced && (
          <>
            <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
              <label htmlFor="api-url" style={{ fontWeight: 700, color: 'var(--navy)', fontSize: 11 }}>
                API URL
              </label>
              <input
                id="api-url"
                value={value}
                onChange={(e) => setValue(e.target.value)}
                placeholder={DEFAULT_LOCAL_API}
                style={{
                  border: '1.5px solid var(--blue)', borderRadius: 4, padding: '5px 9px',
                  fontSize: 11, minWidth: 260, fontFamily: 'monospace',
                }}
              />
              <button
                className="btn-r"
                onClick={() => { setApiBase(value); window.location.reload() }}
              >
                Save &amp; reload
              </button>
              <button
                className="dl-btn"
                onClick={() => { clearApiBase(); window.location.reload() }}
              >
                Reset to default
              </button>
            </div>
            <div style={{ marginTop: 8, color: 'var(--grey)', fontSize: 11, lineHeight: 1.8 }}>
              Change this only if the backend runs on a different port
              (<code>ILIFT_PORT</code>) or on another machine.
            </div>
          </>
        )}
      </div>
    </div>
  )
}

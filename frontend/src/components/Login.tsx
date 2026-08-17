import { useState } from 'react'
import { setCredential, clearCredential, hasCredential } from '../api/auth'

/**
 * Sign-in for a protected deployment.
 *
 * One field, because the server decides what the secret unlocks: the team
 * password grants viewing, the admin token additionally grants uploading.
 * Asking the user to first declare which kind they hold would only create a
 * way to get it wrong.
 */
export function Login({ onSignedIn, wrong }: { onSignedIn: () => void; wrong?: boolean }) {
  const [value, setValue] = useState('')
  const [touched, setTouched] = useState(false)

  const submit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!value.trim()) return
    setCredential(value)
    setTouched(true)
    onSignedIn()
  }

  return (
    <div className="state" style={{ maxWidth: 460 }}>
      <h2>iLIFT Dashboard</h2>
      <p style={{ marginBottom: 18 }}>
        This dashboard is password protected. Enter the password you were given.
      </p>

      {wrong && !touched && (
        <div className="banner" style={{ borderRadius: 6, marginBottom: 16, textAlign: 'left' }}>
          That password was not accepted. Check it and try again.
        </div>
      )}

      <form onSubmit={submit} style={{ display: 'flex', gap: 8, justifyContent: 'center', flexWrap: 'wrap' }}>
        <input
          type="password"
          autoFocus
          autoComplete="current-password"
          value={value}
          onChange={(e) => { setValue(e.target.value); setTouched(false) }}
          placeholder="Password"
          aria-label="Dashboard password"
          style={{
            border: '1.5px solid var(--blue)', borderRadius: 4, padding: '7px 11px',
            fontSize: 12, minWidth: 240,
          }}
        />
        <button className="btn-r" type="submit" disabled={!value.trim()}>Sign in</button>
      </form>

      <p style={{ marginTop: 18, fontSize: 11, color: 'var(--grey)', lineHeight: 1.8 }}>
        Everyone on the team uses the same viewing password. Uploading new data
        needs a separate admin token, held by whoever maintains the dataset.
      </p>

      {hasCredential() && (
        <button
          className="dl-btn"
          style={{ marginTop: 12 }}
          onClick={() => { clearCredential(); window.location.reload() }}
        >
          Clear saved password
        </button>
      )}
    </div>
  )
}

/** Header control: shows the current role and allows signing out. */
export function AuthBadge({ level, protectedMode }: { level: string; protectedMode: boolean }) {
  if (!protectedMode) return null

  return (
    <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
      <span
        className="badge"
        style={{ background: level === 'admin' ? 'var(--grn)' : 'rgba(255,255,255,0.18)' }}
        title={level === 'admin'
          ? 'You can view and upload data'
          : 'You can view the dashboard. Uploading needs the admin token.'}
      >
        {level === 'admin' ? 'Admin' : 'Viewer'}
      </span>
      <button
        className="dl-btn"
        style={{ background: 'transparent', color: '#fff', borderColor: 'rgba(255,255,255,0.45)' }}
        onClick={() => { clearCredential(); window.location.reload() }}
      >
        Sign out
      </button>
    </span>
  )
}

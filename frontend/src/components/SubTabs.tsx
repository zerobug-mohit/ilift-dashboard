import { useState, type ReactNode } from 'react'

export interface SubTab {
  id: string
  label: string
  render: () => ReactNode
}

export function SubTabs({ tabs }: { tabs: SubTab[] }) {
  const [active, setActive] = useState(tabs[0]?.id)
  const current = tabs.find((t) => t.id === active) ?? tabs[0]

  return (
    <>
      <div className="sub-tabs">
        {tabs.map((t) => (
          <button
            key={t.id}
            className={`st ${t.id === current?.id ? 'on' : ''}`}
            onClick={() => setActive(t.id)}
          >
            {t.label}
          </button>
        ))}
      </div>
      <div className="main">{current?.render()}</div>
    </>
  )
}

/** Wraps a query result: loading, error, and empty handled once. */
export function QueryGate<T>(props: {
  query: { data?: T; isLoading: boolean; isError: boolean; error: unknown }
  children: (data: T) => ReactNode
}) {
  const { query, children } = props
  if (query.isError) {
    const msg = query.error instanceof Error ? query.error.message : String(query.error)
    return <div className="state error"><h2>Could not load</h2><p>{msg}</p></div>
  }
  if (!query.data) {
    return <div className="state"><p>Loading…</p></div>
  }
  return <>{children(query.data)}</>
}

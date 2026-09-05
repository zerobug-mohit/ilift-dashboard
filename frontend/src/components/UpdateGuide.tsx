import type { MetaResponse } from '../api/types'

/**
 * Step-by-step for whoever maintains the data.
 *
 * This replaced the Data tab. Uploading no longer happens in the browser — the
 * exports go into a Google Drive folder and GitHub Actions does the rest — so a
 * tab full of upload controls described a workflow nobody uses any more.
 *
 * It also carries the provenance the Data tab used to show: when these figures
 * were generated, and which file each source came from. Without that, a reader
 * has no way to tell a figure from today apart from one from three weeks ago,
 * and the person updating has no way to confirm their upload was the file
 * actually picked up.
 */

const SOURCE_LABELS: Record<string, { name: string; folder: string; note: string }> = {
  ris: {
    name: 'RIS Hub export',
    folder: 'ris',
    note: 'Every file in the folder is combined',
  },
  crd_mis: {
    name: 'CRD MIS',
    folder: 'crd_mis',
    note: 'Every file in the folder is combined',
  },
  nikshay: {
    name: 'Nikshay',
    folder: 'nikshay',
    note: 'Every file in the folder is combined',
  },
}

const fmtWhen = (iso: string | null | undefined) => {
  if (!iso) return '—'
  const d = new Date(iso)
  const days = Math.floor((Date.now() - d.getTime()) / 86_400_000)
  const rel = days === 0 ? 'today' : days === 1 ? 'yesterday' : `${days} days ago`
  return `${d.toLocaleDateString()} (${rel})`
}

export function UpdateGuide({ meta }: { meta: MetaResponse }) {
  const generated = meta.generated_at ?? meta.loaded_at
  const generatedDate = generated ? new Date(generated) : null
  const staleDays = generatedDate
    ? Math.floor((Date.now() - generatedDate.getTime()) / 86_400_000)
    : null

  return (
    <div className="main">
      {/* Answers "am I looking at current numbers?" before anything else. */}
      <div className="sec">
        <div className={`sh ${staleDays !== null && staleDays > 35 ? 'o' : 'n'}`}>
          These figures
        </div>
        <div className="ug-card">
          <div className="ug-stamp">
            <div>
              <span className="ug-lab">Last updated</span>
              <strong>
                {generatedDate ? generatedDate.toLocaleString() : 'unknown'}
              </strong>
            </div>
            <div>
              <span className="ug-lab">Beneficiaries</span>
              <strong>{meta.beneficiaries?.toLocaleString() ?? '—'}</strong>
            </div>
            <div>
              <span className="ug-lab">Months covered</span>
              <strong>
                {meta.months.length > 0
                  ? `${meta.months[0]} – ${meta.months[meta.months.length - 1]}`
                  : '—'}
              </strong>
            </div>
          </div>
          <p className="ug-note">
            The numbers do not change between updates. If you need something more
            recent than the date above, follow the steps below — or ask whoever
            maintains the data to.
          </p>
          {staleDays !== null && staleDays > 35 && (
            <p className="ug-warn">
              These figures are {staleDays} days old. That is longer than the
              usual monthly refresh, so they may be behind.
            </p>
          )}
        </div>
      </div>

      <div className="sec">
        <div className="sh b">Updating the dashboard</div>
        <div className="ug-card">
          <ol className="ug-steps">
            <li>
              <strong>Download the three raw exports</strong>
              <p>
                RIS Hub, the CRD MIS sheet, and the Nikshay quarterly file if
                there is a new one. Download them as they come — there is no
                Excel step and nothing to paste. The dashboard computes the
                Logic sheet itself.
              </p>
            </li>

            <li>
              <strong>Put each one in its Drive folder</strong>
              <p>
                Open the shared <strong>iLIFT data</strong> folder and drop each
                file into the matching subfolder:
              </p>
              <div className="tw" style={{ margin: '10px 0 4px' }}>
                <table>
                  <thead>
                    <tr>
                      <th style={{ textAlign: 'left' }}>Source</th>
                      <th style={{ textAlign: 'left' }}>Drive folder</th>
                      <th style={{ textAlign: 'left' }}>Previous file</th>
                    </tr>
                  </thead>
                  <tbody>
                    {Object.entries(SOURCE_LABELS).map(([key, s]) => (
                      <tr key={key}>
                        <td className="ind"><strong>{s.name}</strong></td>
                        <td className="ind"><code>{s.folder}/</code></td>
                        <td className="ind" style={{ fontSize: 11 }}>{s.note}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <p style={{ fontSize: 11 }}>
                <strong>If an export is too big to download in one go</strong>,
                save it as several files — <code>ris1.csv</code>,{' '}
                <code>ris2.csv</code>, <code>ris3.csv</code> — and put them all
                in the folder. They are combined into one table, with each
                file's header row read once rather than treated as data.
              </p>
              <p style={{ fontSize: 11 }}>
                Uploading the same file twice is harmless; identical rows are
                dropped. But do clear out last month's export once this
                month's is in, since keeping both leaves the older version of
                any record that has since been corrected.
              </p>
            </li>

            <li>
              <strong>Start the refresh</strong>
              <p>
                In GitHub, open <strong>Actions</strong> →{' '}
                <strong>Refresh dashboard from Drive</strong> →{' '}
                <strong>Run workflow</strong>.
              </p>
              <p>
                It takes about ten minutes. A green tick means this dashboard is
                updated. A red cross means nothing was published and the figures
                above are still the previous ones — so a failed run never puts
                wrong numbers in front of anyone.
              </p>
              <p style={{ fontSize: 11 }}>
                Forgetting this step is fine: the dashboard also refreshes by
                itself each morning at about 11:30 IST.
              </p>
            </li>

            <li>
              <strong>Check it before circulating</strong>
              <p>
                Come back to this tab and confirm <em>Last updated</em> shows
                today, and that the file names below are the ones you uploaded.
                If an orange banner appeared at the top of the page, a column
                could not be matched — check those figures against the Excel
                dashboard before sending anything out.
              </p>
            </li>
          </ol>
        </div>
      </div>

      <div className="sec">
        <div className="sh g">Where these numbers came from</div>
        <div className="tw">
          <table>
            <thead>
              <tr>
                <th style={{ textAlign: 'left' }}>Source</th>
                <th style={{ textAlign: 'left' }}>File used</th>
                <th>Dated</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {Object.entries(SOURCE_LABELS).map(([key, s]) => {
                const st = meta.sources.find((x) => x.key === key)
                return (
                  <tr key={key}>
                    <td className="ind"><strong>{s.name}</strong></td>
                    <td className="ind" style={{ fontSize: 11, wordBreak: 'break-all' }}>
                      {st?.present
                        ? st.files.join(', ')
                        : <em style={{ color: 'var(--grey)' }}>none</em>}
                    </td>
                    <td className="num" style={{ fontSize: 11 }}>
                      {fmtWhen(st?.modified ?? null)}
                    </td>
                    <td className="num" style={{ color: st?.present ? 'var(--grn)' : 'var(--org)' }}>
                      {st?.present ? 'loaded' : 'missing'}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
        <p className="ug-note" style={{ padding: '0 2px' }}>
          Only aggregate numbers are published here. The beneficiary records
          themselves stay in Drive and are never part of this page.
        </p>
      </div>

      <div className="sec">
        <div className="sh o">If something goes wrong</div>
        <div className="ug-card">
          <dl className="ug-faq">
            <dt>The run failed</dt>
            <dd>
              Open the red run in <strong>Actions</strong> and read the step that
              failed. "No RIS export was found" means the file is not inside the{' '}
              <code>ris/</code> subfolder. Nothing was published, so the figures
              above are unchanged.
            </dd>

            <dt>The run was green but nothing changed</dt>
            <dd>
              Most likely the new file went into the wrong subfolder, so the old
              one is still the newest. The table above shows the file actually
              used — check it against what you uploaded.
            </dd>

            <dt>An orange banner about columns</dt>
            <dd>
              A column could not be matched by its heading, usually because RIS
              Hub changed its export. The banner names the affected figures —
              check those against the Excel dashboard before relying on them.
            </dd>
          </dl>
        </div>
      </div>
    </div>
  )
}

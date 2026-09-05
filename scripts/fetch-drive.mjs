#!/usr/bin/env node
/**
 * Pull the source workbooks out of a Google Drive folder.
 *
 *   node scripts/fetch-drive.mjs
 *
 * Why this exists: the person who refreshes the data should not have to install
 * R and Node. They drop the exports into a Drive folder; this runs in GitHub
 * Actions, fetches them, and the existing pipeline takes over unchanged.
 *
 * Expects a Drive folder laid out as:
 *
 *   <root folder>/
 *     ris/        newest file wins  — the export is cumulative, so it replaces
 *     crd_mis/    newest file wins  — likewise
 *     nikshay/    every file kept   — quarterly files accumulate
 *
 * That mirrors the replace/accumulate rules the upload endpoint already applies
 * (uploads.R:65-73), so the numbers come out identical either way.
 *
 * Environment:
 *   GDRIVE_SA_KEY      service-account JSON, as a single-line string
 *   GDRIVE_FOLDER_ID   id of the root folder (from its URL)
 *   ILIFT_DATA_DIR     where to write (default: backend/data)
 *
 * This handles beneficiary records, so it prints names, sizes and counts only —
 * never file contents. Anything it writes is deleted by the workflow after the
 * aggregates are computed.
 */

import { google } from 'googleapis'
import { mkdirSync, rmSync, existsSync, createWriteStream, readdirSync, statSync } from 'node:fs'
import path from 'node:path'
import { pipeline } from 'node:stream/promises'

const ROOT = path.resolve(import.meta.dirname, '..')
const DATA_DIR = process.env.ILIFT_DATA_DIR
  ? path.resolve(process.env.ILIFT_DATA_DIR)
  : path.join(ROOT, 'backend', 'data')
const INCOMING = path.join(DATA_DIR, 'incoming')

/**
 * Drive subfolder → how the pipeline expects the file to land.
 *
 * `prefix` matters: find_source() matches on it (config.R:52-56), so a file
 * arriving without it is silently invisible to the dashboard.
 */
const SLOTS = [
  { folder: 'ris',     dir: INCOMING,                          prefix: 'ris_', keepAll: false },
  { folder: 'crd_mis', dir: INCOMING,                          prefix: 'crd_', keepAll: false },
  { folder: 'nikshay', dir: path.join(INCOMING, 'nikshay'),    prefix: '',     keepAll: true  },
]

const XLSX = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
const GOOGLE_SHEET = 'application/vnd.google-apps.spreadsheet'
const FOLDER = 'application/vnd.google-apps.folder'

function fail(msg, hint) {
  console.error(`\n✗ ${msg}`)
  if (hint) console.error(`  ${hint}`)
  process.exit(1)
}

function auth() {
  const raw = process.env.GDRIVE_SA_KEY
  if (!raw) {
    fail(
      'GDRIVE_SA_KEY is not set.',
      'In GitHub: Settings → Secrets and variables → Actions → New repository secret.',
    )
  }
  let creds
  try {
    creds = JSON.parse(raw)
  } catch {
    fail(
      'GDRIVE_SA_KEY is not valid JSON.',
      'Paste the whole service-account key file, including the surrounding { }.',
    )
  }
  if (!creds.client_email || !creds.private_key) {
    fail('GDRIVE_SA_KEY is missing client_email or private_key — not a service-account key.')
  }
  return new google.auth.GoogleAuth({
    credentials: creds,
    // Read-only: this job never needs to modify anything in Drive.
    scopes: ['https://www.googleapis.com/auth/drive.readonly'],
  })
}

/** Every non-trashed child of a folder. Shared Drives need the extra flags. */
async function listChildren(drive, parentId) {
  const files = []
  let pageToken
  do {
    const res = await drive.files.list({
      q: `'${parentId}' in parents and trashed = false`,
      fields: 'nextPageToken, files(id, name, mimeType, modifiedTime, size)',
      orderBy: 'modifiedTime desc',
      pageSize: 200,
      supportsAllDrives: true,
      includeItemsFromAllDrives: true,
      pageToken,
    })
    files.push(...(res.data.files ?? []))
    pageToken = res.data.nextPageToken
  } while (pageToken)
  return files
}

async function download(drive, file, dest) {
  // A file dragged into Drive stays .xlsx; one Drive converted becomes a Google
  // Sheet, which has no bytes to download and must be exported instead.
  const isNative = file.mimeType === GOOGLE_SHEET
  const res = isNative
    ? await drive.files.export(
        { fileId: file.id, mimeType: XLSX },
        { responseType: 'stream' },
      )
    : await drive.files.get(
        { fileId: file.id, alt: 'media', supportsAllDrives: true },
        { responseType: 'stream' },
      )

  mkdirSync(path.dirname(dest), { recursive: true })
  await pipeline(res.data, createWriteStream(dest))
  return { converted: isNative, bytes: statSync(dest).size }
}

/** Make a Drive filename safe on disk and matchable by find_source(). */
function localName(prefix, name) {
  const base = name.replace(/\.(xlsx|xls)$/i, '').replace(/[^A-Za-z0-9._-]+/g, '_')
  return `${prefix}${base}.xlsx`
}

const main = async () => {
  const folderId = process.env.GDRIVE_FOLDER_ID
  if (!folderId) {
    fail(
      'GDRIVE_FOLDER_ID is not set.',
      'It is the last part of the folder URL: drive.google.com/drive/folders/<THIS>',
    )
  }

  const drive = google.drive({ version: 'v3', auth: auth() })

  console.log('Fetching source workbooks from Google Drive\n')

  let root
  try {
    root = await drive.files.get({
      fileId: folderId,
      fields: 'id, name, mimeType',
      supportsAllDrives: true,
    })
  } catch (e) {
    const code = e?.code ?? e?.response?.status
    if (code === 404) {
      fail(
        'That folder was not found, or the service account cannot see it.',
        'Share the folder with the service account\'s client_email (Viewer is enough).',
      )
    }
    fail(`Could not reach Drive (${code ?? 'unknown error'}): ${e.message}`)
  }
  if (root.data.mimeType !== FOLDER) {
    fail(`GDRIVE_FOLDER_ID points at "${root.data.name}", which is not a folder.`)
  }
  console.log(`  root folder: ${root.data.name}\n`)

  const children = await listChildren(drive, folderId)
  const subfolders = new Map(
    children.filter((f) => f.mimeType === FOLDER).map((f) => [f.name.toLowerCase(), f]),
  )

  // Clear previous workbooks so a file removed from Drive also disappears here,
  // rather than lingering and quietly feeding stale figures. Only spreadsheets
  // are removed — .gitkeep and the archive/ folder are left alone.
  const clearWorkbooks = (dir) => {
    if (!existsSync(dir)) return
    for (const name of readdirSync(dir)) {
      if (/\.(xlsx|xls)$/i.test(name)) rmSync(path.join(dir, name), { force: true })
    }
  }
  mkdirSync(INCOMING, { recursive: true })
  clearWorkbooks(INCOMING)
  clearWorkbooks(path.join(INCOMING, 'nikshay'))

  let fetched = 0
  const missing = []

  for (const slot of SLOTS) {
    const folder = subfolders.get(slot.folder)
    if (!folder) {
      missing.push(slot.folder)
      console.log(`  ${slot.folder.padEnd(9)} — no such subfolder, skipping`)
      continue
    }

    const all = await listChildren(drive, folder.id)
    const sheets = all.filter(
      (f) => f.mimeType === GOOGLE_SHEET || /\.(xlsx|xls)$/i.test(f.name),
    )

    if (sheets.length === 0) {
      missing.push(slot.folder)
      console.log(`  ${slot.folder.padEnd(9)} — empty, skipping`)
      continue
    }

    // Newest-first from the API; a cumulative export means only the latest counts.
    const take = slot.keepAll ? sheets : [sheets[0]]

    for (const f of take) {
      const dest = path.join(slot.dir, localName(slot.prefix, f.name))
      const { converted, bytes } = await download(drive, f, dest)
      fetched++
      console.log(
        `  ${slot.folder.padEnd(9)} ← ${f.name}` +
        `  (${(bytes / 1024).toFixed(0)} KB${converted ? ', exported from Google Sheets' : ''})`,
      )
    }

    if (!slot.keepAll && sheets.length > 1) {
      console.log(
        `  ${' '.repeat(9)}   ${sheets.length - 1} older file(s) ignored — newest wins`,
      )
    }
  }

  if (fetched === 0) {
    fail(
      'No source files were found in Drive.',
      `Expected subfolders named: ${SLOTS.map((s) => s.folder).join(', ')}`,
    )
  }

  // RIS is the only source the dashboard cannot do without.
  const haveRis = readdirSync(INCOMING).some((f) => /^ris.*\.xlsx?$/i.test(f))
  if (!haveRis) {
    fail(
      'No RIS export was found — the dashboard cannot compute anything without it.',
      'Put the RIS Hub export in the "ris" subfolder of the Drive folder.',
    )
  }

  console.log(`\n✓ ${fetched} file(s) fetched into ${path.relative(ROOT, INCOMING)}`)
  if (missing.length) {
    console.log(`  note: nothing found for ${missing.join(', ')} — those metrics will be zero`)
  }
}

main().catch((e) => {
  // Never let an API error dump record contents into a public build log.
  console.error(`\n✗ Drive fetch failed: ${e.message}`)
  process.exit(1)
})

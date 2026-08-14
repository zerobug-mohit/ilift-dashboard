#!/usr/bin/env node
/**
 * Locate Rscript and run an R script with it.
 *
 *   node scripts/run-r.mjs backend/scripts/serve.R
 *
 * R installs on Windows are frequently not on PATH, so rather than making every
 * developer fix their environment, this resolves the newest install it can find.
 * Override with ILIFT_RSCRIPT if you need a specific version.
 */
import { spawn, spawnSync } from 'node:child_process'
import { existsSync, readdirSync } from 'node:fs'
import path from 'node:path'

function onPath() {
  const probe = spawnSync(process.platform === 'win32' ? 'where' : 'which', ['Rscript'], {
    encoding: 'utf8',
  })
  if (probe.status === 0) {
    const first = probe.stdout.split(/\r?\n/).find(Boolean)
    if (first && existsSync(first.trim())) return first.trim()
  }
  return null
}

/** Every R under the standard Windows install roots, newest first. */
function windowsInstalls() {
  const roots = [
    'C:\\Program Files\\R',
    'C:\\Program Files (x86)\\R',
    path.join(process.env.LOCALAPPDATA ?? '', 'Programs', 'R'),
  ].filter((r) => r && existsSync(r))

  const candidates = []
  for (const root of roots) {
    for (const dir of readdirSync(root)) {
      for (const sub of ['bin\\x64\\Rscript.exe', 'bin\\Rscript.exe']) {
        const p = path.join(root, dir, sub)
        if (existsSync(p)) candidates.push({ p, v: version(dir) })
      }
    }
  }
  candidates.sort((a, b) => cmp(b.v, a.v))
  return candidates.map((c) => c.p)
}

const version = (name) => (name.match(/(\d+)\.(\d+)\.(\d+)/)?.slice(1) ?? ['0', '0', '0']).map(Number)
const cmp = (a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2]

/**
 * Does this R install have the packages we need?
 * The newest R on a machine is often a fresh install with an empty library,
 * while the packages live under an older version — so "newest" alone is the
 * wrong choice. Verify before committing to a candidate.
 */
const REQUIRED = ['plumber', 'dplyr', 'readxl', 'jsonlite', 'digest']

function hasPackages(rscript) {
  const check = spawnSync(
    rscript,
    ['-e', `q(status = if (all(c(${REQUIRED.map((p) => `"${p}"`).join(',')}) %in% rownames(installed.packages()))) 0 else 1)`],
    { encoding: 'utf8', timeout: 60_000 },
  )
  return check.status === 0
}

function resolveRscript() {
  const explicit = process.env.ILIFT_RSCRIPT
  if (explicit) {
    if (!existsSync(explicit)) {
      console.error(`ILIFT_RSCRIPT points at a missing file: ${explicit}`)
      process.exit(1)
    }
    return explicit
  }

  const candidates = [onPath(), ...(process.platform === 'win32' ? windowsInstalls() : [])]
    .filter(Boolean)

  const ready = candidates.find(hasPackages)
  if (ready) return ready

  if (candidates.length > 0) {
    console.error(
      `Found R at ${candidates[0]}, but it is missing required packages.\n` +
      `  Install them with:\n` +
      `    "${candidates[0]}" -e "install.packages(c(${REQUIRED.map((p) => `'${p}'`).join(', ')}), repos='https://cloud.r-project.org')"\n` +
      `  Or point ILIFT_RSCRIPT at an R install that already has them.`,
    )
    process.exit(1)
  }
  return null
}

const script = process.argv[2]
if (!script) {
  console.error('usage: node scripts/run-r.mjs <script.R> [args…]')
  process.exit(1)
}

const rscript = resolveRscript()
if (!rscript) {
  console.error(
    'Could not find Rscript.\n' +
    '  Install R (https://cran.r-project.org), add it to PATH,\n' +
    '  or set ILIFT_RSCRIPT to the full path of Rscript.exe',
  )
  process.exit(1)
}

spawn(rscript, [script, ...process.argv.slice(3)], { stdio: 'inherit' })
  .on('exit', (code) => process.exit(code ?? 0))

#!/usr/bin/env node
/**
 * Publish a snapshot of the dashboard: no server, no hosting cost, and the
 * beneficiary records never leave this machine.
 *
 *   node scripts/publish.mjs                    build into publish/
 *   node scripts/publish.mjs --push             ...and push to the gh-pages branch
 *   node scripts/publish.mjs --root            for Cloudflare Pages / a custom domain
 *
 * What it does:
 *   1. Runs export_static.R, which precomputes every month-range and gender
 *      combination as JSON. Ranges are computed individually, never by summing
 *      months — see the note in that script for why that matters.
 *   2. Builds the frontend in static mode so it reads those files.
 *   3. Assembles publish/ — the whole thing, ready to host anywhere.
 *
 * Only aggregate numbers end up in publish/. The RIS workbook is not copied.
 */

import { spawnSync } from 'node:child_process'
import { existsSync, rmSync, mkdirSync, cpSync, readdirSync, statSync, writeFileSync } from 'node:fs'
import path from 'node:path'

const ROOT = path.resolve(import.meta.dirname, '..')
const PUBLISH = path.join(ROOT, 'publish')

const args = process.argv.slice(2)
const flag = (name, fallback = null) => {
  const i = args.indexOf(name)
  return i >= 0 && args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : fallback
}
const has = (name) => args.includes(name)

/**
 * Where the site will be served from.
 *
 * GitHub Pages serves a project site from /<repo>/, so assets need that prefix.
 * Cloudflare Pages and custom domains serve from the root — use --root for that
 * rather than `--base /`, because Git Bash rewrites a lone "/" argument into a
 * Windows path (it becomes "/Program Files/Git/", which silently produces a
 * build whose asset URLs 404).
 */
function resolveBase() {
  if (has('--root')) return '/'

  const raw = flag('--base', '/ilift-dashboard/')

  // Detect the Git Bash rewrite rather than building something broken.
  if (/Program Files|^[A-Za-z]:[\\/]/.test(raw)) {
    console.error(`✗ --base looks path-mangled: "${raw}"`)
    console.error('  Git Bash rewrites "/" into a Windows path. Use --root to serve')
    console.error('  from the domain root, or --base ilift-dashboard for a subpath.')
    process.exit(1)
  }

  // Accept "ilift-dashboard", "/ilift-dashboard", "ilift-dashboard/" alike.
  const trimmed = raw.replace(/^\/+|\/+$/g, '')
  return trimmed ? `/${trimmed}/` : '/'
}

const base = resolveBase()
const doPush = has('--push')
const branch = flag('--branch', 'gh-pages')

const run = (cmd, cmdArgs, opts = {}) => {
  const r = spawnSync(cmd, cmdArgs, { stdio: 'inherit', shell: false, cwd: ROOT, ...opts })
  if (r.status !== 0) {
    console.error(`\n✗ failed: ${cmd} ${cmdArgs.join(' ')}`)
    process.exit(r.status ?? 1)
  }
}

const dirSize = (dir) => {
  let total = 0
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name)
    total += entry.isDirectory() ? dirSize(p) : statSync(p).size
  }
  return total
}

console.log('iLIFT — publish snapshot')
console.log(`  base path : ${base}`)
console.log(`  output    : ${PUBLISH}`)
console.log(`  push      : ${doPush ? `yes (${branch})` : 'no'}\n`)

// Start clean so a shrinking reporting period cannot leave stale range files
// behind, which would otherwise still be reachable by URL.
if (existsSync(PUBLISH)) {
  try {
    rmSync(PUBLISH, { recursive: true, force: true })
  } catch (e) {
    // Windows refuses to remove a directory another process has open — most
    // often `npx serve publish` left running from a previous preview.
    if (e.code === 'EPERM' || e.code === 'EBUSY') {
      console.error(`✗ Cannot clear ${PUBLISH} — something has it open.`)
      console.error('  A preview server is the usual cause. Stop it and try again')
      console.error('  (close the terminal running `npx serve publish`).')
      process.exit(1)
    }
    throw e
  }
}
mkdirSync(PUBLISH, { recursive: true })

console.log('── 1/3  Precomputing every view ─────────────────────────────')
run('node', ['scripts/run-r.mjs', 'backend/scripts/export_static.R', path.join(PUBLISH, 'data')])

console.log('\n── 2/3  Building the frontend (static mode) ─────────────────')
run('npm', ['--prefix', 'frontend', 'run', 'build'], {
  env: { ...process.env, VITE_DATA_MODE: 'static', VITE_BASE: base, VITE_API_BASE: '' },
  shell: process.platform === 'win32',
})

console.log('\n── 3/3  Assembling publish/ ─────────────────────────────────')
const dist = path.join(ROOT, 'frontend', 'dist')
if (!existsSync(path.join(dist, 'index.html'))) {
  console.error('✗ frontend build produced no index.html')
  process.exit(1)
}
for (const entry of readdirSync(dist)) {
  cpSync(path.join(dist, entry), path.join(PUBLISH, entry), { recursive: true })
}

// Static hosts have no rewrite rules; a copy of index.html as 404.html keeps
// a reloaded deep link working.
cpSync(path.join(PUBLISH, 'index.html'), path.join(PUBLISH, '404.html'))

// Tells GitHub Pages not to run the output through Jekyll, which would hide
// any directory beginning with an underscore.
writeFileSync(path.join(PUBLISH, '.nojekyll'), '')

// Guard: the export writes aggregates only, but this is the step that makes
// files public, so check rather than assume.
const leaked = spawnSync('grep', ['-rl', '-E', 'IL[0-9]{5}', path.join(PUBLISH, 'data')], {
  encoding: 'utf8',
})
if (leaked.stdout && leaked.stdout.trim()) {
  console.error('\n✗ ABORTING: beneficiary-shaped identifiers found in the output:')
  console.error(leaked.stdout.trim().split('\n').slice(0, 5).join('\n'))
  console.error('\nDo not publish this. Report it as a bug in export_static.R.')
  process.exit(1)
}

const mb = (dirSize(PUBLISH) / 1024 ** 2).toFixed(1)
console.log(`\n✓ publish/ ready — ${mb} MB`)
console.log('  aggregates only; no beneficiary identifiers found')

if (!doPush) {
  console.log('\nTo preview locally:')
  console.log('  npx serve publish')
  console.log('\nTo publish:')
  console.log('  node scripts/publish.mjs --push          (GitHub Pages, /repo/ subpath)')
  console.log('  ...or upload the publish/ folder to Cloudflare Pages')
  process.exit(0)
}

console.log(`\n── Pushing to ${branch} ─────────────────────────────────────`)

// A fresh orphan commit each time, force-pushed: the snapshot is ~13 MB, so
// accumulating history would add that much to the repo on every publish.
const remote = spawnSync('git', ['remote', 'get-url', 'origin'], { encoding: 'utf8', cwd: ROOT })
if (remote.status !== 0) {
  console.error('✗ no git remote "origin" — push manually or add one')
  process.exit(1)
}

const stamp = new Date().toISOString().replace('T', ' ').slice(0, 16)
const tmpGit = path.join(PUBLISH, '.git')
if (existsSync(tmpGit)) rmSync(tmpGit, { recursive: true, force: true })

const git = (...a) => run('git', a, { cwd: PUBLISH })
git('init', '-q')
git('checkout', '-q', '-b', branch)
git('add', '-A')
run('git', ['-c', 'core.autocrlf=false', 'commit', '-q', '-m', `Published snapshot ${stamp}`], { cwd: PUBLISH })
git('remote', 'add', 'origin', remote.stdout.trim())
git('push', '-q', '--force', 'origin', branch)

rmSync(tmpGit, { recursive: true, force: true })

console.log(`\n✓ pushed to ${branch}`)
console.log('\nIf this is the first publish, set the Pages source once:')
console.log('  GitHub → Settings → Pages → Source: "Deploy from a branch"')
console.log(`  Branch: ${branch} / (root)`)
console.log('\nThe site updates a minute or two after each push.')

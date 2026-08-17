# iLIFT Dashboard

Integrated Lung Health for Tribals — programme dashboard.

A Vite + React frontend over a Plumber (R) API. Metrics are computed **per
request** from the current contents of `backend/data/incoming/`, so refreshing
the data is a file drop, not a rebuild.

This replaces the previous pipeline, which ended in a static HTML file
(`build_v3.py`) that could not update as data refreshed.

---

## Quick start

```bash
npm install                # once, at the repo root
npm --prefix frontend install
npm run fixtures           # synthetic data, so there's something to look at
npm run dev                # starts API (:8000) and web (:5173) together
```

Open <http://localhost:5173>.

`npm run dev` locates R for you — R is often not on PATH on Windows. If it
cannot find a suitable install it prints the exact `install.packages(...)` line
to run. Override the choice with `ILIFT_RSCRIPT=/path/to/Rscript.exe`.

Prefer separate terminals? `npm run dev:api` and `npm run dev:web`.

> Fixture data is randomly generated and clinically meaningless. It exists to
> exercise the code paths, not to inform decisions.

---

## Refreshing the data

Two ways, same result.

**From the dashboard (easiest).** Open the **Data** tab, drag each export onto
its box, or use *Choose file*. The backend saves it, recomputes, and the numbers
update — no restart, no rebuild. RIS and CRD MIS replace the current file (the
old one moves to `incoming/archive/`); Nikshay files accumulate.

**By hand.** Drop files into the folder and click **Refresh data** in the header:

| Source | Drop into | Filename must match |
|---|---|---|
| RIS Hub export | `backend/data/incoming/` | `ris*.xlsx` |
| CRD MIS ("New Master Sheet") | `backend/data/incoming/` | `crd*.xlsx` |
| Nikshay quarterly files | `backend/data/incoming/nikshay/` | `*.xlsx` |

The backend fingerprints the source files (name + size + mtime), so any change
invalidates every cached result automatically.

`backend/data/` is gitignored. **Do not commit programme data.**

### The monthly routine

1. Export RIS from the RIS Hub, CRD MIS from Google Sheets (as .xlsx), and get
   the Nikshay quarter file if there's a new one.
2. `npm run dev`, open the dashboard, go to **Data**, upload each file.
3. Check the **Data** tab shows all three as *loaded* with today's date, and
   that no orange column-mapping banner appeared.
4. Read the numbers. Export tables to Excel or slides to PPTX from any tab.

---

## Which sharing option?

| | Local only | Published snapshot | Deployed server |
|---|---|---|---|
| Who can view | one person | anyone with the link | anyone with the password |
| Cost | free | free | ~$7/mo |
| Server to run | none | none | one |
| Where the RIS workbook rests | your machine | **your machine** | the host's disk |
| Numbers are | live | as of last publish | live |
| Refresh step | upload in browser | `npm run publish:push` | upload in browser |
| Password protection | n/a | needs Cloudflare Access | built in |

**Published snapshot** is the option with the least to go wrong: no server, no
cost, and the beneficiary records never leave the machine that publishes. Its
tradeoff is that figures are current as of the last publish, and static hosting
cannot check a password on its own.

**Deployed server** is right if you need live figures behind a password.

---

## Publishing a snapshot (no server)

Everything the dashboard can show is precomputed into JSON files and published
as a static site. There is no backend, so nothing to host, pay for, or keep
running — and the RIS workbook stays where it is.

### What Trisha does

```bash
npm run publish:push
```

That single command:

1. Precomputes **every** month-range and gender combination (66 ranges × 3 = 198
   payloads, plus weekly) — about 5 minutes for 11 months of data
2. Builds the dashboard to read those files
3. Pushes the result to the `gh-pages` branch

Then she sends the team a link. To update the figures later: drop in the new
exports, run the same command again.

Before publishing she needs the data loaded, exactly as for local use — either
`npm run dev` and upload through the **Data** tab, or drop the files into
`backend/data/incoming/` directly.

`npm run publish` (without `:push`) builds into `publish/` without pushing, so
you can check it first with `npx serve publish`.

### What the team sees

A normal dashboard. Filters, tables, charts and the Excel/PPTX exports all work,
because every combination was calculated in advance. The **Data** tab explains
that it is a snapshot and states when it was generated, so nobody mistakes old
figures for current ones.

No login, no upload controls, no refresh button.

### The correctness point

The tempting shortcut is to publish 11 monthly figures and let the browser add
them up for whatever range the user picks. **That is exactly the defect this
rebuild fixed** (`build_v3.py:703`): monthly figures each deduplicate
beneficiaries within their own month, so summing them double-counts anyone
screened in two months.

So each range is computed separately, through the same `metrics_for_range()` the
API uses. That is why it is 198 payloads rather than 11 — and it makes the
snapshot byte-identical to the live API. Verified across sample ranges; see
`export_static.R` for the reasoning.

### Only aggregates are published

No endpoint and no exported file contains an individual record — the finest
granularity anywhere is per-camp counts. `publish.mjs` additionally greps its own
output for beneficiary-shaped identifiers and refuses to continue if it finds
any, because that step is what makes files public.

This is what removes the data-governance question entirely: there is no vendor
disk holding patient data, and no region to choose.

### Adding a password

Static hosting cannot verify a password — a prompt in the JavaScript is theatre,
since the JSON is right there in the network tab. If the figures need protecting:

- **Cloudflare Pages + Cloudflare Access** — upload `publish/` to Cloudflare
  Pages and put an Access policy in front. Real authentication (email codes or
  Google sign-in) at the edge, free for small teams, still no server. Build with
  `node scripts/publish.mjs --root` for Cloudflare, since it serves from the
  domain root rather than a `/repo/` subpath.
- Otherwise treat the link as unlisted-but-readable, which is fine for figures
  you would put in a programme report and not otherwise.

### First-time setup for GitHub Pages

After the first `npm run publish:push`, set the source once:

**Settings → Pages → Source: "Deploy from a branch" → Branch: `gh-pages` / (root)**

That replaces the Actions-based workflow, so disable
`.github/workflows/deploy-pages.yml` if you switch to snapshots — two Pages
deployments cannot coexist on one repo.

---

## Sharing the dashboard with the team (deployed)

This is the option where **everyone views one dashboard and one person uploads**.
The whole thing — UI and API — runs as a single container on one URL. No CORS,
no browser local-network permission, no API address for anyone to configure.

### Two credentials

| Variable | Who holds it | Grants |
|---|---|---|
| `ILIFT_VIEWER_PASSWORD` | the whole team | viewing every figure |
| `ILIFT_ADMIN_TOKEN` | whoever refreshes the data | viewing **and** uploading |

Both are just environment variables. Set neither and the API is open, which is
why local development needs no login.

The UI adapts to whichever was entered: viewers get no upload controls and no
refresh button, and the server refuses those calls regardless. There is one
sign-in box, because the server decides what the secret unlocks — nobody has to
declare which kind they hold.

Generate the admin token randomly, and don't reuse the viewer password:

```bash
# any of these
openssl rand -hex 24
node -e "console.log(require('crypto').randomBytes(24).toString('hex'))"
```

### Deploying to Render

1. **Render → New → Blueprint**, pick this repo. It reads
   [`render.yaml`](render.yaml).
2. Render prompts for `ILIFT_VIEWER_PASSWORD` and `ILIFT_ADMIN_TOKEN`. Set both.
   Leave `ILIFT_ALLOWED_ORIGINS` blank — the UI and API share an origin here.
3. Check the summary before confirming: service type **Web Service**, runtime
   **Docker**, region **Singapore**, plan **Starter**, and a 1 GB disk mounted at
   `/data`. All of these come from `render.yaml`; the UI lets you override them,
   and two of the overrides break the deployment (see below).
4. Deploy. First build takes a while (it installs R packages); later ones are
   cached.
5. Open the URL, sign in with the admin token, go to **Data**, upload the three
   exports. Share the URL and the *viewer* password with the team.

Do not pick **Static Site**: it would publish the frontend with no R backend, so
the dashboard would load and then report that it cannot reach the API.

**The persistent disk is not optional.** `render.yaml` mounts a 1 GB disk at
`/data`. Without it the container filesystem is wiped on every restart and
redeploy, and the dashboard would come back empty until someone re-uploaded.
That requires a paid instance type; the free tier has no persistent disk and
also spins down when idle.

Railway and Fly.io work the same way — same `Dockerfile`, same variables, just
attach a volume at `/data`.

### Before you deploy: what leaves your laptop

The API surface is **aggregate-only**. No endpoint returns individual
beneficiary records; the finest granularity anywhere is per-camp counts. So what
viewers can read is summary figures, not the ~16,000 rows.

The uploaded RIS workbook itself *does* contain beneficiary records, and it sits
on the hosting provider's disk. On a third-party PaaS that means patient
screening data resting on commercial infrastructure outside CHAI's data
agreements. That was a considered choice — if it needs revisiting, the same
container runs unchanged on a CHAI VM or your org's cloud account; only where
you point it changes.

Render has no India region. `render.yaml` selects Singapore as the nearest one,
but the workbook still rests outside India — relevant under the DPDP Act, and
worth confirming with whoever owns data governance before this carries real
patient data.

Two things worth doing either way:

- Put the deployment behind your org's VPN if one is available.
- Rotate `ILIFT_ADMIN_TOKEN` if it is ever shared by email or chat.

### Running the container locally

```bash
docker build -t ilift .
docker run -p 8000:8000 \
  -e ILIFT_VIEWER_PASSWORD=team-password \
  -e ILIFT_ADMIN_TOKEN=$(openssl rand -hex 24) \
  -v ilift-data:/data \
  ilift
```

Then open <http://localhost:8000>.

---

## Hosting the frontend on GitHub Pages

The dashboard can be published as a static site while the backend and all data
stay on your machine. **Nothing is uploaded to GitHub** — the published page is
just the interface, and it reads from a backend running on `127.0.0.1`.

### Setup

1. Push this project to a GitHub repo.
2. **Settings → Pages → Source: GitHub Actions.**
3. Push to `main`. [`.github/workflows/deploy-pages.yml`](.github/workflows/deploy-pages.yml)
   builds and publishes `frontend/`.
4. Start your backend with the Pages origin allowed:

   ```bash
   ILIFT_ALLOWED_ORIGINS=https://<your-user>.github.io npm run dev:api
   ```

   Better, put it in `.Renviron` at the project root so you don't retype it:

   ```
   ILIFT_ALLOWED_ORIGINS=https://<your-user>.github.io
   ```

5. Open `https://<your-user>.github.io/<repo>/`.

If the backend isn't running, or the origin isn't allowed, the page says so and
prints the exact command to fix it.

### What this does and does not give you

**It does not make the dashboard viewable by your team.** Anyone opening the
Pages URL without your backend running sees an empty dashboard and instructions.
The page is public; the data is not. That is the point — but it does mean Pages
buys you convenient distribution of the *interface*, not shared access to
*numbers*.

If what you want is the team seeing live figures, use
[the deployed setup](#sharing-the-dashboard-with-the-team-deployed) instead.
This Pages route is for one person running everything locally.

**You must allow local network access, once.** Chrome now blocks a public
HTTPS site from reaching a loopback address until you permit it. The first time
you open the Pages URL with the backend running, Chrome asks whether the site
may access devices on your local network — click **Allow**. Until you do, the
dashboard reports that it cannot reach the backend, and the browser console
shows:

```
blocked by CORS policy: Permission was denied for this request
to access the `loopback` address space
```

This is a browser policy, not a bug in the dashboard, and no server header can
override it — the backend already sends `Access-Control-Allow-Private-Network`,
which older Chrome accepted but current Chrome does not treat as sufficient on
its own.

**Once the permission is granted, everything works**, verified end to end
against the live Pages URL: reading data, uploading a new RIS export, and the
KPIs and charts updating to match. Cross-origin refetches take a few seconds
longer than they do locally, so the numbers settle a moment after the upload
confirmation appears.

Chrome has nonetheless tightened this rule twice, so if it ever breaks, the
local route is unaffected: `npm run dev` and open <http://localhost:5173>, where
the question never arises.

**Private repos.** GitHub Pages on a private repo needs a paid plan. The
frontend contains no data, so a separate public repo for it is a reasonable
alternative — just don't copy `iLift_Dashboard_2026-08-12.Rmd` into it, as it
contains credentials.

### Why the backend has an origin allowlist

The API binds to `127.0.0.1`, which stops other *machines* reaching it. It does
not stop other *websites*: without an allowlist, any page you happened to visit
while the backend was running could read every beneficiary record out of it, or
POST files to `/api/upload`. So the backend accepts only origins it has been
told about — localhost by default, plus anything in `ILIFT_ALLOWED_ORIGINS`.

---

## What changed from the old dashboard, and why numbers moved

### Multi-month totals were overcounted

The old dashboard computed a range total by **summing monthly buckets**
(`build_v3.py:703`). But each monthly figure deduplicates beneficiaries within
that month (`calc_v2.R:73`), so anyone screened in two months was counted twice.
The Excel reference dashboard deduplicates across the whole period.

The API now computes each requested range in one pass, deduplicating across it.
Expect multi-month figures to **drop** toward the Excel values; full-period
totals are unchanged. The UI shows the size of the correction beneath the TB
cascade table.

### Placeholder values are gone

`build_v3.py:104-120` shipped hardcoded stand-ins that rendered as real numbers
in the NNS tab:

```python
_ast_aitb = 0  # complex cross-tab not available; use 0 placeholder
_mbc_mmrc = 0  # not split by mMRC grade
_cpd_aitb = ...  # will use total for now
```

These are computed from the underlying data now.

### Columns are resolved by name, not position

The old scripts addressed columns purely by position (`d[[50]]`, `d[[106]]`, …),
so a reordered RISHUB export would silently change every metric.
`backend/R/schema.R` resolves each field by matching the header text, falls back
to the legacy position, and surfaces anything it could not confirm as a banner
in the UI and a warning in the server log.

**Known conflict, unresolved:** `calc_nns.R:49-50` reads columns 73–74 as the
Night Sweats / Fever symptom flags, while `calc_weekly.R:110-111` reads the same
two columns as Latitude / Longitude. Both read the same sheet, so one is wrong,
and each failure is silent — `as.numeric("Yes")` yields `NA` (map pins vanish)
and `yn(<latitude>)` yields `FALSE` (symptom counts read zero). Weekly
coordinates now resolve by header name only; `GET /api/meta` reports what the
real export actually holds at those positions.

---

## API

| Endpoint | Purpose |
|---|---|
| `GET /api/health` | Liveness (never authenticated) |
| `GET /api/meta` | Available months, source freshness, schema diagnostics |
| `GET /api/metrics?from&to&gender` | ~230 core metrics + monthly series |
| `GET /api/nns?from&to&gender` | 57 NNS cohorts |
| `GET /api/weekly?from&to&weeks` | Weekly review + per-camp detail |
| `GET /api/sputum?from&to&gender` | Sputum cohort table |
| `POST /api/upload?slot=` | Save a workbook into incoming/ and recompute |
| `POST /api/refresh` | Re-ingest and drop all caches |

`from`/`to` are inclusive `YYYY-MM`; `gender` is `all` \| `F` \| `M`.

`/api/metrics` returns `total` (range-deduplicated), `monthly` (per-month series
for charts), and `sum_of_monthly` + `overcount` so the UI can show exactly how
much double-counting the fix removed.

---

## Layout

```
backend/
  plumber.R              API routes, CORS
  R/
    config.R             env-driven paths (no hardcoded OneDrive)
    schema.R             column-name resolution + drift warnings
    ingest.R             read RIS / CRD MIS / Nikshay
    cache.R              source-fingerprint caching
    metrics_core.R       calc_logic() port + range-dedup fix
    metrics_nns.R        NNS cohorts
    metrics_weekly.R     weekly review
  scripts/
    export_static.R      precompute every view as JSON (snapshot mode)
  scripts/
    serve.R              start the API
    test.R               run the test suite
    smoke.R              exercise every module without HTTP
    make_fixtures.R      synthetic data
  tests/testthat/        schema, range-dedup, Excel parity
  data/incoming/         ← drop exports here (gitignored)

frontend/
  src/
    api/                 typed client + TanStack Query hooks
    state/filters.ts     range + gender, synced to the URL
    components/          KpiTile, charts, DataTable, CascadePyramid
    features/            the five main tabs
    export/              xlsx, png, svg, pptx
```

---

## Configuration

Set in `.Renviron` or the environment:

| Variable | Default | Purpose |
|---|---|---|
| `ILIFT_DATA_DIR` | `backend/data` | Data root |
| `ILIFT_PORT` | `8000` | API port |
| `ILIFT_PROJECT_START` | `2025-07-28` | Start of the project window |
| `ILIFT_USE_EXCEL_LOGIC` | `true` | Read the Excel-computed Logic sheet |
| `ILIFT_VIEWER_PASSWORD` | unset (open) | Shared password to view the dashboard |
| `ILIFT_ADMIN_TOKEN` | unset (open) | Secret granting upload + refresh |
| `ILIFT_HOST` | `127.0.0.1` | Bind address; `0.0.0.0` in a container |
| `ILIFT_STATIC_DIR` | `frontend/dist` if built | Built UI to serve at `/` |
| `ILIFT_ALLOWED_ORIGINS` | localhost only | Extra origins allowed to call the API (comma-separated) |
| `ILIFT_MAX_UPLOAD_MB` | `150` | Upload size ceiling |
| `VITE_DATA_MODE` | unset | Set to `static` at build time to read a snapshot instead of the API |
| `ILIFT_FIXTURE_SEED` | `42` | Fixture generator seed |
| `ILIFT_FIXTURE_N` | `4000` | Fixture beneficiary count |

---

## Tests

```bash
Rscript backend/scripts/test.R
```

- **`test-schema.R`** — every field resolves; header text beats legacy position;
  missing columns are reported rather than read as zero.
- **`test-range-dedup.R`** — range totals never exceed sum-of-months; screened
  equals distinct beneficiaries; repeat attenders counted once.
- **`test-auth.R`** — the viewer/admin boundary: unset variables meaning
  "open", a viewer password being refused on write endpoints, near-miss tokens.
- **`test-uploads.R`** — filename validation for the upload endpoint:
  traversal, Excel lock files, wrong extensions, control characters.
- **`test-parity.R`** — full-period totals against the Excel reference
  (Screened 16,352 · CXR 14,925 · MB+ 55 · TB notified 106 · COPD 398 …).
  **Skips while fixtures are loaded**; it only runs against a real RIS export.

Frontend: `cd frontend && npm run typecheck`.

---

## Still to do

- **Phase 2 — remove the Excel dependency.** The pipeline still reads the
  Excel-computed "Logic sheet", which is why a human must paste into Excel
  before anything works. `SECTION III` of `iLift Data and Dashboard.R:167-503`
  already ports those formulas to R; porting them into `backend/R/flags.R` and
  dual-running against the Excel path until every metric matches would remove
  the manual step. `ILIFT_USE_EXCEL_LOGIC` is the toggle.
- **Verify against real data.** Every number here comes from synthetic
  fixtures. The parity suite is written and will run as soon as a real export
  is present.
- **Verify the container build.** Docker is not installed on the machine this
  was written on, so the Dockerfile and render.yaml are unrun. The app they
  wrap is verified (single-origin serving, auth, upload loop all tested), but
  expect to iterate once on the first Render build.
- Automated ingestion (RISHUB / Google Sheets / SharePoint), if wanted later.
  The ingest layer is isolated so connectors can be added without touching
  metric logic.

## Security note

`iLift_Dashboard_2026-08-12.Rmd` in the source repository contains a live RISHUB
username and password in plaintext, committed to git history. **That password
should be rotated** and removed from the file. This project reads secrets from a
gitignored `.Renviron` and never stores credentials in source.

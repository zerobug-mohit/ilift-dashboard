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
*numbers*. For genuine team access the backend has to run somewhere both people
can reach, which is a different deployment and a data-governance decision.

**Browser support.** A page on HTTPS calling `http://127.0.0.1` is normally
blocked as mixed content, but `localhost` and `127.0.0.1` are exempt from that
rule and **Chrome and Edge honour the exemption**. Firefox and Safari are
stricter and may block it. Use Chrome or Edge, or run the dashboard locally
(`npm run dev`), where the question doesn't arise.

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
| `GET /api/health` | Liveness |
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
| `ILIFT_ALLOWED_ORIGINS` | localhost only | Extra origins allowed to call the API (comma-separated) |
| `ILIFT_MAX_UPLOAD_MB` | `150` | Upload size ceiling |
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
- Automated ingestion (RISHUB / Google Sheets / SharePoint), if wanted later.
  The ingest layer is isolated so connectors can be added without touching
  metric logic.

## Security note

`iLift_Dashboard_2026-08-12.Rmd` in the source repository contains a live RISHUB
username and password in plaintext, committed to git history. **That password
should be rotated** and removed from the file. This project reads secrets from a
gitignored `.Renviron` and never stores credentials in source.

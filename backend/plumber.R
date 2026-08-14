# ─────────────────────────────────────────────────────────────────────────────
# plumber.R — iLIFT Dashboard API
#
# Replaces build_v3.py, which baked a snapshot of the data into a static HTML
# file. Every endpoint here computes from the current contents of
# data/incoming/, so refreshing data is a file drop rather than a rebuild.
#
# Run:  Rscript backend/scripts/serve.R
# ─────────────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(plumber)
  library(dplyr)
  library(jsonlite)
  library(digest)
})

# serve.R sets the working directory to backend/, so R/ resolves from there.
source_dir <- if (dir.exists("R")) "R" else file.path("backend", "R")

for (f in c("config.R", "schema.R", "ingest.R", "cache.R", "uploads.R",
            "metrics_core.R", "metrics_nns.R", "metrics_weekly.R")) {
  source(file.path(source_dir, f))
}

# ── CORS ─────────────────────────────────────────────────────────────────────
# Deliberately an allowlist, not "*".
#
# The API binds to 127.0.0.1, which stops other machines reaching it — but it
# does NOT stop other *websites*. With a wildcard, any page the user happened to
# browse could read every beneficiary record out of this API, or POST files to
# /api/upload. That is not acceptable for patient screening data.
#
# Localhost origins are allowed by default (the dev server and a local build).
# To use a dashboard hosted elsewhere — GitHub Pages, say — name it explicitly:
#   ILIFT_ALLOWED_ORIGINS=https://yourname.github.io
# Comma-separate for more than one.

ALLOWED_ORIGINS <- local({
  extra <- Sys.getenv("ILIFT_ALLOWED_ORIGINS", unset = "")
  extra <- trimws(strsplit(extra, ",", fixed = TRUE)[[1]])
  extra <- extra[nzchar(extra)]

  local_origins <- as.vector(outer(
    c("http://localhost", "http://127.0.0.1"),
    c("", ":5173", ":5174", ":5175", ":4173", ":8000"),
    paste0
  ))
  unique(c(local_origins, sub("/+$", "", extra)))
})

cat("CORS allowed origins:\n")
for (o in ALLOWED_ORIGINS) cat("  ", o, "\n")
cat("\n")

#* @filter cors
function(req, res) {
  origin <- req$HTTP_ORIGIN

  # Same-origin and non-browser callers (curl, R) send no Origin header
  if (is.null(origin) || !nzchar(origin)) {
    if (identical(req$REQUEST_METHOD, "OPTIONS")) {
      res$status <- 200
      return(list())
    }
    return(plumber::forward())
  }

  if (!(sub("/+$", "", origin) %in% ALLOWED_ORIGINS)) {
    # Allow the *rejection* to be read cross-origin. Without this header the
    # browser turns the 403 into an opaque network error, and the dashboard
    # cannot tell "origin refused" from "backend not running" — so it tells the
    # user to start a backend that is already running.
    #
    # This leaks nothing: the body carries no programme data, only the reason
    # and the fix. Data-bearing routes are still unreachable from this origin.
    res$setHeader("Access-Control-Allow-Origin", origin)
    res$setHeader("Vary", "Origin")
    res$status <- 403

    # unbox() so the client sees strings, not single-element arrays — this
    # filter runs before any route's serializer applies.
    return(list(
      error   = jsonlite::unbox("origin_not_allowed"),
      origin  = jsonlite::unbox(origin),
      message = jsonlite::unbox(paste0(
        "Origin '", origin, "' is not allowed to call this API. ",
        "If this dashboard is yours, restart the backend with ",
        "ILIFT_ALLOWED_ORIGINS=", origin
      ))
    ))
  }

  res$setHeader("Access-Control-Allow-Origin", origin)
  res$setHeader("Vary", "Origin")
  res$setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
  res$setHeader("Access-Control-Allow-Headers", "Content-Type")
  res$setHeader("Access-Control-Max-Age", "600")

  if (identical(req$REQUEST_METHOD, "OPTIONS")) {
    res$status <- 200
    return(list())
  }
  plumber::forward()
}

# Wrap a handler so ingest failures return a structured 503 instead of a stack
# trace — the UI renders this as "no data loaded yet" with the reason.
with_data <- function(res, fn) {
  tryCatch(fn(), error = function(e) {
    res$status <- 503
    list(error = "data_unavailable", message = conditionMessage(e),
         sources = source_status())
  })
}

norm_gender <- function(g) {
  g <- tolower(as.character(g %||% "all"))
  if (g %in% c("f", "female")) "F" else if (g %in% c("m", "male")) "M" else "all"
}

#* Liveness probe
#* @serializer unboxedJSON
#* @get /api/health
function() {
  list(status = "ok", time = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
}

#* Dataset metadata: available months, source freshness, schema diagnostics
#* @serializer unboxedJSON
#* @get /api/meta
function(res) {
  with_data(res, function() {
    b <- get_bundle()
    list(
      months        = I(b$months),   # always an array, even for a single month
      loaded_at     = b$loaded_at,
      fingerprint   = b$fingerprint,
      project_start = format(CONFIG$project_start),
      rows          = b$ris$n_rows,
      beneficiaries = b$ris$n_bids,
      sources       = source_status(),
      cache         = cache_stats(),
      schema        = list(
        warnings  = b$ris$warnings,
        conflicts = b$ris$conflicts
      ),
      notes = list(
        raw_sheet_available = b$ris$raw_ok,
        crd_available       = b$crd$present,
        nikshay_available   = b$nik$present,
        using_excel_logic   = CONFIG$use_excel_logic_sheet
      )
    )
  })
}

#* Core metrics for a date range and gender
#* @param from Start month, "YYYY-MM"
#* @param to   End month, "YYYY-MM"
#* @param gender "all" | "F" | "M"
#* @serializer unboxedJSON
#* @get /api/metrics
function(res, from = "", to = "", gender = "all") {
  g <- norm_gender(gender)
  with_data(res, function() {
    b <- get_bundle()
    r <- cached("metrics", list(from, to, g),
                function() metrics_for_range(b, from, to, g))
    c(r, list(computed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
              filters = list(from = from, to = to, gender = g)))
  })
}

#* NNS cohorts for a date range
#* @serializer unboxedJSON
#* @get /api/nns
function(res, from = "", to = "", gender = "all") {
  g <- norm_gender(gender)
  with_data(res, function() {
    b <- get_bundle()
    cached("nns", list(from, to, g), function() nns_for_range(b, from, to, g))
  })
}

#* Weekly review and per-camp detail
#* @serializer unboxedJSON
#* @get /api/weekly
function(res, from = "", to = "", weeks = 4) {
  nw <- suppressWarnings(as.integer(weeks)); if (is.na(nw)) nw <- 4
  with_data(res, function() {
    b <- get_bundle()
    cached("weekly", list(from, to, nw),
           function() weekly_for_range(b, from, to, n_weeks = nw))
  })
}

#* Sputum cohort table (AI-suggestive x symptomatic)
#* @serializer unboxedJSON
#* @get /api/sputum
function(res, from = "", to = "", gender = "all") {
  g <- norm_gender(gender)
  with_data(res, function() {
    b <- get_bundle()
    r <- cached("metrics", list(from, to, g),
                function() metrics_for_range(b, from, to, g))
    t <- r$total
    mk <- function(label, sfx) list(
      cohort = label,
      n      = t[[paste0("n_scr_",  sfx)]],
      elig   = t[[paste0("n_elig_", sfx)]],
      coll   = t[[paste0("n_coll_", sfx)]],
      test   = t[[paste0("n_test_", sfx)]],
      mbp    = t[[paste0("n_mbc_",  sfx)]],
      cd     = t[[paste0("n_cd_",   sfx)]]
    )
    list(rows = list(
      mk("AI-TB Sugg + Symptomatic", "as"),
      mk("AI-TB Sugg Only",          "ao"),
      mk("Symptomatic Only",         "so"),
      mk("Neither",                  "nn")
    ))
  })
}

#* Upload a source workbook into data/incoming/ and recompute
#*
#* Equivalent to dropping the file into the folder by hand, but doable from the
#* dashboard. Replaces the current file for `ris` and `crd_mis` (the old one is
#* archived, not deleted); adds to the set for `nikshay`.
#*
#* @param slot "ris" | "crd_mis" | "nikshay"
#* @parser multi
#* @serializer unboxedJSON
#* @post /api/upload
function(req, res, slot = "") {
  slot <- tolower(trimws(as.character(slot)))

  if (!slot %in% UPLOAD_SLOTS) {
    res$status <- 400
    return(list(error = "bad_slot",
                message = paste0("slot must be one of: ",
                                 paste(UPLOAD_SLOTS, collapse = ", "))))
  }

  files <- extract_uploads(req$body)
  if (length(files) == 0) {
    res$status <- 400
    return(list(error = "no_file", message = "no file found in the request body"))
  }

  saved  <- list()
  failed <- list()
  for (f in files) {
    r <- tryCatch(save_upload(slot, f$filename, f$bytes),
                  error = function(e) list(error = conditionMessage(e),
                                           original = f$filename))
    if (!is.null(r$error)) failed[[length(failed) + 1]] <- r
    else                   saved[[length(saved) + 1]]   <- r
  }

  if (length(saved) == 0) {
    res$status <- 400
    return(list(error = "upload_rejected", saved = list(), failed = failed))
  }

  # New files on disk: drop every cached result and reload
  invalidate_cache()
  reload <- tryCatch({
    b <- get_bundle(force = TRUE)
    list(ok = TRUE, rows = b$ris$n_rows, beneficiaries = b$ris$n_bids,
         months = I(b$months), loaded_at = b$loaded_at,
         schema_warnings = b$ris$warnings)
  }, error = function(e) list(ok = FALSE, message = conditionMessage(e)))

  if (length(failed) > 0) res$status <- 207   # partial success

  list(saved = saved, failed = failed, reload = reload, sources = source_status())
}

#* Re-read the incoming folder and drop all cached results
#* @serializer unboxedJSON
#* @post /api/refresh
function(res) {
  invalidate_cache()
  with_data(res, function() {
    b <- get_bundle(force = TRUE)
    list(refreshed = TRUE, loaded_at = b$loaded_at,
         rows = b$ris$n_rows, beneficiaries = b$ris$n_bids,
         months = I(b$months), sources = source_status())
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# export_static.R — precompute every view the dashboard can show, as JSON.
#
#   Rscript backend/scripts/export_static.R [output_dir]
#
# WHY THIS EXISTS
# The API computes each requested range on demand. That needs a running server,
# which means hosting, which means the RIS workbook resting on someone else's
# disk. Precomputing instead removes the server entirely: the raw data never
# leaves this machine, and only aggregate numbers are published.
#
# THE THING THIS MUST NOT DO
# The obvious shortcut is to publish the 12 monthly figures and let the browser
# add them up for whatever range the user picks. That is exactly the defect this
# rebuild exists to fix (build_v3.py:703): monthly figures each deduplicate
# beneficiaries within their own month, so summing them double-counts anyone
# screened in two months.
#
# So every range is computed separately, through the same metrics_for_range()
# the API uses. 11 months means 66 ranges, not 11 — and the numbers are then
# identical to the live API's by construction.
# ─────────────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(dplyr)
  library(digest)
  library(jsonlite)
})

script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", args, value = TRUE)
  if (length(m)) dirname(normalizePath(sub("^--file=", "", m[1]))) else getwd()
}

backend_dir <- normalizePath(file.path(script_dir(), ".."), mustWork = TRUE)
project_dir <- normalizePath(file.path(backend_dir, ".."), mustWork = TRUE)
setwd(backend_dir)
if (Sys.getenv("ILIFT_DATA_DIR") == "") {
  Sys.setenv(ILIFT_DATA_DIR = file.path(backend_dir, "data"))
}

for (f in c("config.R", "schema.R", "ingest.R", "cache.R", "uploads.R", "auth.R",
            "metrics_core.R", "metrics_nns.R", "metrics_weekly.R")) {
  source(file.path("R", f))
}

args <- commandArgs(trailingOnly = TRUE)
out_root <- if (length(args) >= 1 && nzchar(args[1])) {
  args[1]
} else {
  file.path(project_dir, "publish", "data")
}

GENDERS <- c("all", "F", "M")

# One file per view. The frontend builds the same key from its filter state, so
# the mapping has to stay in step with staticSource.ts.
range_key <- function(from, to, gender = NULL) {
  if (is.null(gender)) paste0(from, "__", to) else paste0(from, "__", to, "__", gender)
}

write_json_file <- function(obj, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  # digits = NA keeps integers exact; auto_unbox matches the API's serializer so
  # the frontend cannot tell the two sources apart.
  writeLines(toJSON(obj, auto_unbox = TRUE, digits = NA, na = "null"), path)
  file.size(path)
}

cat("iLIFT static export\n")
cat("  output:", out_root, "\n\n")

bundle <- get_bundle()
months <- bundle$months
if (length(months) == 0) stop("no data loaded — nothing to export")

n <- length(months)
ranges <- list()
for (i in seq_len(n)) {
  for (j in i:n) ranges[[length(ranges) + 1]] <- c(months[i], months[j])
}

cat(sprintf("  months : %d (%s .. %s)\n", n, months[1], months[n]))
cat(sprintf("  ranges : %d\n", length(ranges)))
cat(sprintf("  payloads: %d metrics + %d nns + %d weekly\n\n",
            length(ranges) * length(GENDERS),
            length(ranges) * length(GENDERS),
            length(ranges)))

if (dir.exists(out_root)) unlink(out_root, recursive = TRUE)

total_bytes <- 0
t_start <- Sys.time()
done <- 0
total_jobs <- length(ranges) * length(GENDERS) * 2 + length(ranges)

tick <- function() {
  done <<- done + 1
  if (done %% 25 == 0 || done == total_jobs) {
    el <- as.numeric(difftime(Sys.time(), t_start, units = "secs"))
    cat(sprintf("\r  %d/%d payloads  %.0fs elapsed", done, total_jobs, el))
    flush.console()
  }
}

for (r in ranges) {
  from <- r[1]; to <- r[2]

  for (g in GENDERS) {
    key <- range_key(from, to, g)

    m <- metrics_for_range(bundle, from, to, g)
    m$computed_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    m$filters <- list(from = from, to = to, gender = g)
    total_bytes <- total_bytes + write_json_file(m, file.path(out_root, "metrics", paste0(key, ".json")))
    tick()

    total_bytes <- total_bytes + write_json_file(
      nns_for_range(bundle, from, to, g),
      file.path(out_root, "nns", paste0(key, ".json"))
    )
    tick()
  }

  # Weekly review has no gender filter (weekly_for_range takes from/to only),
  # so one file per range rather than three.
  total_bytes <- total_bytes + write_json_file(
    weekly_for_range(bundle, from, to),
    file.path(out_root, "weekly", paste0(range_key(from, to), ".json"))
  )
  tick()
}

cat("\n\n")

# ── Manifest ─────────────────────────────────────────────────────────────────
# Stands in for GET /api/meta. `auth` reports viewer with nothing protected:
# a published snapshot has no upload path, so the UI must not offer one.
manifest <- list(
  months        = I(months),
  loaded_at     = bundle$loaded_at,
  generated_at  = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  fingerprint   = bundle$fingerprint,
  project_start = format(CONFIG$project_start),
  rows          = bundle$ris$n_rows,
  beneficiaries = bundle$ris$n_bids,
  sources       = source_status(),
  cache         = list(loaded = TRUE, fingerprint = bundle$fingerprint,
                       entries = 0, load_error = NULL),
  auth          = list(read_protected = FALSE, write_protected = FALSE,
                       mode = "published snapshot", level = "viewer"),
  schema        = list(warnings = bundle$ris$warnings, conflicts = bundle$ris$conflicts),
  notes         = list(raw_sheet_available = bundle$ris$raw_ok,
                       crd_available       = bundle$crd$present,
                       nikshay_available   = bundle$nik$present,
                       using_excel_logic   = CONFIG$use_excel_logic_sheet),
  # Marks this as a snapshot so the UI can say so instead of implying it is live
  static        = TRUE
)
invisible(write_json_file(manifest, file.path(out_root, "manifest.json")))

elapsed <- as.numeric(difftime(Sys.time(), t_start, units = "secs"))
cat(sprintf("Done in %.0fs — %d files, %.1f MB\n",
            elapsed, total_jobs + 1, total_bytes / 1024^2))
cat("\nPublished figures are aggregates only. No beneficiary records are written\n")
cat("to this directory — verify with: grep -rl 'IL0' ", out_root, "\n", sep = "")

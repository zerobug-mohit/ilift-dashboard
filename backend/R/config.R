# ─────────────────────────────────────────────────────────────────────────────
# config.R — environment-driven paths
#
# Replaces the hardcoded per-machine paths in the legacy pipeline:
#   calc_v2.R:4              BASE <- "C:/Users/tchandra/OneDrive - ..."
#   ILIFT MASTER DATASET.R:18
#   build_v3.py:3
#
# Every path is now resolved relative to ILIFT_DATA_DIR (default: ./data),
# so the project runs on any machine with no source edits.
# ─────────────────────────────────────────────────────────────────────────────

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || identical(a, "")) b else a

CONFIG <- local({
  base_dir <- Sys.getenv("ILIFT_DATA_DIR", unset = "data")
  if (!dir.exists(base_dir)) dir.create(base_dir, recursive = TRUE, showWarnings = FALSE)

  incoming <- file.path(base_dir, "incoming")
  cache    <- file.path(base_dir, "cache")
  for (d in c(incoming, cache)) {
    if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  }

  list(
    data_dir     = base_dir,
    incoming_dir = incoming,
    cache_dir    = cache,

    # Project date window. The legacy pipeline hardcoded this at calc_v2.R:33
    # ("July 28, 2025 onwards, matches Excel Date Selection start").
    project_start = as.Date(Sys.getenv("ILIFT_PROJECT_START", unset = "2025-07-28")),

    # Phase 1 reads the Excel-computed "Logic sheet" for guaranteed parity.
    # Phase 2 flips this to FALSE to compute flags natively from raw RIS data.
    # Kept as a toggle so the Excel path remains available as a fallback.
    use_excel_logic_sheet = tolower(Sys.getenv("ILIFT_USE_EXCEL_LOGIC", "true")) %in%
                            c("true", "1", "yes"),

    port = as.integer(Sys.getenv("ILIFT_PORT", unset = "8000")),

    # Sheet names inside the source workbooks
    sheet_logic = Sys.getenv("ILIFT_SHEET_LOGIC", "Logic sheet"),
    sheet_raw   = Sys.getenv("ILIFT_SHEET_RAW",   "RAW DATA (paste here)"),
    sheet_crd   = Sys.getenv("ILIFT_SHEET_CRD",   "New Master Sheet")
  )
})

# ── Expected filenames in the watched incoming/ folder ───────────────────────
# Matched case-insensitively by prefix so dated exports work without renaming
# (e.g. "ris_2026-08-14.xlsx" matches the "ris" pattern).
# RIS Hub and the CRD MIS export CSV; the Excel workbooks are the same data
# pasted into a template. Both are accepted so neither route needs a conversion
# step — see read_source_table() in ingest.R.
SOURCE_PATTERNS <- list(
  ris     = "^ris.*\\.(xlsx?|csv)$",
  crd_mis = "^crd.*\\.(xlsx?|csv)$",
  nikshay = "^.*\\.(xlsx?|csv)$"   # inside incoming/nikshay/
)

#' Locate a source's files in the incoming folder by pattern.
#'
#' Returns every match, name-sorted, or NULL if none. All of them are read and
#' combined: an export too large to download in one go arrives as ris1, ris2,
#' ris3, and splitting it should not mean choosing between the pieces.
#'
#' Name order, not modification time, so the result does not depend on which
#' chunk finished downloading first.
find_source <- function(key) {
  pat <- SOURCE_PATTERNS[[key]]
  if (is.null(pat)) return(NULL)

  dir <- if (key == "nikshay") file.path(CONFIG$incoming_dir, "nikshay") else CONFIG$incoming_dir
  if (!dir.exists(dir)) return(NULL)

  files <- list.files(dir, pattern = pat, full.names = TRUE, ignore.case = TRUE)
  files <- files[!grepl("^~\\$", basename(files))]   # skip Excel lock files
  if (length(files) == 0) return(NULL)

  sort(files)
}

#' Status of every expected source — powers GET /api/meta so the UI can always
#' show which files are loaded and how fresh they are.
source_status <- function() {
  lapply(c("ris", "crd_mis", "nikshay"), function(k) {
    f <- find_source(k)
    if (is.null(f)) {
      list(key = k, present = FALSE, files = list(), modified = NULL)
    } else {
      list(
        key      = k,
        present  = TRUE,
        files    = as.list(basename(f)),
        modified = format(max(file.mtime(f)), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
      )
    }
  })
}

#' Combined fingerprint of all source files. Used as the cache key so that
#' dropping a new export into incoming/ automatically invalidates cached
#' results — this is what makes the dashboard non-static.
sources_fingerprint <- function() {
  all_files <- unlist(lapply(c("ris", "crd_mis", "nikshay"), find_source))
  if (length(all_files) == 0) return("empty")
  info <- file.info(all_files)
  digest::digest(paste(basename(all_files), info$size, info$mtime, collapse = "|"))
}

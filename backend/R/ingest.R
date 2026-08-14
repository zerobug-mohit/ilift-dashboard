# ─────────────────────────────────────────────────────────────────────────────
# ingest.R — load the three data sources from the watched incoming/ folder
#
# Replaces the legacy flow, which required:
#   1. manually copying the RIS workbook to a hardcoded temp path
#      (calc_v2.R:29 "logic_tmp_v2.xlsx not found. Run: Copy-Item ... first")
#   2. a separate copy per script (logic_tmp_v2 / _gender / _weekly)
#
# Here the workbook is read once and shared across all metric modules.
# ─────────────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(dplyr)
  library(readxl)
})

#' Read the RIS workbook: Logic sheet + RAW sheet, filtered to the project window.
ingest_ris <- function() {
  path <- find_source("ris")
  if (is.null(path)) stop("No RIS export found in ", CONFIG$incoming_dir,
                          ". Expected a file matching 'ris*.xlsx'.")

  L <- suppressWarnings(read_excel(path, sheet = CONFIG$sheet_logic))

  # Resolve columns by header, not blind position (see schema.R)
  res <- resolve_schema(L)
  map <- res$index

  warns <- schema_warnings(res)
  if (length(warns) > 0) {
    message("[schema] ", length(warns), " column(s) could not be confirmed by header:")
    for (w in warns) message("  - ", w)
  }

  L$camp_date <- suppressWarnings(as.Date(fld(L, map, "camp_date")))
  L$ym        <- format(L$camp_date, "%Y-%m")
  L$bid       <- as.character(fld(L, map, "beneficiary_id"))
  L$gender    <- trimws(as.character(fld(L, map, "gender")))

  # Same filter as calc_v2.R:33 — project window, valid beneficiary
  L <- L[!is.na(L$camp_date) & L$camp_date >= CONFIG$project_start & !is.na(L$bid), ]

  # RAW sheet — Expert Referral (calc_v2.R:420-430)
  raw_expref_bids <- character(0)
  raw_ok <- TRUE
  tryCatch({
    RAW <- suppressWarnings(read_excel(path, sheet = CONFIG$sheet_raw))
    RAW$camp_date <- suppressWarnings(as.Date(RAW[[2]]))
    RAW <- RAW[!is.na(RAW$camp_date) & RAW$camp_date >= CONFIG$project_start & !is.na(RAW[[50]]), ]
    if (ncol(RAW) >= 169) {
      flg <- RAW[[169]] %in% c("Immediate referral", "Deferred referral")
      raw_expref_bids <- unique(as.character(RAW[[50]][flg]))
    }
  }, error = function(e) {
    raw_ok <<- FALSE
    message("[ingest] RAW sheet unavailable (", conditionMessage(e),
            ") — expert-referral metrics will be zero.")
  })

  list(
    logic       = L,
    map         = map,
    diagnostics = res$diagnostics,
    warnings    = warns,
    conflicts   = check_known_conflicts(L),
    expref_bids = raw_expref_bids,
    raw_ok      = raw_ok,
    path        = path,
    n_rows      = nrow(L),
    n_bids      = length(unique(L$bid))
  )
}

#' Read the CRD MIS workbook — spirometry completion + OPD rows.
#' Cleaning logic reused from calc_v2.R:47-65.
ingest_crd <- function() {
  path <- find_source("crd_mis")
  if (is.null(path)) {
    message("[ingest] No CRD MIS file found — spirometry/OPD metrics will be zero.")
    return(list(spiro_comp_bids = character(0), opd_rows = NULL,
                present = FALSE, path = NULL, n_rows = 0))
  }

  CRD <- suppressWarnings(read_excel(path, sheet = CONFIG$sheet_crd))

  # The export ships a duplicated ID header and stray unnamed columns
  if ("Beneficiary ID...1" %in% colnames(CRD)) {
    CRD <- CRD %>% rename("Beneficiary ID" = "Beneficiary ID...1")
  }
  CRD <- CRD %>% select(-any_of(c("...32", "...33", "Date check")))

  spiro_col <- "Spirometry test status"
  spiro_comp_bids <- character(0)
  if (spiro_col %in% colnames(CRD)) {
    spiro_comp_bids <- CRD %>%
      filter(grepl("^Test completed", .data[[spiro_col]], ignore.case = TRUE)) %>%
      pull(`Beneficiary ID`) %>% as.character() %>% unique()
  }

  # OPD rows are those whose Beneficiary ID is literally "OPD" (calc_v2.R:63)
  opd_rows <- NULL
  date_col <- grep("Date of facility visit", colnames(CRD), value = TRUE)[1]
  if (!is.na(date_col) && "Beneficiary ID" %in% colnames(CRD)) {
    opd_rows <- CRD[!is.na(CRD$`Beneficiary ID`) &
                    trimws(as.character(CRD$`Beneficiary ID`)) == "OPD", ]
    if (nrow(opd_rows) > 0) {
      opd_rows$opd_ym <- format(suppressWarnings(as.Date(opd_rows[[date_col]])), "%Y-%m")
    }
  }

  list(spiro_comp_bids = spiro_comp_bids, opd_rows = opd_rows,
       diag_col = grep("Diagnosis.*Action|Action.*MO", colnames(CRD), value = TRUE)[1],
       present = TRUE, path = path, n_rows = nrow(CRD))
}

#' Read all Nikshay quarterly workbooks and collect Episode_IDs.
#' Used for treatment-started matching (calc_v2.R:42-45, 97-99).
ingest_nikshay <- function() {
  paths <- find_source("nikshay")
  if (is.null(paths) || length(paths) == 0) {
    message("[ingest] No Nikshay files found in ", file.path(CONFIG$incoming_dir, "nikshay"),
            " — treatment-started metrics will be zero.")
    return(list(episode_ids = numeric(0), present = FALSE, paths = character(0), n_rows = 0))
  }

  frames <- lapply(paths, function(p) {
    tryCatch(suppressWarnings(read_excel(p)), error = function(e) {
      message("[ingest] could not read ", basename(p), ": ", conditionMessage(e)); NULL
    })
  })
  frames <- Filter(Negate(is.null), frames)
  if (length(frames) == 0) {
    return(list(episode_ids = numeric(0), present = FALSE, paths = paths, n_rows = 0))
  }

  nik <- bind_rows(frames)
  ids <- numeric(0)
  if ("Episode_ID" %in% colnames(nik)) {
    ids <- suppressWarnings(as.numeric(unique(nik$Episode_ID)))
    ids <- ids[!is.na(ids)]
  } else {
    message("[ingest] Nikshay files have no 'Episode_ID' column — tx_started will be zero.")
  }

  list(episode_ids = ids, present = TRUE, paths = paths, n_rows = nrow(nik))
}

#' Load all three sources into a single bundle used by every metric module.
ingest_all <- function() {
  ris <- ingest_ris()
  crd <- ingest_crd()
  nik <- ingest_nikshay()

  months <- sort(unique(ris$logic$ym[!is.na(ris$logic$ym)]))

  list(
    ris = ris, crd = crd, nik = nik,
    months = months,
    fingerprint = sources_fingerprint(),
    loaded_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
}

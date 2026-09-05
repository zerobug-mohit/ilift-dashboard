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

#' TRUE when a source file is a CSV rather than a workbook.
is_csv <- function(path) grepl("\\.csv$", path, ignore.case = TRUE)

#' Read one table from a source file, whatever its format.
#'
#' RIS Hub and the CRD MIS both export CSV directly. A CSV holds a single table,
#' so `sheet` is meaningful only for workbooks and is ignored otherwise —
#' the caller gets the one table the file contains.
#'
#' check.names = FALSE matters: the schema resolves columns by their real
#' headers ("Beneficiary ID", "Camp ID"), and R's default name-mangling would
#' turn those into "Beneficiary.ID" and break every lookup.
read_source_table <- function(path, sheet = NULL) {
  if (is_csv(path)) {
    d <- read.csv(path, check.names = FALSE, stringsAsFactors = FALSE,
                  na.strings = c("", "NA"))
    # readxl names unlabelled columns "...31"; read.csv leaves them empty, which
    # dplyr::select() rejects outright. Match readxl so both paths behave alike.
    blank <- is.na(names(d)) | trimws(names(d)) == ""
    names(d)[blank] <- paste0("...", which(blank))
    d
  } else if (is.null(sheet)) {
    suppressWarnings(read_excel(path))
  } else {
    suppressWarnings(read_excel(path, sheet = sheet))
  }
}

# Flags that exist only on the Excel-computed "Logic sheet". The raw RIS Hub
# export carries none of them — it has the observations they are derived from,
# not the derivations.
LOGIC_SHEET_FIELDS <- c(
  "symptomatic", "vulnerable", "eligible_sputum", "sputum_tested",
  "mb_positive", "tb", "tb_presumptive", "crd_presumptive", "crd_diagnosed",
  "facility_visited", "spiro_done",
  "cxr_norm_sp", "cxr_tb_sp", "cxr_oca_sp", "cxr_norm_sn", "cxr_tb_sn", "cxr_oca_sn"
)

#' Refuse a file that is clearly not the Logic sheet.
#'
#' resolve_schema() falls back to column position when a header cannot be
#' matched. On the Logic sheet that is a reasonable safety net: the layout is
#' fixed, so position is a good second guess. On any other file it is actively
#' dangerous — feeding the raw export in maps `symptomatic` onto
#' "Fibrosis Detection (%)" and every downstream figure becomes confident
#' nonsense.
#'
#' A warning is not enough here. This rebuild exists because the old dashboard
#' reported wrong numbers without saying so, and publishing garbage behind an
#' orange banner would repeat exactly that.
assert_is_logic_sheet <- function(res, path) {
  # diagnostics is an unnamed list of records, each carrying its own `field`.
  how_by_field <- setNames(
    vapply(res$diagnostics, function(d) d$how, character(1)),
    vapply(res$diagnostics, function(d) d$field, character(1))
  )

  # "position only" means no header matched at all; "MISSING" means the file is
  # too narrow to even guess. Both mean the flag was not found by name.
  by_position <- vapply(
    LOGIC_SHEET_FIELDS,
    function(f) {
      h <- how_by_field[[f]]
      !is.null(h) && h %in% c("position only (no header match)", "MISSING")
    },
    logical(1)
  )

  n_bad <- sum(by_position)
  if (n_bad <= length(LOGIC_SHEET_FIELDS) / 2) return(invisible(TRUE))

  stop(
    "This does not look like the RIS Logic sheet.\n",
    "  File: ", basename(path), "\n",
    "  ", n_bad, " of ", length(LOGIC_SHEET_FIELDS),
    " computed flags could not be found by name, including:\n",
    "    ", paste(utils::head(names(by_position)[by_position], 5), collapse = ", "), "\n\n",
    "  The raw RIS Hub export contains the observations but not the flags the\n",
    "  dashboard needs. Paste it into the Excel template that computes the\n",
    "  Logic sheet, and upload that workbook instead.\n\n",
    "  Refusing rather than guessing: matching those columns by position would\n",
    "  produce figures that look plausible and are wrong.",
    call. = FALSE
  )
}

#' Read the RIS workbook: Logic sheet + RAW sheet, filtered to the project window.
ingest_ris <- function() {
  path <- find_source("ris")
  if (is.null(path)) stop("No RIS export found in ", CONFIG$incoming_dir,
                          ". Expected a file matching 'ris*.xlsx'.")

  L <- read_source_table(path, CONFIG$sheet_logic)

  # Resolve columns by header, not blind position (see schema.R)
  res <- resolve_schema(L)
  map <- res$index

  warns <- schema_warnings(res)
  if (length(warns) > 0) {
    message("[schema] ", length(warns), " column(s) could not be confirmed by header:")
    for (w in warns) message("  - ", w)
  }

  assert_is_logic_sheet(res, path)

  L$camp_date <- suppressWarnings(as.Date(fld(L, map, "camp_date")))
  L$ym        <- format(L$camp_date, "%Y-%m")
  L$bid       <- as.character(fld(L, map, "beneficiary_id"))
  L$gender    <- trimws(as.character(fld(L, map, "gender")))

  # Same filter as calc_v2.R:33 — project window, valid beneficiary
  L <- L[!is.na(L$camp_date) & L$camp_date >= CONFIG$project_start & !is.na(L$bid), ]

  # Expert Referral, from the RAW sheet (calc_v2.R:420-430).
  #
  # A CSV export has no second tab, but it carries the same columns — so the
  # table already read serves as both. Resolving "Expert Referral" and
  # "Beneficiary ID" by header rather than by position (169 and 50) means a
  # column inserted upstream shifts nothing.
  raw_expref_bids <- character(0)
  raw_ok <- TRUE
  tryCatch({
    RAW <- if (is_csv(path)) L else read_source_table(path, CONFIG$sheet_raw)

    ref_col <- if (is_csv(path)) {
      grep("^Expert Referral$", colnames(RAW), ignore.case = TRUE)[1]
    } else if (ncol(RAW) >= 169) 169L else NA_integer_

    bid_col <- if (is_csv(path)) {
      grep("^Beneficiary ID$", colnames(RAW), ignore.case = TRUE)[1]
    } else 50L

    if (!is.na(ref_col) && !is.na(bid_col)) {
      if (is_csv(path)) {
        keep <- !is.na(RAW[[bid_col]])
      } else {
        RAW$camp_date <- suppressWarnings(as.Date(RAW[[2]]))
        keep <- !is.na(RAW$camp_date) & RAW$camp_date >= CONFIG$project_start &
                !is.na(RAW[[bid_col]])
      }
      flg <- keep & RAW[[ref_col]] %in% c("Immediate referral", "Deferred referral")
      raw_expref_bids <- unique(as.character(RAW[[bid_col]][flg]))
    } else {
      raw_ok <- FALSE
      message("[ingest] no Expert Referral column found — those metrics will be zero.")
    }
  }, error = function(e) {
    raw_ok <<- FALSE
    message("[ingest] RAW data unavailable (", conditionMessage(e),
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

  CRD <- read_source_table(path, CONFIG$sheet_crd)

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
    tryCatch(read_source_table(p), error = function(e) {
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

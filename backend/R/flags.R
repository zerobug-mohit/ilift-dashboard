# ─────────────────────────────────────────────────────────────────────────────
# flags.R — compute the Logic sheet in R, from the raw RIS Hub export
#
# WHY THIS EXISTS
# The dashboard's figures depend on ~18 derived flags (Symptomatic, MB+,
# Eligible for sputum, the CXR × symptom cross-tabs, ...). Until now those were
# computed by formulas living in an Excel workbook, so every refresh required a
# person to paste the raw export into that workbook and upload the result. The
# spreadsheet was the pipeline's only copy of that logic, and nothing tested it.
#
# This ports those formulas, following SECTION III of the legacy
# `iLift Data and Dashboard.R` (lines 167-503), which had already translated
# them from the Excel version. Section markers below ([13A] … [13Z]) refer to
# that file so the two can be diffed.
#
# WHAT THIS DOES NOT DO
# It does not change any definition. Where the legacy port looks odd — comparing
# against the string "0", say, or treating "Beneficiary ID not present" as a
# normal X-ray — that oddity is preserved, because the Excel workbook is still
# the reference the programme reports against. Fixing a definition is a separate
# decision from removing the manual step, and mixing the two would make a
# disagreement impossible to attribute.
# ─────────────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(dplyr)
})

#' Source columns the raw export must supply, by canonical name.
#'
#' Matched case- and whitespace-insensitively, so "Sputum Result (Same Day)" and
#' "Sputum Result(Same Day)" both resolve. Anything listed as required and
#' absent stops ingest with a message naming it — better than computing a flag
#' from a column that is not there.
RAW_REQUIRED <- c(
  "Camp ID", "Beneficiary ID", "Genki Edge Result", "Symptoms",
  "Sputum Result(Same Day)", "Sputum Result(Next Day)", "Sputum Result(Other Day)",
  "Sputum Collected(Same Day)", "Sputum Collected(Next Day)", "Sputum Collected(Other Day)",
  "mMRC Scale", "TB Confirmed by Clinician", "Chronic Respiratory Diseases",
  "BMI", "Blood Sugar (mg/dL)",
  "Cough (in Last 2 Weeks)", "Chest Pain (in Last 2 Weeks)",
  "Night Sweats (in Last 2 Weeks)", "Fever (in Last 2 Weeks)",
  "Loss of Weight (in Last 3 Months)", "Blood in Sputum (in Last 6 Months)"
)

#' Columns used when present, defaulted when not. Each is a genuine "may be
#' absent" case rather than a guess: DiagnosisBasis only appears once Nikshay
#' data is merged, and the Deeptek eligibility columns exist purely to be
#' compared against.
RAW_OPTIONAL <- c(
  "DiagnosisBasis", "Chronic Respiratory Diseases (Other)", "Other Risk",
  "Shortness Of Breath", "Size Of Lump", "X-Ray Eligibility", "Sputum Eligibility",
  "Test Type(Same Day)", "Test Type(Next Day)", "Test Type(Other Day)",
  "(Common) Diabetes", "(Common) Smokeless Tobacco", "(Common) Smoking",
  "(Common) Alcohol Consumption",
  "(Common) Contact of Known TB Patients (Household Contacts)",
  "(Common) Past TB (less than 5 years)",
  "(Clinical) Renal Impairment/Dialysis", "(Clinical) Liver Impairment",
  "(Clinical) Cancer", "(Clinical) Organ Transplantation",
  "(Clinical) Existing Chronic Respiratory Disease",
  "(Social) Migrant", "(Social) Factory/Construction workers",
  "(Social) Miner", "(Social) Health Care Worker"
)

norm_header <- function(x) tolower(gsub("\\s+", "", trimws(x)))

#' The part of a header before any parenthetical qualifier.
#'
#' RIS Hub is inconsistent about these: the export carries "Cough" but
#' "Chest Pain (in Last 2 Weeks)", and the legacy script assumed the long form
#' for both. Comparing on the stem matches either spelling without needing an
#' alias list that would go stale the next time the export changes.
header_stem <- function(x) {
  norm_header(sub("\\s*\\(.*$", "", trimws(x)))
}

#' TRUE when a data frame already carries the computed flags — i.e. it is the
#' Excel Logic sheet rather than a raw export.
has_logic_flags <- function(df) {
  h <- norm_header(colnames(df))
  sum(c("symptomatic", "mb+", "tbpresumptive", "crdpresumptive", "spirodone") %in% h) >= 3
}

#' Build a lookup from canonical column name to the data frame's actual column.
resolve_raw_columns <- function(df) {
  actual <- colnames(df)
  key    <- norm_header(actual)

  stem <- header_stem(actual)

  find <- function(want) {
    hit <- which(key == norm_header(want))
    if (length(hit) > 0) return(actual[hit[1]])

    # Fall back to the stem, but only when it identifies exactly one column —
    # an ambiguous stem is worse than a missing one, because it would silently
    # pick a neighbour.
    hit <- which(stem == header_stem(want))
    if (length(hit) == 1) return(actual[hit])

    NA_character_
  }

  map <- vapply(c(RAW_REQUIRED, RAW_OPTIONAL), find, character(1))

  missing_required <- RAW_REQUIRED[is.na(map[RAW_REQUIRED])]
  if (length(missing_required) > 0) {
    stop(
      "The RIS export is missing ", length(missing_required),
      " column(s) needed to compute the Logic sheet:\n",
      paste0("    - ", missing_required, collapse = "\n"),
      "\n\n  Either the export format changed, or this is not the full",
      " beneficiary export.",
      call. = FALSE
    )
  }

  map
}

# ── Small helpers matching the legacy port's semantics ───────────────────────

#' Column accessor. Returns a run of NA when an optional column is absent, so
#' every downstream `replace_na(..., FALSE)` lands on FALSE.
gcol <- function(df, map, name) {
  col <- map[[name]]
  if (is.na(col)) rep(NA, nrow(df)) else df[[col]]
}

#' `x == "yes"`, case-insensitive, NA-safe.
is_yes <- function(x) tidyr::replace_na(tolower(trimws(as.character(x))) == "yes", FALSE)

#' `grepl(pattern, x)`, NA-safe.
has_txt <- function(x, pattern) {
  tidyr::replace_na(grepl(pattern, as.character(x), ignore.case = TRUE), FALSE)
}

#' `x == value`, NA-safe.
eq <- function(x, value) tidyr::replace_na(as.character(x) == value, FALSE)

#' Numeric coercion that does not warn on free text.
num <- function(x) suppressWarnings(as.numeric(as.character(x)))

# ─────────────────────────────────────────────────────────────────────────────

#' Compute the Logic sheet columns from a raw RIS export.
#'
#' Returns the data frame with the derived columns appended, named exactly as
#' the Excel Logic sheet names them so schema.R resolves them by header.
#'
#' @param df   raw RIS export
#' @param quiet suppress the agreement summary
compute_logic_flags <- function(df, quiet = FALSE) {
  original_cols <- colnames(df)
  map <- resolve_raw_columns(df)
  g   <- function(name) gcol(df, map, name)

  camp_id     <- g("Camp ID")
  has_camp    <- !is.na(camp_id) & trimws(as.character(camp_id)) != ""
  genki       <- g("Genki Edge Result")
  symptoms    <- g("Symptoms")
  crd         <- g("Chronic Respiratory Diseases")
  crd_other   <- g("Chronic Respiratory Diseases (Other)")
  tb_clin     <- g("TB Confirmed by Clinician")

  # ── [13A] MB+ ─────────────────────────────────────────────────────────────
  # Positive on any of the three sputum timepoints, or a molecular diagnosis
  # basis recorded in Nikshay. Blank — not "No" — where there is no camp record.
  mb_pos <- has_txt(g("Sputum Result(Same Day)"),  "Positive") |
            has_txt(g("Sputum Result(Next Day)"),  "Positive") |
            has_txt(g("Sputum Result(Other Day)"), "Positive") |
            has_txt(g("DiagnosisBasis"), "Truenat|Trunat|CBNAAT|Xpert")
  df$`MB+` <- ifelse(has_camp, ifelse(mb_pos, "Yes", "No"), "")

  # ── [13H] Symptomatic ─────────────────────────────────────────────────────
  # Deeptek's own category, not our recomputed Symptom Flag below.
  symptomatic <- eq(symptoms, "Symptomatic only") | eq(symptoms, "Symptomatic and Vulnerable")
  df$Symptomatic <- symptomatic

  # ── [13B] TB presumptive ──────────────────────────────────────────────────
  df$`TB presumptive` <- ifelse(
    has_camp,
    eq(genki, "TB Related Abnormalities") | symptomatic,
    ""
  )

  # ── [13C] Sputum Collected ────────────────────────────────────────────────
  df$`Sputum Collected` <- ifelse(
    has_camp,
    has_txt(g("Sputum Collected(Same Day)"),  "Collected") |
    has_txt(g("Sputum Collected(Next Day)"),  "Collected") |
    has_txt(g("Sputum Collected(Other Day)"), "Collected"),
    ""
  )

  # ── [13D] Sputum Tested ───────────────────────────────────────────────────
  # A result exists at any timepoint. "0" is the export's empty marker, so it
  # is excluded alongside the empty string.
  nonzero_result <- function(x) {
    s <- as.character(x)
    tidyr::replace_na(!is.na(s) & s != "" & s != "0", FALSE)
  }
  df$`Sputum Tested` <- nonzero_result(g("Sputum Result(Same Day)")) |
                        nonzero_result(g("Sputum Result(Next Day)")) |
                        nonzero_result(g("Sputum Result(Other Day)"))

  # ── [13E] Test Type ───────────────────────────────────────────────────────
  blankable <- function(x) {
    s <- as.character(x)
    ifelse(is.na(s) | s == "0", "", s)
  }
  df$`Test Type` <- paste0(
    blankable(g("Test Type(Same Day)")),
    blankable(g("Test Type(Next Day)")),
    blankable(g("Test Type(Other Day)"))
  )

  # ── [13F] CRD presumptive ─────────────────────────────────────────────────
  mmrc <- g("mMRC Scale")
  df$`CRD presumptive` <- eq(genki, "Other Chest Related Abnormalities") |
                          tidyr::replace_na(as.character(mmrc) != "0" & !is.na(mmrc) &
                                            trimws(as.character(mmrc)) != "", FALSE)

  # ── [13G] TB ──────────────────────────────────────────────────────────────
  df$TB <- eq(df$`MB+`, "Yes") | eq(tb_clin, "Yes")

  # ── [13I] Facility Visited ────────────────────────────────────────────────
  crd_nonzero <- tidyr::replace_na(
    !is.na(crd) & trimws(as.character(crd)) != "" & as.character(crd) != "0", FALSE
  )
  df$`Facility Visited` <- eq(tb_clin, "Yes") | eq(tb_clin, "No") | crd_nonzero

  # ── [13J] Spiro done ──────────────────────────────────────────────────────
  df$`Spiro done` <- crd_nonzero & !eq(crd, "LTFU")

  # ── [13K] CRD diagnosed ───────────────────────────────────────────────────
  df$`CRD diagnosed` <- eq(crd, "Asthma") | eq(crd, "COPD") | eq(crd, "Others")

  # ── [13L] CXR result × symptom status ─────────────────────────────────────
  # "Beneficiary ID not present" counts as normal, per the Excel sheet.
  cxr_normal <- eq(genki, "Normal") | eq(genki, "Beneficiary ID not present")
  cxr_tb     <- eq(genki, "TB Related Abnormalities")
  cxr_oca    <- eq(genki, "Other Chest Related Abnormalities")

  df$`CXR normal S+` <- cxr_normal &  symptomatic
  df$`CXR TB S+`     <- cxr_tb     &  symptomatic
  df$`CXR TB S-`     <- cxr_tb     & !symptomatic
  df$`CXR OCA S+`    <- cxr_oca    &  symptomatic
  df$`CXR OCA S-`    <- cxr_oca    & !symptomatic
  df$`CXR normal S-` <- cxr_normal & !symptomatic

  # ── [13N] Symptom Flag ────────────────────────────────────────────────────
  # Recomputed from the six individual symptoms, as distinct from Deeptek's
  # Symptoms category used for `Symptomatic` above.
  symptom_flag <- is_yes(g("Cough (in Last 2 Weeks)")) |
                  is_yes(g("Chest Pain (in Last 2 Weeks)")) |
                  is_yes(g("Night Sweats (in Last 2 Weeks)")) |
                  is_yes(g("Fever (in Last 2 Weeks)")) |
                  is_yes(g("Loss of Weight (in Last 3 Months)")) |
                  is_yes(g("Blood in Sputum (in Last 6 Months)"))
  df$`Symptom Flag` <- symptom_flag

  # ── [13O] Vulnerable Flag ─────────────────────────────────────────────────
  bmi   <- num(g("BMI"))
  sugar <- num(g("Blood Sugar (mg/dL)"))
  risk_cols <- c(
    "(Common) Diabetes", "(Common) Smokeless Tobacco", "(Common) Smoking",
    "(Common) Alcohol Consumption",
    "(Common) Contact of Known TB Patients (Household Contacts)",
    "(Common) Past TB (less than 5 years)",
    "(Clinical) Renal Impairment/Dialysis", "(Clinical) Liver Impairment",
    "(Clinical) Cancer", "(Clinical) Organ Transplantation",
    "(Clinical) Existing Chronic Respiratory Disease",
    "(Social) Migrant", "(Social) Factory/Construction workers",
    "(Social) Miner", "(Social) Health Care Worker", "Other Risk"
  )
  vulnerable <- Reduce(`|`, lapply(risk_cols, function(c) is_yes(g(c))))
  vulnerable <- vulnerable |
                tidyr::replace_na(bmi > 0 & bmi < 18.5, FALSE) |
                tidyr::replace_na(sugar > 140, FALSE)
  df$`Vulnerable Flag` <- vulnerable

  # ── [13P] Eligible for X-ray ──────────────────────────────────────────────
  df$`Eligible for X-ray` <- ifelse(
    vulnerable |
    tidyr::replace_na(sugar > 140, FALSE) |
    tidyr::replace_na(bmi >= 9 & bmi < 18.5, FALSE) |
    is_yes(g("Shortness Of Breath")) |
    tidyr::replace_na(as.character(g("Size Of Lump")) != "0" &
                      !is.na(g("Size Of Lump")), FALSE),
    "Yes", "No"
  )

  # ── [13R] Eligible for sputum ─────────────────────────────────────────────
  df$`Eligible for sputum` <- ifelse(
    symptomatic | eq(genki, "TB Related Abnormalities"),
    "Yes", "No"
  )

  # ── [13T] Vulnerability ───────────────────────────────────────────────────
  bid <- g("Beneficiary ID")
  df$Vulnerability <- ifelse(
    !is.na(bid) & trimws(as.character(bid)) != "",
    ifelse(symptomatic &  vulnerable, "Symptomatic and Vulnerable",
    ifelse(symptomatic & !vulnerable, "Symptomatic only",
    ifelse(!symptomatic & vulnerable, "Vulnerable only", "None"))),
    ""
  )

  # ── [13V/13W/13X/13Y/13Z] Binary CRD groupings ────────────────────────────
  df$`COPD/Asthma FLAG` <- as.integer(eq(crd, "Asthma") | eq(crd, "COPD"))

  crd_other_in <- function(values) {
    Reduce(`|`, lapply(values, function(v) eq(crd_other, v)))
  }
  df$`CRD (other) FLAG` <- as.integer(crd_other_in(c(
    "Diagnosis - Respiratory - Allergic Rhinitis",
    "Diagnosis - Respiratory - Asthma and COPD Overlap",
    "Diagnosis - Respiratory - Fibrosis",
    "Diagnosis - Respiratory - Mixed Airway Disease",
    "Diagnosis - Respiratory - Obstructive Airway Disease",
    "Diagnosis - Respiratory - Post TB COPD",
    "Diagnosis - Respiratory - Post TB Fibrosis",
    "Diagnosis - Respiratory - Small Airway Disease"
  )))
  df$`Final CRD Flag` <- as.integer(symptom_flag | vulnerable)
  df$`Under process` <- as.integer(
    has_txt(crd_other, "^Process -") | has_txt(crd_other, "^dublicate create id")
  )
  df$`Non-CRD Flag` <- as.integer(crd_other_in(c(
    "Diagnosis - Non Respiratory - Anemia",
    "Diagnosis - Non Respiratory - Anxiety",
    "Diagnosis - Non Respiratory - GERD",
    "Diagnosis - Non Respiratory - Obstructive Sleep Apnea",
    "Diagnosis - Non-Respiratory - Others",
    "Diagnosis- Non Respiratory - Cardiac Causes"
  )))

  # ── [13Q/13S/13U] Agreement with Deeptek ──────────────────────────────────
  # Deeptek computes its own eligibility and symptom categories. Comparing ours
  # against theirs is the cheapest available check that this port is behaving:
  # a sudden drop in agreement means one side changed.
  agreement <- compute_agreement(df, map, g)
  attr(df, "deeptek_agreement") <- agreement
  # Recorded so resolve_schema() can break pattern ties in favour of what we
  # computed, rather than a raw column that happens to match too.
  attr(df, "computed_columns") <- setdiff(colnames(df), original_cols)
  if (!quiet) report_agreement(agreement)

  df
}

#' Rates at which our computed flags match Deeptek's own columns.
compute_agreement <- function(df, map, g) {
  pairs <- list(
    xray   = list(ours = df$`Eligible for X-ray`,  theirs = g("X-Ray Eligibility")),
    sputum = list(ours = df$`Eligible for sputum`, theirs = g("Sputum Eligibility")),
    vulne  = list(ours = df$Vulnerability,         theirs = g("Symptoms"))
  )

  lapply(pairs, function(p) {
    if (all(is.na(p$theirs))) return(list(available = FALSE))
    comparable <- !is.na(p$theirs) & trimws(as.character(p$theirs)) != ""
    n <- sum(comparable)
    if (n == 0) return(list(available = FALSE))
    matched <- sum(
      trimws(as.character(p$ours)[comparable]) ==
      trimws(as.character(p$theirs)[comparable])
    )
    list(available = TRUE, n = n, matched = matched, rate = matched / n)
  })
}

report_agreement <- function(agreement) {
  labels <- c(xray = "Eligible for X-ray", sputum = "Eligible for sputum",
              vulne = "Vulnerability")
  shown <- FALSE
  for (k in names(agreement)) {
    a <- agreement[[k]]
    if (!isTRUE(a$available)) next
    if (!shown) {
      message("[flags] computed in R; agreement with Deeptek's own columns:")
      shown <- TRUE
    }
    message(sprintf("  - %-20s %5.1f%% of %s rows", labels[[k]], 100 * a$rate,
                    format(a$n, big.mark = ",")))
    if (a$rate < 0.95) {
      message("      ^ below 95% — worth checking before trusting these figures")
    }
  }
}

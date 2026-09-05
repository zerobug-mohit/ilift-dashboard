# ─────────────────────────────────────────────────────────────────────────────
# schema.R — canonical column mapping for the RIS "Logic sheet"
#
# WHY THIS EXISTS
# The legacy scripts address columns purely by position: d[[50]], d[[101]],
# d[[106]], d[[155]]... If RISHUB ever reorders or inserts a column, every
# metric silently changes with no error. calc_v2.R:19-27 documents the
# positions in a comment, which is not enforcement.
#
# This module resolves each logical field by matching the actual header text,
# falling back to the legacy position, and reporting anything it could not
# confirm. A wrong column now surfaces as a warning instead of a wrong number.
#
# KNOWN DISCREPANCY (unresolved until a real RIS export is available):
#   calc_nns.R:49-50    treats cols 73,74 as "Night Sweats" / "Fever"  (yes/no)
#   calc_weekly.R:110   treats cols 73,74 as "Latitude" / "Longitude"  (numeric)
# Both read the same sheet, so one is wrong. Whichever it is, the consuming
# code fails silently: as.numeric("Yes") -> NA (map pins vanish), and
# yn(<latitude>) -> FALSE (NNS symptom counts read zero).
# resolve_schema() flags this pair explicitly. See check_known_conflicts().
# ─────────────────────────────────────────────────────────────────────────────

# field name -> list(idx = legacy position, pat = header regex, type = expected)
LOGIC_SCHEMA <- list(
  camp_id            = list(idx = 1,   pat = "^camp\\s*id",                    type = "chr"),
  # Anchored so "Camp Last Update Date" cannot win.
  camp_date          = list(idx = 2,   pat = "camp\\s*creation\\s*date",       type = "date"),
  camp_district      = list(idx = 6,   pat = "district",                       type = "chr"),
  # Two spellings of the same field: the Logic sheet says "Camp Area Type",
  # the raw export "Type of Camp". Anchored so plain "Area Type" — a different
  # column entirely — cannot match.
  camp_area_type     = list(idx = 11,  pat = "^camp\\s*area\\s*type$|^type\\s*of\\s*camp$",
                                                                               type = "chr"),
  # Likewise "Area Classification" (Logic sheet) vs "Area Type" (raw export).
  area_classification= list(idx = 14,  pat = "^area\\s*classification$|^area\\s*type$",
                                                                               type = "chr"),

  beneficiary_id     = list(idx = 50,  pat = "beneficiary\\s*id",              type = "chr"),
  age                = list(idx = 52,  pat = "^(beneficiary\\s*)?age$",        type = "num"),
  gender             = list(idx = 54,  pat = "^(beneficiary\\s*)?(gender|sex)$",
                                                                               type = "chr"),
  nikshay_id         = list(idx = 56,  pat = "nikshay\\s*id",                  type = "num"),

  bmi                = list(idx = 60,  pat = "^bmi",                           type = "num"),
  blood_sugar        = list(idx = 63,  pat = "blood\\s*sugar|rbs",             type = "num"),
  # "Test Available: SpO2" is a flag saying the test was offered, not a reading.
  spo2               = list(idx = 64,  pat = "^spo2$|pulse\\s*oximeter",       type = "num"),
  bp_systolic        = list(idx = 66,  pat = "systolic|blood\\s*pressure",     type = "num"),
  # Requiring "result" separates the reading from "Test Available: Sickle cell
  # disease" and from the bare "Sickle Cell Disease" risk-factor column.
  scd_result         = list(idx = 68,  pat = "sickle.*result|^scd.*result",    type = "chr"),

  sym_cough          = list(idx = 71,  pat = "cough",                          type = "yn"),
  sym_chest_pain     = list(idx = 72,  pat = "chest\\s*pain",                  type = "yn"),
  sym_night_sweats   = list(idx = 73,  pat = "night\\s*sweat",                 type = "yn"),
  sym_fever          = list(idx = 74,  pat = "fever",                          type = "yn"),
  sym_weight_loss    = list(idx = 75,  pat = "weight\\s*loss|loss\\s*of\\s*weight", type = "yn"),
  sym_blood_sputum   = list(idx = 76,  pat = "blood.*sputum|haemoptysis",      type = "yn"),

  mmrc_scale         = list(idx = 80,  pat = "mmrc",                           type = "chr"),
  tobacco_any        = list(idx = 83,  pat = "tobacco",                        type = "yn"),
  smoking            = list(idx = 84,  pat = "smoking",                        type = "yn"),
  alcohol            = list(idx = 85,  pat = "alcohol",                        type = "yn"),
  hh_contact_tb      = list(idx = 86,  pat = "(hh|household).*contact",        type = "yn"),
  past_tb            = list(idx = 87,  pat = "past.*tb|previous.*tb",          type = "yn"),
  current_tb_tx      = list(idx = 88,  pat = "current.*tb|on\\s*tb\\s*treat",  type = "yn"),

  migrant            = list(idx = 94,  pat = "migrant",                        type = "yn"),
  factory_worker     = list(idx = 95,  pat = "factory",                        type = "yn"),
  # "(Social) Miner" in the raw export, "Mine Worker" on the Logic sheet.
  mine_worker        = list(idx = 96,  pat = "mine\\s*worker|mining\\s*work|\\bminer\\b",
                                                                               type = "yn"),
  healthcare_worker  = list(idx = 97,  pat = "health\\s*care\\s*worker|hcw",   type = "yn"),

  xray_taken         = list(idx = 101, pat = "x.?ray.*taken",                  type = "chr"),
  genki_result       = list(idx = 106, pat = "genki|ai.*result",               type = "chr"),
  eptb               = list(idx = 137, pat = "eptb|extra.?pulmonary",          type = "yn"),
  # Anchored: "(Clinical) Existing Chronic Respiratory Disease" is a risk
  # factor and "Chronic Respiratory Diseases (Other)" a free-text field.
  crd_result         = list(idx = 142, pat = "^chronic\\s*respiratory\\s*diseases?$",
                                                                               type = "chr"),

  # Flag columns — computed by Excel formulas in Phase 1,
  # computed natively by flags.R in Phase 2.
  mb_positive        = list(idx = 155, pat = "^mb\\+",                         type = "chr"),
  tb_presumptive     = list(idx = 156, pat = "tb\\s*presumptive",              type = "lgl"),
  sputum_collected   = list(idx = 157, pat = "sputum\\s*collected",            type = "lgl"),
  sputum_tested      = list(idx = 158, pat = "sputum\\s*tested",               type = "lgl"),
  crd_presumptive    = list(idx = 160, pat = "crd\\s*presumptive",             type = "lgl"),
  tb                 = list(idx = 161, pat = "^tb$",                           type = "lgl"),
  symptomatic        = list(idx = 162, pat = "^symptomatic$",                  type = "lgl"),
  facility_visited   = list(idx = 163, pat = "facility\\s*visited",            type = "lgl"),
  spiro_done         = list(idx = 164, pat = "spiro\\s*done",                  type = "lgl"),
  crd_diagnosed      = list(idx = 165, pat = "crd\\s*diagnosed",               type = "lgl"),
  cxr_norm_sp        = list(idx = 166, pat = "cxr\\s*normal\\s*s\\+",          type = "lgl"),
  cxr_tb_sp          = list(idx = 167, pat = "cxr\\s*tb\\s*s\\+",              type = "lgl"),
  cxr_tb_sn          = list(idx = 168, pat = "cxr\\s*tb\\s*s-",                type = "lgl"),
  cxr_oca_sp         = list(idx = 169, pat = "cxr\\s*oca\\s*s\\+",             type = "lgl"),
  cxr_oca_sn         = list(idx = 170, pat = "cxr\\s*oca\\s*s-",               type = "lgl"),
  cxr_norm_sn        = list(idx = 171, pat = "cxr\\s*normal\\s*s-",            type = "lgl"),
  vulnerable         = list(idx = 174, pat = "vulnerable",                     type = "lgl"),
  eligible_sputum    = list(idx = 177, pat = "eligible.*sputum",               type = "chr")
)

# Columns whose legacy positions conflict between scripts. See header note.
KNOWN_CONFLICTS <- list(
  list(idx = 73, claimants = c("sym_night_sweats (calc_nns.R:49)",
                               "latitude (calc_weekly.R:110)")),
  list(idx = 74, claimants = c("sym_fever (calc_nns.R:50)",
                               "longitude (calc_weekly.R:111)"))
)

#' Resolve the schema against a real data frame's headers.
#'
#' For each field: try to match the header text; if that fails, fall back to
#' the legacy index. Returns a list with the resolved index per field plus a
#' diagnostics table describing how each was resolved.
#' @param prefer column names this caller knows to be authoritative. When a
#'   pattern matches several headers and one of them is in `prefer`, that one
#'   wins. flags.R uses it for the columns it computes: "sputum collected"
#'   matches both its aggregate "Sputum Collected" and the raw per-timepoint
#'   "Sputum Collected(Same Day)", and without this the legacy position would
#'   quietly select the wrong one.
resolve_schema <- function(df, schema = LOGIC_SCHEMA, prefer = character(0)) {
  headers <- tolower(trimws(colnames(df)))
  ncols   <- length(headers)
  prefer_idx <- which(colnames(df) %in% prefer)

  resolved <- list()
  diags    <- list()

  for (nm in names(schema)) {
    spec <- schema[[nm]]
    hit  <- grep(spec$pat, headers, perl = TRUE)

    if (length(hit) == 1) {
      idx <- hit
      how <- if (idx == spec$idx) "name+position agree" else "name (position differs)"
    } else if (length(hit) > 1 && length(intersect(hit, prefer_idx)) == 1) {
      idx <- intersect(hit, prefer_idx)
      how <- "name (computed column preferred)"
    } else if (length(hit) > 1) {
      # Ambiguous header match — prefer the legacy position if it is among them
      idx <- if (spec$idx %in% hit) spec$idx else hit[1]
      how <- "ambiguous name, position preferred"
    } else if (spec$idx <= ncols) {
      idx <- spec$idx
      how <- "position only (no header match)"
    } else {
      idx <- NA_integer_
      how <- "MISSING"
    }

    resolved[[nm]] <- idx
    diags[[length(diags) + 1]] <- list(
      field = nm, index = idx, legacy_index = spec$idx,
      header = if (is.na(idx)) NA_character_ else colnames(df)[idx],
      how = how
    )
  }

  list(index = resolved, diagnostics = diags)
}

#' Report fields that could not be confirmed by header text. Called at ingest
#' so problems appear in the server log and in GET /api/meta.
#' Report fields whose column could not be established from the header.
#'
#' "name (position differs)" is deliberately not a warning: the header matched,
#' which is the outcome we want — it only means the column has moved from the
#' position the legacy scripts assumed, which is precisely what resolving by
#' name is for. Reporting it trained people to ignore a banner that also
#' carries the cases that matter.
schema_warnings <- function(res) {
  bad <- Filter(function(d) d$how %in% c("MISSING", "position only (no header match)") ||
                            grepl("ambiguous", d$how), res$diagnostics)
  lapply(bad, function(d) sprintf("column '%s': %s (using index %s, header '%s')",
                                  d$field, d$how, d$index, d$header))
}

#' Surface the col 73/74 conflict against real headers so it can be settled.
check_known_conflicts <- function(df) {
  hdr <- colnames(df)
  lapply(KNOWN_CONFLICTS, function(c) {
    list(
      index     = c$idx,
      header    = if (c$idx <= length(hdr)) hdr[c$idx] else NA_character_,
      claimants = c$claimants
    )
  })
}

#' Accessor: pull a logical field out of a data frame using the resolved map.
#' Replaces bare d[[50]] / d[[106]] positional access throughout the metrics.
fld <- function(df, map, name) {
  idx <- map[[name]]
  if (is.null(idx) || is.na(idx)) return(rep(NA, nrow(df)))
  df[[idx]]
}

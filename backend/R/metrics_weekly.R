# ─────────────────────────────────────────────────────────────────────────────
# metrics_weekly.R — weekly review + per-camp detail
# Ported from calc_weekly.R:33-135, with named columns.
#
# NOTE ON LATITUDE/LONGITUDE
# calc_weekly.R:110-111 reads columns 73 and 74 as Latitude/Longitude, but
# calc_nns.R:49-50 reads the same two columns as the "Night Sweats" and "Fever"
# symptom flags. Both read the same sheet, so at most one can be right.
# Here the coordinates are resolved by header name only — if no latitude and
# longitude headers exist, camps are returned without coordinates rather than
# silently coercing "Yes"/"No" to NA. See schema.R KNOWN_CONFLICTS.
# ─────────────────────────────────────────────────────────────────────────────

pct0 <- function(x, y) if (is.na(y) || y == 0) 0 else round(x / y * 100, 1)

#' Locate latitude/longitude columns by header text only. Returns NULL if absent.
find_latlon <- function(df) {
  hdr <- tolower(trimws(colnames(df)))
  lat <- grep("^lat(itude)?$", hdr)
  lon <- grep("^(lon|lng|long(itude)?)$", hdr)
  if (length(lat) == 1 && length(lon) == 1) list(lat = lat, lon = lon) else NULL
}

#' Weekly review for the most recent complete weeks.
#' `n_weeks` summary rows; `n_camp_weeks` weeks of per-camp detail.
weekly_for_range <- function(bundle, from = NULL, to = NULL,
                             n_weeks = 4, n_camp_weeks = 2, today = Sys.Date()) {
  map <- bundle$ris$map
  f   <- function(df, name) fld(df, map, name)

  L <- slice_logic(bundle$ris$logic, from, to, "all")
  if (nrow(L) == 0) return(list(weeks = list(), camps = list()))

  L$CampID   <- f(L, "camp_id")
  L$BID      <- as.character(f(L, "beneficiary_id"))
  L$Gender   <- trimws(as.character(f(L, "gender")))
  L$EligSp   <- f(L, "eligible_sputum")
  L$SpColl   <- f(L, "sputum_collected")
  L$SpTest   <- f(L, "sputum_tested")
  L$SpO2     <- suppressWarnings(as.numeric(f(L, "spo2")))
  L$RBS      <- suppressWarnings(as.numeric(f(L, "blood_sugar")))
  L$SBP      <- suppressWarnings(as.numeric(f(L, "bp_systolic")))
  L$Age      <- suppressWarnings(as.numeric(f(L, "age")))
  L$SCD_val  <- as.character(f(L, "scd_result"))
  L$District <- as.character(f(L, "camp_district"))

  # Week starting Monday (calc_weekly.R:27-28)
  L$dow          <- as.integer(format(L$camp_date, "%u"))
  L$week_monday  <- L$camp_date - (L$dow - 1L)

  all_weeks      <- sort(unique(L$week_monday), decreasing = TRUE)
  complete_weeks <- all_weeks[all_weeks + 6 < today]   # exclude partial current week
  recent <- head(complete_weeks, n_weeks)

  scd_pos_vals <- c("POCT - Sickle cell disease", "POCT - Sickle cell trait",
                    "Solubility - screened +ve")

  weeks <- lapply(recent, function(wk) {
    wdata    <- L[L$week_monday == wk, ]
    n_camps  <- length(unique(wdata$CampID))
    uniq     <- wdata[!duplicated(wdata$BID), ]
    n_screen <- nrow(uniq)

    n_male   <- sum(uniq$Gender == "Male",   na.rm = TRUE)
    n_elig   <- sum(uniq$EligSp == "Yes",    na.rm = TRUE)
    n_coll   <- sum(uniq$SpColl == TRUE,     na.rm = TRUE)
    n_test   <- sum(uniq$SpTest == TRUE,     na.rm = TRUE)

    list(
      week      = format(wk, "%Y-%m-%d"),
      week_end  = format(wk + 6, "%Y-%m-%d"),
      n_camps   = n_camps,
      n_screen  = n_screen,
      avg_ff    = if (n_camps > 0) round(n_screen / n_camps, 1) else 0,
      pct_male  = pct0(n_male, n_screen),
      n_elig    = n_elig,
      n_coll    = n_coll,
      n_test    = n_test,
      pct_coll  = pct0(n_coll, n_elig),
      pct_test  = pct0(n_test, n_coll),
      pct_spo2  = pct0(sum(!is.na(uniq$SpO2) & uniq$SpO2 > 0, na.rm = TRUE), n_screen),
      pct_rbs   = pct0(sum(!is.na(uniq$RBS)  & uniq$RBS  > 0, na.rm = TRUE), n_screen),
      pct_bp    = pct0(sum(!is.na(uniq$SBP)  & uniq$SBP  > 0, na.rm = TRUE), n_screen),
      n_le40    = sum(!is.na(uniq$Age) & uniq$Age <= 40, na.rm = TRUE),
      n_scd_pos = sum(uniq$SCD_val %in% scd_pos_vals, na.rm = TRUE)
    )
  })

  # ── Per-camp detail for the most recent weeks ──────────────────────────────
  latlon <- find_latlon(L)
  camps <- lapply(head(recent, n_camp_weeks), function(wk) {
    wdata <- L[L$week_monday == wk, ]
    per_camp <- lapply(unique(wdata$CampID), function(cid) {
      cd   <- wdata[wdata$CampID == cid, ]
      uniq <- cd[!duplicated(cd$BID), ]

      out <- list(
        camp_id   = as.character(cid),
        camp_date = format(cd$camp_date[1], "%Y-%m-%d"),
        district  = cd$District[1],
        n_screen  = nrow(uniq),
        n_male    = sum(uniq$Gender == "Male",   na.rm = TRUE),
        n_female  = sum(uniq$Gender == "Female", na.rm = TRUE),
        n_elig    = sum(uniq$EligSp == "Yes",    na.rm = TRUE),
        n_coll    = sum(uniq$SpColl == TRUE,     na.rm = TRUE),
        n_test    = sum(uniq$SpTest == TRUE,     na.rm = TRUE)
      )

      if (!is.null(latlon)) {
        lat <- suppressWarnings(as.numeric(cd[[latlon$lat]][1]))
        lon <- suppressWarnings(as.numeric(cd[[latlon$lon]][1]))
        if (!is.na(lat)) out$lat <- lat
        if (!is.na(lon)) out$lon <- lon
      }
      out
    })

    list(week = format(wk, "%Y-%m-%d"), camps = per_camp)
  })

  list(weeks = weeks, camps = camps, has_coordinates = !is.null(latlon))
}

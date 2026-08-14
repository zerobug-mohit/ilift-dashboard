# ─────────────────────────────────────────────────────────────────────────────
# metrics_core.R — port of calc_logic() from calc_v2.R:72-410
#
# Semantics are preserved exactly. Two things changed:
#
#  1. Positional access d[[50]] / d[[106]] / ... is replaced by named access
#     f(d, "beneficiary_id") resolved through schema.R.
#
#  2. calc_logic() closed over nik_episode_ids and spiro_comp_crd from the
#     global environment. They are now passed explicitly via `ctx`, which is
#     what allows the function to be called per-request with an arbitrary slice.
#
# THE RANGE-DEDUP FIX
# calc_logic() deduplicates beneficiaries within whatever slice it is given
# (calc_v2.R:73). The legacy pipeline only ever called it per-month, then the
# browser summed those monthly values for any user-selected range
# (build_v3.py:703). A beneficiary screened in two months was therefore counted
# twice. Calling this function with the actual requested range instead — see
# metrics_for_range() — dedups across the whole range and matches Excel.
# ─────────────────────────────────────────────────────────────────────────────

# Helpers, identical to calc_v2.R:68-69
n_  <- function(expr) sum(expr, na.rm = TRUE)
yn_ <- function(x) x %in% c("yes", "Yes", "YES", TRUE, "TRUE", "true", "1", 1)

#' Build the context calc_logic needs beyond the data slice itself.
make_ctx <- function(bundle) {
  list(
    map        = bundle$ris$map,
    nik_ids    = bundle$nik$episode_ids,
    spiro_bids = bundle$crd$spiro_comp_bids
  )
}

calc_logic <- function(data, ctx) {
  map <- ctx$map
  f   <- function(df, name) fld(df, map, name)

  # Dedup by beneficiary within this slice — the whole point of the fix
  d       <- data[!duplicated(as.character(f(data, "beneficiary_id"))), ]
  bid_set <- as.character(f(d, "beneficiary_id"))

  n_camps       <- length(unique(f(data, "camp_id")))
  n_screened    <- nrow(d)
  n_cxr         <- n_(f(d, "xray_taken") == "Yes")
  n_ai_tb       <- n_(f(d, "genki_result") == "TB Related Abnormalities")
  n_ai_oca      <- n_(f(d, "genki_result") == "Other Chest Related Abnormalities")
  n_symptomatic <- n_(f(d, "symptomatic") == TRUE)
  n_vuln        <- n_(f(d, "vulnerable") == TRUE)

  # ── Sputum ─────────────────────────────────────────────────────────────────
  n_elig_sp   <- n_(f(d, "eligible_sputum") == "Yes")
  n_sp_coll   <- n_(f(d, "sputum_collected") == TRUE)
  n_sp_coll_t <- n_sp_coll
  n_sp_test   <- n_(f(d, "sputum_tested") == TRUE)

  # ── TB ─────────────────────────────────────────────────────────────────────
  n_mbc      <- n_(as.character(f(d, "mb_positive")) == "Yes")
  n_notified <- n_(f(d, "tb") == TRUE)
  n_cd       <- n_notified - n_mbc

  # Treatment started — unique Nikshay IDs matched against the Nikshay export
  nik_id_set   <- suppressWarnings(as.numeric(f(d, "nikshay_id")))
  nik_id_set   <- nik_id_set[!is.na(nik_id_set) & nik_id_set != 0]
  n_tx_started <- length(unique(nik_id_set[nik_id_set %in% ctx$nik_ids]))

  # ── CXR × symptom categories ───────────────────────────────────────────────
  n_cxr_norm_sp <- n_(f(d, "cxr_norm_sp") == TRUE)
  n_cxr_tb_sp   <- n_(f(d, "cxr_tb_sp")   == TRUE)
  n_cxr_tb_sn   <- n_(f(d, "cxr_tb_sn")   == TRUE)
  n_cxr_oca_sp  <- n_(f(d, "cxr_oca_sp")  == TRUE)
  n_cxr_oca_sn  <- n_(f(d, "cxr_oca_sn")  == TRUE)
  n_cxr_norm_sn <- n_(f(d, "cxr_norm_sn") == TRUE)

  # ── Lung-health pathway ────────────────────────────────────────────────────
  tb_pres_v  <- f(d, "tb_presumptive")
  crd_pres_v <- f(d, "crd_presumptive")
  tb_pres    <- tb_pres_v  == TRUE & !is.na(tb_pres_v)
  crd_pres   <- crd_pres_v == TRUE & !is.na(crd_pres_v)

  n_tb_only  <- n_( tb_pres & !crd_pres)
  n_tb_crd   <- n_( tb_pres &  crd_pres)
  n_crd_only <- n_(!tb_pres &  crd_pres)
  n_neither  <- n_(!tb_pres & !crd_pres)

  tb_v     <- f(d, "tb")
  tb_conf  <- tb_v == TRUE & !is.na(tb_v)
  n_lh1_tb <- n_( tb_pres & !crd_pres & tb_conf)
  n_tbc_tb <- n_( tb_pres &  crd_pres & tb_conf)
  n_crd_tb <- n_(!tb_pres &  crd_pres & tb_conf)
  n_nne_tb <- n_(!tb_pres & !crd_pres & tb_conf)

  cur_v     <- f(d, "current_tb_tx")
  n_cur_tb  <- n_(cur_v == "Yes" & !is.na(cur_v))
  n_eptb    <- n_(yn_(f(d, "eptb")))
  n_ptb_tb  <- n_(yn_(f(d, "past_tb")) & tb_conf)
  spo2_v    <- suppressWarnings(as.numeric(f(d, "spo2")))
  n_spo2_92 <- n_(!is.na(spo2_v) & spo2_v > 0 & spo2_v <= 92)

  # ── Facility / CRD ─────────────────────────────────────────────────────────
  n_facility   <- n_(f(d, "facility_visited") == TRUE)
  n_spiro      <- n_(f(d, "spiro_done") == TRUE)
  n_spiro_comp <- sum(ctx$spiro_bids %in% bid_set)
  n_copd       <- n_(as.character(f(d, "crd_result")) == "COPD")
  n_asthma     <- n_(as.character(f(d, "crd_result")) == "Asthma")
  n_crd_dx     <- n_(f(d, "crd_diagnosed") == TRUE)
  n_crd_pres_t <- n_(crd_pres)

  # ── mMRC breathlessness grades ─────────────────────────────────────────────
  mmrc_str   <- as.character(f(d, "mmrc_scale"))
  n_mmrc_1   <- n_(grepl("^Grade 1:", mmrc_str))
  n_mmrc_2   <- n_(grepl("^Grade 2:", mmrc_str))
  n_mmrc_3   <- n_(grepl("^Grade 3:", mmrc_str))
  n_mmrc_4   <- n_(grepl("^Grade 4:", mmrc_str))
  n_mmrc_5   <- n_(mmrc_str == "grade_5")
  n_mmrc_pos <- n_mmrc_1 + n_mmrc_2 + n_mmrc_3 + n_mmrc_4 + n_mmrc_5
  n_mmrc_0   <- nrow(d) - n_mmrc_pos

  mmrc_cas_g <- function(rows) {
    if (nrow(rows) == 0) return(c(fac=0L, spiro=0L, copd=0L, asthma=0L, crd=0L, tb=0L))
    c(fac    = n_(f(rows, "facility_visited") == TRUE),
      spiro  = n_(f(rows, "spiro_done") == TRUE),
      copd   = n_(as.character(f(rows, "crd_result")) == "COPD"),
      asthma = n_(as.character(f(rows, "crd_result")) == "Asthma"),
      crd    = n_(f(rows, "crd_diagnosed") == TRUE),
      tb     = n_(f(rows, "tb") == TRUE))
  }
  mpos <- grepl("^Grade [1-4]:", mmrc_str) | mmrc_str == "grade_5"
  gc0 <- mmrc_cas_g(d[!mpos, ])
  gc1 <- mmrc_cas_g(d[grepl("^Grade 1:", mmrc_str), ])
  gc2 <- mmrc_cas_g(d[grepl("^Grade 2:", mmrc_str), ])
  gc3 <- mmrc_cas_g(d[grepl("^Grade 3:", mmrc_str), ])
  gc4 <- mmrc_cas_g(d[grepl("^Grade 4:", mmrc_str), ])
  gc5 <- mmrc_cas_g(d[mmrc_str == "grade_5", ])

  # ── Lung-health pathway sub-groups ─────────────────────────────────────────
  lhp_g <- function(rows) {
    if (nrow(rows) == 0) return(c(tot=0L, fac=0L, spiro=0L, cpd=0L, ast=0L, oth=0L))
    crd_count <- n_(f(rows, "crd_diagnosed") == TRUE)
    cpd <- n_(as.character(f(rows, "crd_result")) == "COPD")
    ast <- n_(as.character(f(rows, "crd_result")) == "Asthma")
    c(tot = nrow(rows),
      fac = n_(f(rows, "facility_visited") == TRUE),
      spiro = n_(f(rows, "spiro_done") == TRUE),
      cpd = cpd, ast = ast, oth = crd_count - cpd - ast)
  }
  mpos_d   <- mpos
  genki_v  <- f(d, "genki_result")
  oca_flag <- !is.na(genki_v) & genki_v == "Other Chest Related Abnormalities"

  lg1 <- lhp_g(d[ tb_pres & !crd_pres, ])
  lg2 <- lhp_g(d[ tb_pres &  crd_pres &  mpos_d & !oca_flag, ])
  lg3 <- lhp_g(d[ tb_pres &  crd_pres & !mpos_d &  oca_flag, ])
  lg4 <- lhp_g(d[ tb_pres &  crd_pres &  mpos_d &  oca_flag, ])
  lg5 <- lhp_g(d[!tb_pres &  crd_pres &  mpos_d & !oca_flag, ])
  lg6 <- lhp_g(d[!tb_pres &  crd_pres & !mpos_d &  oca_flag, ])
  lg7 <- lhp_g(d[!tb_pres &  crd_pres &  mpos_d &  oca_flag, ])
  lg8 <- lhp_g(d[!tb_pres & !crd_pres, ])

  # Alternative CRD-presumptive definition (mMRC positive OR past TB)
  ptb_flag     <- yn_(f(d, "past_tb"))
  new_crd_pres <- mpos_d | ptb_flag
  lg1n <- lhp_g(d[ tb_pres & !new_crd_pres, ])
  lg2n <- lhp_g(d[ tb_pres &  new_crd_pres &  mpos_d & !ptb_flag, ])
  lg3n <- lhp_g(d[ tb_pres &  new_crd_pres & !mpos_d &  ptb_flag, ])
  lg4n <- lhp_g(d[ tb_pres &  new_crd_pres &  mpos_d &  ptb_flag, ])
  lg5n <- lhp_g(d[!tb_pres &  new_crd_pres &  mpos_d & !ptb_flag, ])
  lg6n <- lhp_g(d[!tb_pres &  new_crd_pres & !mpos_d &  ptb_flag, ])
  lg7n <- lhp_g(d[!tb_pres &  new_crd_pres &  mpos_d &  ptb_flag, ])
  lg8n <- lhp_g(d[!tb_pres & !new_crd_pres, ])

  # ── NCD ────────────────────────────────────────────────────────────────────
  bs <- suppressWarnings(as.numeric(f(d, "blood_sugar")))
  bp <- suppressWarnings(as.numeric(f(d, "bp_systolic")))
  n_rbs      <- n_(!is.na(bs) & bs > 0)
  n_rbs_200p <- n_(!is.na(bs) & bs > 200)
  n_rbs_140p <- n_(!is.na(bs) & bs > 140)
  n_bp       <- n_(!is.na(bp) & bp > 0)
  n_bp_160p  <- n_(!is.na(bp) & bp >= 160)
  n_bp_140p  <- n_(!is.na(bp) & bp >= 140)

  # ── SCD ────────────────────────────────────────────────────────────────────
  scd <- as.character(f(d, "scd_result"))
  n_scd_screen <- n_(scd %in% c("POCT - Normal", "POCT - Sickle cell disease",
                                "POCT - Sickle cell trait",
                                "Solubility - screened -ve", "Solubility - screened +ve"))
  n_scd_pos    <- n_(scd %in% c("POCT - Sickle cell disease", "POCT - Sickle cell trait",
                                "Solubility - screened +ve"))
  n_scd_sol      <- n_(grepl("Solubility", scd))
  n_scd_sol_pos  <- n_(scd == "Solubility - screened +ve")
  n_scd_poct     <- n_(grepl("POCT", scd))
  n_scd_poct_pos <- n_(scd %in% c("POCT - Sickle cell disease", "POCT - Sickle cell trait"))

  age_v       <- suppressWarnings(as.numeric(f(d, "age")))
  n_under40   <- n_(!is.na(age_v) & age_v <= 40)
  n_past_tb   <- n_(yn_(f(d, "past_tb")))
  n_crd_other <- n_crd_dx - n_copd - n_asthma

  # ── Past-TB sub-cohort ─────────────────────────────────────────────────────
  d_ptb            <- d[yn_(f(d, "past_tb")), ]
  n_ptb_fac        <- n_(f(d_ptb, "facility_visited") == TRUE)
  n_ptb_spiro      <- n_(f(d_ptb, "spiro_done") == TRUE)
  n_ptb_copd       <- n_(as.character(f(d_ptb, "crd_result")) == "COPD")
  n_ptb_asthma     <- n_(as.character(f(d_ptb, "crd_result")) == "Asthma")
  n_ptb_crd_dx     <- n_(f(d_ptb, "crd_diagnosed") == TRUE)
  n_ptb_crd_other  <- n_ptb_crd_dx - n_ptb_copd - n_ptb_asthma
  n_ptb_spiro_comp <- sum(ctx$spiro_bids %in% as.character(f(d_ptb, "beneficiary_id")))

  # ── Asymptomatic yield ─────────────────────────────────────────────────────
  symp_v      <- f(d, "symptomatic")
  symp_flag   <- symp_v == TRUE & !is.na(symp_v)
  n_asymp_tb  <- n_(tb_conf & !symp_flag)
  n_asymp_mbc <- n_(as.character(f(d, "mb_positive")) == "Yes" & !symp_flag)

  ai_flag <- !is.na(genki_v) & genki_v == "TB Related Abnormalities"

  # ── CRD risk-variable cross-tabs ───────────────────────────────────────────
  crd_res_v  <- f(d, "crd_result")
  copd_flg   <- as.character(crd_res_v) == "COPD" & !is.na(crd_res_v)
  fac_v      <- f(d, "facility_visited")
  fac_flg    <- fac_v == TRUE & !is.na(fac_v)
  cough_flg  <- yn_(f(d, "sym_cough"))
  smoke_flg  <- yn_(f(d, "tobacco_any")) | yn_(f(d, "smoking"))
  bmi_v2     <- suppressWarnings(as.numeric(f(d, "bmi")))
  bmi18_flg  <- !is.na(bmi_v2) & bmi_v2 > 0 & bmi_v2 < 18.5

  n_crdv_cough_fac    <- n_(cough_flg & fac_flg)
  n_crdv_cough_copd   <- n_(cough_flg & copd_flg)
  n_crdv_aitb_fac     <- n_(ai_flag   & fac_flg)
  n_crdv_aitb_copd    <- n_(ai_flag   & copd_flg)
  n_crdv_aioca_fac    <- n_(oca_flag  & fac_flg)
  n_crdv_aioca_copd   <- n_(oca_flag  & copd_flg)
  n_crdv_tobacco_fac  <- n_(smoke_flg & fac_flg)
  n_crdv_tobacco_copd <- n_(smoke_flg & copd_flg)
  n_crdv_bmi_fac      <- n_(bmi18_flg & fac_flg)
  n_crdv_bmi_copd     <- n_(bmi18_flg & copd_flg)
  n_crdv_rbs_fac      <- n_(!is.na(bs) & bs > 200 & fac_flg)
  n_crdv_rbs_copd     <- n_(!is.na(bs) & bs > 200 & copd_flg)

  chest_flg      <- yn_(f(d, "sym_chest_pain"))
  smoking_flg    <- yn_(f(d, "smoking"))
  mine_flg       <- yn_(f(d, "mine_worker"))
  factory_flg    <- yn_(f(d, "factory_worker"))
  area_v         <- f(d, "camp_area_type")
  miningcamp_flg <- as.character(area_v) == "Mining area" & !is.na(area_v)
  sp2_v          <- suppressWarnings(as.numeric(f(d, "spo2")))
  spo295_flg     <- !is.na(sp2_v) & sp2_v > 0 & sp2_v < 95

  cxr_ns_v   <- f(d, "cxr_norm_sp"); cxr_nn_v <- f(d, "cxr_norm_sn")
  ainorm_flg <- (cxr_ns_v == TRUE & !is.na(cxr_ns_v)) | (cxr_nn_v == TRUE & !is.na(cxr_nn_v))
  xray_v     <- f(d, "xray_taken")
  notaken_flg<- !(xray_v == "Yes" & !is.na(xray_v))

  spiro_v    <- f(d, "spiro_done");     spiro_flg  <- spiro_v == TRUE & !is.na(spiro_v)
  crddx_v    <- f(d, "crd_diagnosed");  crd_dx_flg <- crddx_v == TRUE & !is.na(crddx_v)

  n_crdv_chest_fac       <- n_(chest_flg & fac_flg)
  n_crdv_chest_copd      <- n_(chest_flg & copd_flg)
  n_crdv_smoking_fac     <- n_(smoking_flg & fac_flg)
  n_crdv_smoking_copd    <- n_(smoking_flg & copd_flg)
  n_crdv_mine_fac        <- n_(mine_flg & fac_flg)
  n_crdv_mine_copd       <- n_(mine_flg & copd_flg)
  n_crdv_factory_fac     <- n_(factory_flg & fac_flg)
  n_crdv_factory_copd    <- n_(factory_flg & copd_flg)
  n_crdv_miningcamp_fac  <- n_(miningcamp_flg & fac_flg)
  n_crdv_miningcamp_copd <- n_(miningcamp_flg & copd_flg)
  n_crdv_spo295_fac      <- n_(spo295_flg & fac_flg)
  n_crdv_spo295_spiro    <- n_(spo295_flg & spiro_flg)
  n_crdv_spo295_copd     <- n_(spo295_flg & copd_flg)
  n_crdv_spo295_crd      <- n_(spo295_flg & crd_dx_flg)
  n_crdv_ainorm_fac      <- n_(ainorm_flg & fac_flg)
  n_crdv_ainorm_copd     <- n_(ainorm_flg & copd_flg)
  n_crdv_notaken_fac     <- n_(notaken_flg & fac_flg)
  n_crdv_notaken_copd    <- n_(notaken_flg & copd_flg)

  # ── Sputum cohorts (AI × symptom) ──────────────────────────────────────────
  calc_sp_cat <- function(rows) {
    if (nrow(rows) == 0) return(c(scr=0L, elig=0L, coll=0L, test=0L, mbc=0L, cd=0L))
    ntf <- n_(f(rows, "tb") == TRUE)
    mbc <- n_(as.character(f(rows, "mb_positive")) == "Yes")
    c(scr  = nrow(rows),
      elig = n_(f(rows, "eligible_sputum") == "Yes"),
      coll = n_(f(rows, "sputum_collected") == TRUE),
      test = n_(f(rows, "sputum_tested") == TRUE),
      mbc  = mbc, cd = ntf - mbc)
  }
  cat_as <- calc_sp_cat(d[ ai_flag &  symp_flag, ])
  cat_ao <- calc_sp_cat(d[ ai_flag & !symp_flag, ])
  cat_so <- calc_sp_cat(d[!ai_flag &  symp_flag, ])
  cat_nn <- calc_sp_cat(d[!ai_flag & !symp_flag, ])

  # ── CXR category cascades ──────────────────────────────────────────────────
  calc_cxr_cat <- function(rows) {
    if (nrow(rows) == 0) return(c(test=0L, mbc=0L, cd=0L, tx=0L, mbc_tx=0L))
    ntf <- n_(f(rows, "tb") == TRUE)
    mbc <- n_(as.character(f(rows, "mb_positive")) == "Yes")
    nik_r <- suppressWarnings(as.numeric(f(rows, "nikshay_id")))
    nik_r <- nik_r[!is.na(nik_r) & nik_r != 0]
    tx    <- length(unique(nik_r[nik_r %in% ctx$nik_ids]))
    mbc_rows <- rows[as.character(f(rows, "mb_positive")) == "Yes", ]
    mbc_nik  <- suppressWarnings(as.numeric(f(mbc_rows, "nikshay_id")))
    mbc_nik  <- mbc_nik[!is.na(mbc_nik) & mbc_nik != 0]
    mbc_tx   <- length(unique(mbc_nik[mbc_nik %in% ctx$nik_ids]))
    c(test = n_(f(rows, "sputum_tested") == TRUE),
      mbc = mbc, cd = ntf - mbc, tx = tx, mbc_tx = mbc_tx)
  }
  sel <- function(name) { v <- f(d, name); d[v == TRUE & !is.na(v), ] }
  cxrcat_ns <- calc_cxr_cat(sel("cxr_norm_sp"))
  cxrcat_ts <- calc_cxr_cat(sel("cxr_tb_sp"))
  cxrcat_tn <- calc_cxr_cat(sel("cxr_tb_sn"))
  cxrcat_os <- calc_cxr_cat(sel("cxr_oca_sp"))
  cxrcat_on <- calc_cxr_cat(sel("cxr_oca_sn"))
  cxrcat_nn <- calc_cxr_cat(sel("cxr_norm_sn"))

  # ── CRD presumptive-variable counts ────────────────────────────────────────
  n_crdp_tobacco    <- n_(yn_(f(d, "tobacco_any")))
  n_crdp_bmi        <- n_(!is.na(bmi_v2) & bmi_v2 > 0 & bmi_v2 < 18.5)
  n_crdp_cough      <- n_(yn_(f(d, "sym_cough")))
  n_crdp_chestpain  <- n_(yn_(f(d, "sym_chest_pain")))
  n_crdp_smoking    <- n_(yn_(f(d, "smoking")))
  n_crdp_mineworker <- n_(yn_(f(d, "mine_worker")))
  n_crdp_factory    <- n_(yn_(f(d, "factory_worker")))
  n_crdp_miningcamp <- n_(miningcamp_flg)
  n_crdp_spo295     <- n_(spo295_flg)

  c(n_camps=n_camps, n_screened=n_screened, n_cxr=n_cxr,
    n_ai_tb=n_ai_tb, n_ai_oca=n_ai_oca,
    n_symptomatic=n_symptomatic, n_vuln=n_vuln,
    n_elig_sp=n_elig_sp, n_sp_coll=n_sp_coll,
    n_sp_coll_t=n_sp_coll_t, n_sp_test=n_sp_test,
    n_mbc=n_mbc, n_notified=n_notified, n_cd=n_cd, n_tx_started=n_tx_started,
    n_cxr_norm_sp=n_cxr_norm_sp, n_cxr_tb_sp=n_cxr_tb_sp,
    n_cxr_tb_sn=n_cxr_tb_sn, n_cxr_oca_sp=n_cxr_oca_sp,
    n_cxr_oca_sn=n_cxr_oca_sn, n_cxr_norm_sn=n_cxr_norm_sn,
    n_cxr_ns_test=cxrcat_ns[["test"]], n_cxr_ns_mbc=cxrcat_ns[["mbc"]], n_cxr_ns_cd=cxrcat_ns[["cd"]], n_cxr_ns_tx=cxrcat_ns[["tx"]], n_cxr_ns_mbc_tx=cxrcat_ns[["mbc_tx"]],
    n_cxr_ts_test=cxrcat_ts[["test"]], n_cxr_ts_mbc=cxrcat_ts[["mbc"]], n_cxr_ts_cd=cxrcat_ts[["cd"]], n_cxr_ts_tx=cxrcat_ts[["tx"]], n_cxr_ts_mbc_tx=cxrcat_ts[["mbc_tx"]],
    n_cxr_tn_test=cxrcat_tn[["test"]], n_cxr_tn_mbc=cxrcat_tn[["mbc"]], n_cxr_tn_cd=cxrcat_tn[["cd"]], n_cxr_tn_tx=cxrcat_tn[["tx"]], n_cxr_tn_mbc_tx=cxrcat_tn[["mbc_tx"]],
    n_cxr_os_test=cxrcat_os[["test"]], n_cxr_os_mbc=cxrcat_os[["mbc"]], n_cxr_os_cd=cxrcat_os[["cd"]], n_cxr_os_tx=cxrcat_os[["tx"]], n_cxr_os_mbc_tx=cxrcat_os[["mbc_tx"]],
    n_cxr_on_test=cxrcat_on[["test"]], n_cxr_on_mbc=cxrcat_on[["mbc"]], n_cxr_on_cd=cxrcat_on[["cd"]], n_cxr_on_tx=cxrcat_on[["tx"]], n_cxr_on_mbc_tx=cxrcat_on[["mbc_tx"]],
    n_cxr_nn_test=cxrcat_nn[["test"]], n_cxr_nn_mbc=cxrcat_nn[["mbc"]], n_cxr_nn_cd=cxrcat_nn[["cd"]], n_cxr_nn_tx=cxrcat_nn[["tx"]], n_cxr_nn_mbc_tx=cxrcat_nn[["mbc_tx"]],
    n_tb_only=n_tb_only, n_tb_crd=n_tb_crd, n_crd_only=n_crd_only, n_neither=n_neither,
    n_lh1_tb=n_lh1_tb, n_tbc_tb=n_tbc_tb, n_crd_tb=n_crd_tb, n_nne_tb=n_nne_tb,
    n_cur_tb=n_cur_tb, n_eptb=n_eptb, n_ptb_tb=n_ptb_tb, n_spo2_92=n_spo2_92,
    n_facility=n_facility, n_spiro=n_spiro, n_spiro_comp=n_spiro_comp,
    n_copd=n_copd, n_asthma=n_asthma, n_crd_dx=n_crd_dx, n_crd_pres=n_crd_pres_t,
    n_mmrc_0=n_mmrc_0, n_mmrc_1=n_mmrc_1, n_mmrc_2=n_mmrc_2,
    n_mmrc_3=n_mmrc_3, n_mmrc_4=n_mmrc_4, n_mmrc_5=n_mmrc_5, n_mmrc_pos=n_mmrc_pos,
    n_g0_fac=gc0[["fac"]], n_g0_spiro=gc0[["spiro"]], n_g0_copd=gc0[["copd"]], n_g0_asthma=gc0[["asthma"]], n_g0_crd=gc0[["crd"]], n_g0_tb=gc0[["tb"]],
    n_g1_fac=gc1[["fac"]], n_g1_spiro=gc1[["spiro"]], n_g1_copd=gc1[["copd"]], n_g1_asthma=gc1[["asthma"]], n_g1_crd=gc1[["crd"]], n_g1_tb=gc1[["tb"]],
    n_g2_fac=gc2[["fac"]], n_g2_spiro=gc2[["spiro"]], n_g2_copd=gc2[["copd"]], n_g2_asthma=gc2[["asthma"]], n_g2_crd=gc2[["crd"]], n_g2_tb=gc2[["tb"]],
    n_g3_fac=gc3[["fac"]], n_g3_spiro=gc3[["spiro"]], n_g3_copd=gc3[["copd"]], n_g3_asthma=gc3[["asthma"]], n_g3_crd=gc3[["crd"]], n_g3_tb=gc3[["tb"]],
    n_g4_fac=gc4[["fac"]], n_g4_spiro=gc4[["spiro"]], n_g4_copd=gc4[["copd"]], n_g4_asthma=gc4[["asthma"]], n_g4_crd=gc4[["crd"]], n_g4_tb=gc4[["tb"]],
    n_g5_fac=gc5[["fac"]], n_g5_spiro=gc5[["spiro"]], n_g5_copd=gc5[["copd"]], n_g5_asthma=gc5[["asthma"]], n_g5_crd=gc5[["crd"]], n_g5_tb=gc5[["tb"]],
    n_rbs=n_rbs, n_rbs_140p=n_rbs_140p, n_rbs_200p=n_rbs_200p,
    n_bp=n_bp, n_bp_140p=n_bp_140p, n_bp_160p=n_bp_160p,
    n_scd_screen=n_scd_screen, n_scd_pos=n_scd_pos,
    n_scd_sol=n_scd_sol, n_scd_sol_pos=n_scd_sol_pos,
    n_scd_poct=n_scd_poct, n_scd_poct_pos=n_scd_poct_pos,
    n_under40=n_under40, n_crd_other=n_crd_other, n_past_tb=n_past_tb,
    n_ptb_fac=n_ptb_fac, n_ptb_spiro=n_ptb_spiro, n_ptb_spiro_comp=n_ptb_spiro_comp,
    n_ptb_copd=n_ptb_copd, n_ptb_asthma=n_ptb_asthma, n_ptb_crd_other=n_ptb_crd_other,
    n_asymp_tb=n_asymp_tb, n_asymp_mbc=n_asymp_mbc,
    n_crdp_mmrc=n_mmrc_pos, n_crdp_pasttb=n_past_tb,
    n_crdp_aioca=n_ai_oca, n_crdp_aitb=n_ai_tb,
    n_crdp_tobacco=n_crdp_tobacco, n_crdp_bmi=n_crdp_bmi, n_crdp_cough=n_crdp_cough,
    n_crdp_chestpain=n_crdp_chestpain, n_crdp_smoking=n_crdp_smoking,
    n_crdp_mineworker=n_crdp_mineworker, n_crdp_factory=n_crdp_factory,
    n_crdp_miningcamp=n_crdp_miningcamp, n_crdp_spo295=n_crdp_spo295,
    n_crdv_cough_fac=n_crdv_cough_fac, n_crdv_cough_copd=n_crdv_cough_copd,
    n_crdv_aitb_fac=n_crdv_aitb_fac, n_crdv_aitb_copd=n_crdv_aitb_copd,
    n_crdv_aioca_fac=n_crdv_aioca_fac, n_crdv_aioca_copd=n_crdv_aioca_copd,
    n_crdv_tobacco_fac=n_crdv_tobacco_fac, n_crdv_tobacco_copd=n_crdv_tobacco_copd,
    n_crdv_bmi_fac=n_crdv_bmi_fac, n_crdv_bmi_copd=n_crdv_bmi_copd,
    n_crdv_rbs_fac=n_crdv_rbs_fac, n_crdv_rbs_copd=n_crdv_rbs_copd,
    n_crdv_chest_fac=n_crdv_chest_fac, n_crdv_chest_copd=n_crdv_chest_copd,
    n_crdv_smoking_fac=n_crdv_smoking_fac, n_crdv_smoking_copd=n_crdv_smoking_copd,
    n_crdv_mine_fac=n_crdv_mine_fac, n_crdv_mine_copd=n_crdv_mine_copd,
    n_crdv_factory_fac=n_crdv_factory_fac, n_crdv_factory_copd=n_crdv_factory_copd,
    n_crdv_miningcamp_fac=n_crdv_miningcamp_fac, n_crdv_miningcamp_copd=n_crdv_miningcamp_copd,
    n_crdv_spo295_fac=n_crdv_spo295_fac, n_crdv_spo295_spiro=n_crdv_spo295_spiro,
    n_crdv_spo295_copd=n_crdv_spo295_copd, n_crdv_spo295_crd=n_crdv_spo295_crd,
    n_crdv_ainorm_fac=n_crdv_ainorm_fac, n_crdv_ainorm_copd=n_crdv_ainorm_copd,
    n_crdv_notaken_fac=n_crdv_notaken_fac, n_crdv_notaken_copd=n_crdv_notaken_copd,
    n_scr_as=cat_as[["scr"]], n_elig_as=cat_as[["elig"]], n_coll_as=cat_as[["coll"]], n_test_as=cat_as[["test"]], n_mbc_as=cat_as[["mbc"]], n_cd_as=cat_as[["cd"]],
    n_scr_ao=cat_ao[["scr"]], n_elig_ao=cat_ao[["elig"]], n_coll_ao=cat_ao[["coll"]], n_test_ao=cat_ao[["test"]], n_mbc_ao=cat_ao[["mbc"]], n_cd_ao=cat_ao[["cd"]],
    n_scr_so=cat_so[["scr"]], n_elig_so=cat_so[["elig"]], n_coll_so=cat_so[["coll"]], n_test_so=cat_so[["test"]], n_mbc_so=cat_so[["mbc"]], n_cd_so=cat_so[["cd"]],
    n_scr_nn=cat_nn[["scr"]], n_elig_nn=cat_nn[["elig"]], n_coll_nn=cat_nn[["coll"]], n_test_nn=cat_nn[["test"]], n_mbc_nn=cat_nn[["mbc"]], n_cd_nn=cat_nn[["cd"]],
    n_lh1_tot=lg1[["tot"]], n_lh1_fac=lg1[["fac"]], n_lh1_spiro=lg1[["spiro"]], n_lh1_cpd=lg1[["cpd"]], n_lh1_ast=lg1[["ast"]], n_lh1_oth=lg1[["oth"]],
    n_lh2_tot=lg2[["tot"]], n_lh2_fac=lg2[["fac"]], n_lh2_spiro=lg2[["spiro"]], n_lh2_cpd=lg2[["cpd"]], n_lh2_ast=lg2[["ast"]], n_lh2_oth=lg2[["oth"]],
    n_lh3_tot=lg3[["tot"]], n_lh3_fac=lg3[["fac"]], n_lh3_spiro=lg3[["spiro"]], n_lh3_cpd=lg3[["cpd"]], n_lh3_ast=lg3[["ast"]], n_lh3_oth=lg3[["oth"]],
    n_lh4_tot=lg4[["tot"]], n_lh4_fac=lg4[["fac"]], n_lh4_spiro=lg4[["spiro"]], n_lh4_cpd=lg4[["cpd"]], n_lh4_ast=lg4[["ast"]], n_lh4_oth=lg4[["oth"]],
    n_lh5_tot=lg5[["tot"]], n_lh5_fac=lg5[["fac"]], n_lh5_spiro=lg5[["spiro"]], n_lh5_cpd=lg5[["cpd"]], n_lh5_ast=lg5[["ast"]], n_lh5_oth=lg5[["oth"]],
    n_lh6_tot=lg6[["tot"]], n_lh6_fac=lg6[["fac"]], n_lh6_spiro=lg6[["spiro"]], n_lh6_cpd=lg6[["cpd"]], n_lh6_ast=lg6[["ast"]], n_lh6_oth=lg6[["oth"]],
    n_lh7_tot=lg7[["tot"]], n_lh7_fac=lg7[["fac"]], n_lh7_spiro=lg7[["spiro"]], n_lh7_cpd=lg7[["cpd"]], n_lh7_ast=lg7[["ast"]], n_lh7_oth=lg7[["oth"]],
    n_lh8_tot=lg8[["tot"]], n_lh8_fac=lg8[["fac"]], n_lh8_spiro=lg8[["spiro"]], n_lh8_cpd=lg8[["cpd"]], n_lh8_ast=lg8[["ast"]], n_lh8_oth=lg8[["oth"]],
    n_lh1n_tot=lg1n[["tot"]], n_lh1n_fac=lg1n[["fac"]], n_lh1n_spiro=lg1n[["spiro"]], n_lh1n_cpd=lg1n[["cpd"]], n_lh1n_ast=lg1n[["ast"]], n_lh1n_oth=lg1n[["oth"]],
    n_lh2n_tot=lg2n[["tot"]], n_lh2n_fac=lg2n[["fac"]], n_lh2n_spiro=lg2n[["spiro"]], n_lh2n_cpd=lg2n[["cpd"]], n_lh2n_ast=lg2n[["ast"]], n_lh2n_oth=lg2n[["oth"]],
    n_lh3n_tot=lg3n[["tot"]], n_lh3n_fac=lg3n[["fac"]], n_lh3n_spiro=lg3n[["spiro"]], n_lh3n_cpd=lg3n[["cpd"]], n_lh3n_ast=lg3n[["ast"]], n_lh3n_oth=lg3n[["oth"]],
    n_lh4n_tot=lg4n[["tot"]], n_lh4n_fac=lg4n[["fac"]], n_lh4n_spiro=lg4n[["spiro"]], n_lh4n_cpd=lg4n[["cpd"]], n_lh4n_ast=lg4n[["ast"]], n_lh4n_oth=lg4n[["oth"]],
    n_lh5n_tot=lg5n[["tot"]], n_lh5n_fac=lg5n[["fac"]], n_lh5n_spiro=lg5n[["spiro"]], n_lh5n_cpd=lg5n[["cpd"]], n_lh5n_ast=lg5n[["ast"]], n_lh5n_oth=lg5n[["oth"]],
    n_lh6n_tot=lg6n[["tot"]], n_lh6n_fac=lg6n[["fac"]], n_lh6n_spiro=lg6n[["spiro"]], n_lh6n_cpd=lg6n[["cpd"]], n_lh6n_ast=lg6n[["ast"]], n_lh6n_oth=lg6n[["oth"]],
    n_lh7n_tot=lg7n[["tot"]], n_lh7n_fac=lg7n[["fac"]], n_lh7n_spiro=lg7n[["spiro"]], n_lh7n_cpd=lg7n[["cpd"]], n_lh7n_ast=lg7n[["ast"]], n_lh7n_oth=lg7n[["oth"]],
    n_lh8n_tot=lg8n[["tot"]], n_lh8n_fac=lg8n[["fac"]], n_lh8n_spiro=lg8n[["spiro"]], n_lh8n_cpd=lg8n[["cpd"]], n_lh8n_ast=lg8n[["ast"]], n_lh8n_oth=lg8n[["oth"]])
}

# ─────────────────────────────────────────────────────────────────────────────
# Slicing + the range-dedup fix
# ─────────────────────────────────────────────────────────────────────────────

#' Filter the Logic sheet by month range and gender.
#' `from`/`to` are inclusive "YYYY-MM" strings; gender is "all" | "F" | "M".
slice_logic <- function(L, from = NULL, to = NULL, gender = "all") {
  keep <- rep(TRUE, nrow(L))
  if (!is.null(from) && nzchar(from)) keep <- keep & !is.na(L$ym) & L$ym >= from
  if (!is.null(to)   && nzchar(to))   keep <- keep & !is.na(L$ym) & L$ym <= to

  if (!is.null(gender) && gender %in% c("F", "M")) {
    want <- if (gender == "F") "Female" else "Male"
    keep <- keep & !is.na(L$gender) & L$gender == want
  }
  L[keep, ]
}

#' Metrics for a date range, computed over the whole range at once.
#'
#' This is the corrected replacement for build_v3.py's tot(key, idxs), which
#' summed monthly buckets. Returns both:
#'   total   — deduped across the entire range (correct)
#'   monthly — per-month series, for trend charts only
#'   sum_of_monthly + overcount — the size of the legacy error, so the UI can
#'                                show how much double-counting was removed
metrics_for_range <- function(bundle, from = NULL, to = NULL, gender = "all") {
  ctx <- make_ctx(bundle)
  L   <- bundle$ris$logic

  rng   <- slice_logic(L, from, to, gender)
  total <- calc_logic(rng, ctx)

  months <- sort(unique(rng$ym[!is.na(rng$ym)]))
  monthly <- lapply(months, function(m) calc_logic(rng[rng$ym == m, ], ctx))
  names(monthly) <- months

  # Quantify the legacy overcount for unique-beneficiary metrics
  sum_monthly <- if (length(monthly) == 0) {
    setNames(rep(0, length(total)), names(total))
  } else {
    Reduce(`+`, monthly)
  }
  overcount <- sum_monthly - total

  list(
    total          = as.list(total),
    monthly        = lapply(monthly, as.list),
    # I() keeps this a JSON array even when the range covers a single month —
    # the unboxing serializer would otherwise emit a bare string.
    months         = I(months),
    sum_of_monthly = as.list(sum_monthly),
    overcount      = as.list(overcount[overcount != 0])
  )
}

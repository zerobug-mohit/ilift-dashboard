# ─────────────────────────────────────────────────────────────────────────────
# metrics_nns.R — Number Needed to Screen cohorts
# Ported from calc_nns.R:19-111, with named columns and range-aware totals.
#
# NNS = cohort size / outcomes found. Because the numerator is a count of
# unique beneficiaries, the legacy sum-of-months approach inflated it for any
# multi-month selection — the same defect described in metrics_core.R.
# ─────────────────────────────────────────────────────────────────────────────

#' Per-cohort outcome counts. Ported from calc_nns.R:19-33.
calc_cohort <- function(rows, map) {
  f <- function(df, name) fld(df, map, name)
  if (nrow(rows) == 0) {
    return(list(n = 0, sp_coll = 0, sp_test = 0, tb = 0, mbc = 0,
                spiro = 0, copd = 0, asthma = 0, crd_dx = 0))
  }
  d <- rows[!duplicated(as.character(f(rows, "beneficiary_id"))), ]
  list(
    n       = nrow(d),
    sp_coll = sum(f(d, "sputum_collected") == TRUE, na.rm = TRUE),
    sp_test = sum(f(d, "sputum_tested")    == TRUE, na.rm = TRUE),
    tb      = sum(f(d, "tb")               == TRUE, na.rm = TRUE),
    mbc     = sum(as.character(f(d, "mb_positive")) == "Yes", na.rm = TRUE),
    spiro   = sum(f(d, "spiro_done")       == TRUE, na.rm = TRUE),
    copd    = sum(as.character(f(d, "crd_result")) == "COPD",   na.rm = TRUE),
    asthma  = sum(as.character(f(d, "crd_result")) == "Asthma", na.rm = TRUE),
    crd_dx  = sum(f(d, "crd_diagnosed")    == TRUE, na.rm = TRUE)
  )
}

#' Cohort definitions, ported from calc_nns.R:42-100.
#' Each predicate receives (data, map) and returns a logical vector.
nns_cohort_defs <- function() {
  g   <- function(d, map, name) fld(d, map, name)
  num <- function(d, map, name) suppressWarnings(as.numeric(fld(d, map, name)))
  chr <- function(d, map, name) as.character(fld(d, map, name))

  ai_tb <- function(d, m) { v <- g(d, m, "genki_result"); !is.na(v) & as.character(v) == "TB Related Abnormalities" }
  symp  <- function(d, m) { v <- g(d, m, "symptomatic");  !is.na(v) & v == TRUE }
  vuln  <- function(d, m) { v <- g(d, m, "vulnerable");   !is.na(v) & v == TRUE }
  age   <- function(d, m) num(d, m, "age")
  mmrc  <- function(d, m) chr(d, m, "mmrc_scale")

  fem <- function(d, m) chr(d, m, "gender") == "Female"
  mal <- function(d, m) chr(d, m, "gender") == "Male"

  list(
    list(theme="AI Result",    label="AI-TB Sugg + Symptomatic", f=function(d,m) ai_tb(d,m) &  symp(d,m)),
    list(theme="AI Result",    label="AI-TB Sugg only",          f=function(d,m) ai_tb(d,m) & !symp(d,m)),
    list(theme="AI Result",    label="Symptomatic only",         f=function(d,m) !ai_tb(d,m) &  symp(d,m)),
    list(theme="AI Result",    label="Neither",                  f=function(d,m) !ai_tb(d,m) & !symp(d,m)),

    list(theme="Symptoms",     label="Cough",                    f=function(d,m) yn_(g(d,m,"sym_cough"))),
    list(theme="Symptoms",     label="Chest Pain",               f=function(d,m) yn_(g(d,m,"sym_chest_pain"))),
    list(theme="Symptoms",     label="Night Sweats",             f=function(d,m) yn_(g(d,m,"sym_night_sweats"))),
    list(theme="Symptoms",     label="Fever",                    f=function(d,m) yn_(g(d,m,"sym_fever"))),
    list(theme="Symptoms",     label="Loss of Weight",           f=function(d,m) yn_(g(d,m,"sym_weight_loss"))),
    list(theme="Symptoms",     label="Blood in Sputum",          f=function(d,m) yn_(g(d,m,"sym_blood_sputum"))),

    list(theme="Area",         label="Tribal area",              f=function(d,m) chr(d,m,"area_classification") == "Tribal"),
    list(theme="Area",         label="Rural area",               f=function(d,m) chr(d,m,"area_classification") == "Rural"),
    list(theme="Area",         label="Urban area",               f=function(d,m) chr(d,m,"area_classification") == "Urban"),
    list(theme="Area",         label="Mining area",              f=function(d,m) chr(d,m,"camp_area_type") == "Mining area"),

    list(theme="Social",       label="Migrant",                  f=function(d,m) yn_(g(d,m,"migrant"))),
    list(theme="Social",       label="Factory/Construction",     f=function(d,m) yn_(g(d,m,"factory_worker"))),
    list(theme="Social",       label="Miner",                    f=function(d,m) yn_(g(d,m,"mine_worker"))),
    list(theme="Social",       label="Healthcare worker",        f=function(d,m) yn_(g(d,m,"healthcare_worker"))),

    list(theme="Female by age",label="Female <25",               f=function(d,m) fem(d,m) & !is.na(age(d,m)) & age(d,m) < 25),
    list(theme="Female by age",label="Female 25-45",             f=function(d,m) fem(d,m) & !is.na(age(d,m)) & age(d,m) >= 25 & age(d,m) <= 45),
    list(theme="Female by age",label="Female 46-59",             f=function(d,m) fem(d,m) & !is.na(age(d,m)) & age(d,m) >= 46 & age(d,m) <= 59),
    list(theme="Female by age",label="Female 60+",               f=function(d,m) fem(d,m) & !is.na(age(d,m)) & age(d,m) >= 60),
    list(theme="Female by age",label="Female all ages",          f=function(d,m) fem(d,m)),

    list(theme="Male by age",  label="Male <25",                 f=function(d,m) mal(d,m) & !is.na(age(d,m)) & age(d,m) < 25),
    list(theme="Male by age",  label="Male 25-45",               f=function(d,m) mal(d,m) & !is.na(age(d,m)) & age(d,m) >= 25 & age(d,m) <= 45),
    list(theme="Male by age",  label="Male 46-59",               f=function(d,m) mal(d,m) & !is.na(age(d,m)) & age(d,m) >= 46 & age(d,m) <= 59),
    list(theme="Male by age",  label="Male 60+",                 f=function(d,m) mal(d,m) & !is.na(age(d,m)) & age(d,m) >= 60),
    list(theme="Male by age",  label="Male all ages",            f=function(d,m) mal(d,m)),

    list(theme="Profile",      label="Symptomatic only",         f=function(d,m)  symp(d,m) & !vuln(d,m)),
    list(theme="Profile",      label="Vulnerable flag only",     f=function(d,m) !symp(d,m) &  vuln(d,m)),
    list(theme="Profile",      label="Symptomatic + Vulnerable", f=function(d,m)  symp(d,m) &  vuln(d,m)),
    list(theme="Profile",      label="Neither",                  f=function(d,m) !symp(d,m) & !vuln(d,m)),

    list(theme="Tobacco",      label="Smokeless Tobacco",        f=function(d,m) yn_(g(d,m,"tobacco_any"))),
    list(theme="Tobacco",      label="Smoking",                  f=function(d,m) yn_(g(d,m,"smoking"))),
    list(theme="Tobacco",      label="No tobacco or smoking",    f=function(d,m) !yn_(g(d,m,"tobacco_any")) & !yn_(g(d,m,"smoking"))),

    list(theme="Past TB",      label="Past TB",                  f=function(d,m)  yn_(g(d,m,"past_tb"))),
    list(theme="Past TB",      label="No Past TB",               f=function(d,m) !yn_(g(d,m,"past_tb"))),

    list(theme="HH Contact",   label="HH Contact of TB patient", f=function(d,m)  yn_(g(d,m,"hh_contact_tb"))),
    list(theme="HH Contact",   label="Not a contact",            f=function(d,m) !yn_(g(d,m,"hh_contact_tb"))),

    list(theme="SpO2",         label="SpO2 94-100%",             f=function(d,m){s<-num(d,m,"spo2"); !is.na(s)&s>=94&s<=100}),
    list(theme="SpO2",         label="SpO2 90 to <94%",          f=function(d,m){s<-num(d,m,"spo2"); !is.na(s)&s>=90&s<94}),
    list(theme="SpO2",         label="SpO2 <90%",                f=function(d,m){s<-num(d,m,"spo2"); !is.na(s)&s>0&s<90}),

    list(theme="BMI",          label="BMI <18.5",                f=function(d,m){b<-num(d,m,"bmi"); !is.na(b)&b>0&b<18.5}),
    list(theme="BMI",          label="BMI 18.5-25.0",            f=function(d,m){b<-num(d,m,"bmi"); !is.na(b)&b>=18.5&b<=25.0}),
    list(theme="BMI",          label="BMI 25.0-40",              f=function(d,m){b<-num(d,m,"bmi"); !is.na(b)&b>25.0&b<=40}),
    list(theme="BMI",          label="BMI >=40",                 f=function(d,m){b<-num(d,m,"bmi"); !is.na(b)&b>40}),

    list(theme="Alcohol",      label="Alcohol: Yes",             f=function(d,m)  yn_(g(d,m,"alcohol"))),
    list(theme="Alcohol",      label="Alcohol: No",              f=function(d,m) !yn_(g(d,m,"alcohol"))),

    list(theme="RBS",          label="RBS 70-140",               f=function(d,m){r<-num(d,m,"blood_sugar"); !is.na(r)&r>=70&r<=140}),
    list(theme="RBS",          label="RBS 140-200",              f=function(d,m){r<-num(d,m,"blood_sugar"); !is.na(r)&r>140&r<=200}),
    list(theme="RBS",          label="RBS >=200",                f=function(d,m){r<-num(d,m,"blood_sugar"); !is.na(r)&r>200}),

    list(theme="mMRC",         label="Grade 0",                  f=function(d,m) !grepl("^Grade [1-5]:|^grade_5", mmrc(d,m))),
    list(theme="mMRC",         label="Grade 1",                  f=function(d,m)  grepl("^Grade 1:", mmrc(d,m))),
    list(theme="mMRC",         label="Grade 2",                  f=function(d,m)  grepl("^Grade 2:", mmrc(d,m))),
    list(theme="mMRC",         label="Grade 3",                  f=function(d,m)  grepl("^Grade 3:", mmrc(d,m))),
    list(theme="mMRC",         label="Grade 4",                  f=function(d,m)  grepl("^Grade 4:", mmrc(d,m))),
    list(theme="mMRC",         label="Grade 5",                  f=function(d,m)  mmrc(d,m) == "grade_5")
  )
}

#' NNS cohorts for a date range. Totals are deduped across the whole range.
nns_for_range <- function(bundle, from = NULL, to = NULL, gender = "all") {
  map <- bundle$ris$map
  rng <- slice_logic(bundle$ris$logic, from, to, gender)
  months <- sort(unique(rng$ym[!is.na(rng$ym)]))
  defs <- nns_cohort_defs()

  cohorts <- lapply(defs, function(cd) {
    keep <- cd$f(rng, map)
    keep[is.na(keep)] <- FALSE
    sub  <- rng[keep, ]

    monthly <- lapply(months, function(mo) calc_cohort(sub[sub$ym == mo, ], map))
    names(monthly) <- months

    list(theme = cd$theme, label = cd$label,
         total = calc_cohort(sub, map), monthly = monthly)
  })

  list(months = I(months), cohorts = cohorts)
}

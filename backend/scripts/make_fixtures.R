# ─────────────────────────────────────────────────────────────────────────────
# make_fixtures.R — synthetic data matching the documented RIS/CRD/Nikshay
# schema, so the stack runs end-to-end before real exports are available.
#
#   Rscript backend/scripts/make_fixtures.R
#
# Deliberately includes beneficiaries screened in more than one month. That is
# what makes the legacy sum-of-months overcount visible and testable — see
# tests/testthat/test-range-dedup.R.
#
# THIS IS NOT REAL DATA. Numbers produced from it are meaningless clinically.
# ─────────────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(writexl)
})

# Seed and size are overridable so a second, different dataset can be generated
# to prove the dashboard picks up new data without a rebuild:
#   ILIFT_FIXTURE_SEED=99 Rscript backend/scripts/make_fixtures.R
set.seed(as.integer(Sys.getenv("ILIFT_FIXTURE_SEED", unset = "42")))

script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", args, value = TRUE)
  if (length(m)) dirname(normalizePath(sub("^--file=", "", m[1]))) else getwd()
}

backend_dir <- normalizePath(file.path(script_dir(), ".."), mustWork = TRUE)
incoming    <- file.path(backend_dir, "data", "incoming")
dir.create(file.path(incoming, "nikshay"), recursive = TRUE, showWarnings = FALSE)

N_COLS   <- 180
MONTHS   <- c("2025-08","2025-09","2025-10","2025-11","2025-12",
              "2026-01","2026-02","2026-03","2026-04","2026-05","2026-06")
N_UNIQUE <- as.integer(Sys.getenv("ILIFT_FIXTURE_N", unset = "4000"))
N_REPEAT <- 350          # beneficiaries who attend a second camp in a later month

# Column headers: real names at the schema positions, filler elsewhere.
headers <- paste0("col_", seq_len(N_COLS))
named <- c(
  "1"="Camp ID", "2"="Camp Creation Date", "6"="Camp District",
  "11"="Camp Area Type", "14"="Area Classification",
  "50"="Beneficiary ID", "52"="Age", "54"="Gender", "56"="Beneficiary Nikshay ID",
  "60"="BMI", "63"="Blood Sugar (RBS)", "64"="SpO2", "66"="Systolic BP",
  "68"="Sickle Cell Result",
  "71"="Cough", "72"="Chest Pain", "73"="Night Sweats", "74"="Fever",
  "75"="Loss of Weight", "76"="Blood in Sputum",
  "80"="mMRC Scale", "83"="Tobacco Use", "84"="Smoking", "85"="Alcohol",
  "86"="HH Contact of TB Patient", "87"="Past TB", "88"="Currently on TB Treatment",
  "94"="Migrant", "95"="Factory Worker", "96"="Mine Worker", "97"="Healthcare Worker",
  "101"="X-ray Taken", "106"="Genki Edge Result", "137"="EPTB",
  "142"="Chronic Respiratory Diseases",
  "155"="MB+", "156"="TB presumptive", "157"="Sputum Collected",
  "158"="Sputum Tested", "160"="CRD presumptive", "161"="TB",
  "162"="Symptomatic", "163"="Facility Visited", "164"="Spiro done",
  "165"="CRD diagnosed",
  "166"="CXR normal S+", "167"="CXR TB S+", "168"="CXR TB S-",
  "169"="CXR OCA S+", "170"="CXR OCA S-", "171"="CXR normal S-",
  "174"="Vulnerable", "177"="Eligible for Sputum",
  "178"="Latitude", "179"="Longitude"
)
for (k in names(named)) headers[as.integer(k)] <- named[[k]]

pick <- function(x, n, prob = NULL) sample(x, n, replace = TRUE, prob = prob)

# ── Camps: each camp runs on one day in one district ─────────────────────────
# Beneficiaries are assigned to a camp, so camp-level aggregates (screenings
# per camp, weekly footfall) come out in a realistic range.
N_CAMPS    <- 90
camp_id    <- sprintf("CAMP%03d", seq_len(N_CAMPS))
camp_mon   <- pick(MONTHS, N_CAMPS)
camp_date  <- as.Date(paste0(camp_mon, "-", sprintf("%02d", pick(1:28, N_CAMPS))))
camp_dist  <- pick(c("Korba","Raigarh","Bastar","Surguja","Jashpur"), N_CAMPS)
camp_area  <- pick(c("Mining area","Non-mining area"), N_CAMPS, prob = c(0.22, 0.78))
camp_class <- pick(c("Tribal","Rural","Urban"), N_CAMPS, prob = c(0.55, 0.35, 0.10))
camp_lat   <- round(runif(N_CAMPS, 21.0, 23.5), 5)
camp_lon   <- round(runif(N_CAMPS, 81.0, 84.0), 5)

# ── Beneficiary-level attributes (stable across encounters) ──────────────────
# Gender and age must not vary between a beneficiary's visits, otherwise the
# gender-filtered totals would not sum to the overall total.
bids     <- sprintf("IL%05d", seq_len(N_UNIQUE))
b_gender <- pick(c("Female","Male"), N_UNIQUE, prob = c(0.53, 0.47))
b_age    <- pick(18:80, N_UNIQUE)
b_camp   <- pick(seq_len(N_CAMPS), N_UNIQUE)

# Repeat attenders: same beneficiary, a camp held in a later month
rep_idx <- sample(seq_len(N_UNIQUE), N_REPEAT)
rep_camp <- sapply(rep_idx, function(i) {
  later <- which(camp_date > camp_date[b_camp[i]])
  if (length(later) == 0) b_camp[i] else sample(later, 1)
})

# Row-level (encounter) index into the beneficiary roster
row_ben  <- c(seq_len(N_UNIQUE), rep_idx)
row_camp <- c(b_camp, rep_camp)
N <- length(row_ben)

all_bid <- bids[row_ben]
dates   <- camp_date[row_camp]

genki <- pick(c("Normal", "TB Related Abnormalities", "Other Chest Related Abnormalities",
                "Beneficiary ID not present"), N, prob = c(0.68, 0.16, 0.13, 0.03))
symptomatic <- pick(c(TRUE, FALSE), N, prob = c(0.22, 0.78))
ai_tb <- genki == "TB Related Abnormalities"

elig    <- ifelse(ai_tb | symptomatic, pick(c("Yes","No"), N, prob=c(0.85,0.15)), "No")
sp_coll <- elig == "Yes" & pick(c(TRUE,FALSE), N, prob=c(0.70,0.30))
sp_test <- sp_coll       & pick(c(TRUE,FALSE), N, prob=c(0.82,0.18))
mbp     <- ifelse(sp_test & pick(c(TRUE,FALSE), N, prob=c(0.022,0.978)), "Yes", "No")
tb_flag <- mbp == "Yes" | (sp_test & pick(c(TRUE,FALSE), N, prob=c(0.02,0.98)))

mmrc <- pick(c("Grade 0", "Grade 1: Breathless on strenuous exercise",
               "Grade 2: Short of breath hurrying", "Grade 3: Walks slower",
               "Grade 4: Stops for breath", "grade_5"),
             N, prob = c(0.72, 0.12, 0.08, 0.04, 0.03, 0.01))
mmrc_pos <- grepl("^Grade [1-4]:", mmrc) | mmrc == "grade_5"

crd_pres <- genki == "Other Chest Related Abnormalities" | mmrc_pos
facility <- crd_pres & pick(c(TRUE,FALSE), N, prob=c(0.42,0.58))
spiro    <- facility & pick(c(TRUE,FALSE), N, prob=c(0.80,0.20))
crd_res  <- ifelse(spiro, pick(c("COPD","Asthma","Others","Normal"), N,
                               prob=c(0.26,0.12,0.07,0.55)), NA_character_)
crd_dx   <- !is.na(crd_res) & crd_res %in% c("COPD","Asthma","Others")

nikshay_id <- ifelse(tb_flag, sample(700000:799999, N, replace = TRUE), 0)

L <- as.data.frame(matrix("", nrow = N, ncol = N_COLS), stringsAsFactors = FALSE)
colnames(L) <- headers

L[[1]]   <- camp_id[row_camp]
L[[2]]   <- dates
L[[6]]   <- camp_dist[row_camp]
L[[11]]  <- camp_area[row_camp]
L[[14]]  <- camp_class[row_camp]
L[[50]]  <- all_bid
L[[52]]  <- b_age[row_ben]          # stable per beneficiary
L[[54]]  <- b_gender[row_ben]       # stable per beneficiary
L[[56]]  <- nikshay_id
L[[60]]  <- round(runif(N, 14, 34), 1)
L[[63]]  <- pick(c(0, 70:260), N)
L[[64]]  <- pick(c(0, 86:100), N, prob = c(0.05, rep(0.95/15, 15)))
L[[66]]  <- pick(c(0, 100:180), N)
L[[68]]  <- pick(c("POCT - Normal","POCT - Sickle cell disease","POCT - Sickle cell trait",
                   "Solubility - screened -ve","Solubility - screened +ve",""), N,
                 prob = c(0.42,0.02,0.06,0.28,0.04,0.18))
for (i in c(71,72,73,74,75,76,83,84,85,86,87,88,94,95,96,97,137)) {
  L[[i]] <- pick(c("Yes","No"), N, prob = c(0.15, 0.85))
}
L[[80]]  <- mmrc
L[[101]] <- pick(c("Yes","No"), N, prob=c(0.91,0.09))
L[[106]] <- genki
L[[142]] <- ifelse(is.na(crd_res), "", crd_res)
L[[155]] <- mbp
L[[156]] <- ai_tb | symptomatic
L[[157]] <- sp_coll
L[[158]] <- sp_test
L[[160]] <- crd_pres
L[[161]] <- tb_flag
L[[162]] <- symptomatic
L[[163]] <- facility
L[[164]] <- spiro
L[[165]] <- crd_dx
L[[166]] <- genki %in% c("Normal","Beneficiary ID not present") &  symptomatic
L[[167]] <- ai_tb &  symptomatic
L[[168]] <- ai_tb & !symptomatic
L[[169]] <- genki == "Other Chest Related Abnormalities" &  symptomatic
L[[170]] <- genki == "Other Chest Related Abnormalities" & !symptomatic
L[[171]] <- genki %in% c("Normal","Beneficiary ID not present") & !symptomatic
L[[174]] <- pick(c(TRUE,FALSE), N, prob=c(0.30,0.70))
L[[177]] <- elig
L[[178]] <- camp_lat[row_camp]   # Latitude  (named header, per camp)
L[[179]] <- camp_lon[row_camp]   # Longitude (named header, per camp)

# RAW sheet — needs col 169 = Expert Referral (calc_v2.R:427)
RAW <- as.data.frame(matrix("", nrow = N, ncol = N_COLS), stringsAsFactors = FALSE)
colnames(RAW) <- headers
RAW[[2]]   <- dates
RAW[[50]]  <- all_bid
RAW[[169]] <- pick(c("Immediate referral","Deferred referral","No","-"), N,
                   prob = c(0.05, 0.10, 0.55, 0.30))

write_xlsx(list(`Logic sheet` = L, `RAW DATA (paste here)` = RAW),
           file.path(incoming, "ris_fixture.xlsx"))

# ── CRD MIS ──────────────────────────────────────────────────────────────────
crd_bids <- sample(bids, 900)
CRD <- data.frame(
  `Beneficiary ID...1`        = c(crd_bids, rep("OPD", 220)),
  `Date of facility visit`    = c(sample(dates, 900, replace = TRUE),
                                  sample(dates, 220, replace = TRUE)),
  `Spirometry test status`    = pick(c("Test completed","Test pending","LTFU"), 1120,
                                     prob = c(0.62, 0.24, 0.14)),
  `Diagnosis and Action by MO`= pick(c("COPD","Asthma","Other","No CRD"), 1120,
                                     prob = c(0.22, 0.11, 0.09, 0.58)),
  check.names = FALSE, stringsAsFactors = FALSE
)
write_xlsx(list(`New Master Sheet` = CRD), file.path(incoming, "crd_mis_fixture.xlsx"))

# ── Nikshay quarterly files ──────────────────────────────────────────────────
tb_nik <- unique(nikshay_id[nikshay_id != 0])
started <- sample(tb_nik, round(length(tb_nik) * 0.88))
chunks  <- split(started, cut(seq_along(started), 4, labels = FALSE))
for (i in seq_along(chunks)) {
  write_xlsx(
    list(Sheet1 = data.frame(Episode_ID = chunks[[i]],
                             Notification_Date = sample(dates, length(chunks[[i]]), replace = TRUE),
                             stringsAsFactors = FALSE)),
    file.path(incoming, "nikshay", sprintf("2%d.xlsx", 5000 + i))
  )
}

# Marker so the test suite can tell synthetic data from a real export without
# guessing from filenames. Parity assertions against the Excel reference are
# meaningless on fixtures, and a filename heuristic is too easy to defeat —
# any uploaded file not containing "fixture" would silently enable them.
writeLines(
  c("Synthetic data generated by backend/scripts/make_fixtures.R.",
    "Delete this file when real programme exports are in place.",
    paste("seed:", Sys.getenv("ILIFT_FIXTURE_SEED", "42")),
    paste("generated:", format(Sys.time(), "%Y-%m-%dT%H:%M:%S"))),
  file.path(incoming, ".fixtures")
)

cat("Fixtures written to", incoming, "\n")
cat("  rows:", N, " unique beneficiaries:", length(unique(all_bid)),
    " repeat attenders:", N_REPEAT, "\n")
cat("  NOTE: synthetic data — clinically meaningless.\n")

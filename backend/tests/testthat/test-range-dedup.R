# ─────────────────────────────────────────────────────────────────────────────
# The range-dedup fix — the defect this rebuild exists to correct.
#
# build_v3.py:703 computed any multi-month total as the sum of monthly buckets.
# calc_logic() dedups beneficiaries within whatever slice it receives
# (calc_v2.R:73), so a beneficiary screened in two months was counted twice.
#
# These tests run against fixtures as well as real data — the invariants hold
# for any dataset containing repeat attenders.
# ─────────────────────────────────────────────────────────────────────────────

UNIQUE_BENEFICIARY_METRICS <- c(
  "n_screened", "n_cxr", "n_ai_tb", "n_ai_oca", "n_symptomatic",
  "n_elig_sp", "n_sp_coll", "n_sp_test", "n_facility", "n_spiro",
  "n_past_tb", "n_vuln"
)

test_that("range totals never exceed the legacy sum-of-months", {
  b <- test_bundle()
  r <- metrics_for_range(b)

  for (m in UNIQUE_BENEFICIARY_METRICS) {
    expect_lte(
      as.numeric(r$total[[m]]),
      as.numeric(r$sum_of_monthly[[m]]),
      label = sprintf("%s range total (%s)", m, r$total[[m]])
    )
  }
})

test_that("screened equals the count of distinct beneficiaries in the range", {
  b <- test_bundle()
  L <- b$ris$logic
  expected <- length(unique(as.character(fld(L, b$ris$map, "beneficiary_id"))))
  expect_equal(as.integer(metrics_for_range(b)$total$n_screened), expected)
})

test_that("repeat attenders are counted once across a multi-month range", {
  b <- test_bundle()
  L <- b$ris$logic
  bid <- as.character(fld(L, b$ris$map, "beneficiary_id"))

  # Beneficiaries appearing in more than one distinct month
  months_per_bid <- tapply(L$ym, bid, function(x) length(unique(x)))
  n_repeat <- sum(months_per_bid > 1)
  skip_if(n_repeat == 0, "dataset has no cross-month repeat attenders")

  r <- metrics_for_range(b)
  overcount <- as.numeric(r$sum_of_monthly$n_screened) - as.numeric(r$total$n_screened)

  # Every cross-month repeat contributes exactly one extra to the legacy sum
  # for each additional month it appears in.
  expected_overcount <- sum(months_per_bid[months_per_bid > 1] - 1)
  expect_equal(overcount, as.numeric(expected_overcount))
})

test_that("sub-range totals are consistent with the full range", {
  b <- test_bundle()
  months <- b$months
  skip_if(length(months) < 3, "need at least 3 months")

  full <- metrics_for_range(b)$total$n_screened
  head_r <- metrics_for_range(b, months[1], months[length(months) - 1])$total$n_screened
  tail_r <- metrics_for_range(b, months[2], months[length(months)])$total$n_screened

  # Each sub-range is a subset of the full range
  expect_lte(as.numeric(head_r), as.numeric(full))
  expect_lte(as.numeric(tail_r), as.numeric(full))

  # A single month computed directly equals that month's entry in the series
  one <- metrics_for_range(b, months[2], months[2])
  expect_equal(as.numeric(one$total$n_screened),
               as.numeric(one$monthly[[months[2]]][["n_screened"]]))
})

test_that("gender subsets partition the whole population", {
  b <- test_bundle()
  all_n <- as.numeric(metrics_for_range(b, gender = "all")$total$n_screened)
  f_n   <- as.numeric(metrics_for_range(b, gender = "F")$total$n_screened)
  m_n   <- as.numeric(metrics_for_range(b, gender = "M")$total$n_screened)

  # Female + Male may be less than the total (blank/other gender) but never more
  expect_lte(f_n + m_n, all_n)
})

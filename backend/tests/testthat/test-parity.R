# ─────────────────────────────────────────────────────────────────────────────
# Parity against the Excel reference dashboard.
#
# The legacy pipeline printed these comparisons to the console and left it to
# a human to read (calc_v2.R:566-585). Here they are assertions.
#
# They run only when a real RIS export is present — fixtures cannot match real
# programme numbers, so with fixtures loaded these skip rather than fail.
# ─────────────────────────────────────────────────────────────────────────────

# Reference values from the Excel dashboard, as recorded in calc_v2.R:569-585.
# Update these when the reference period changes.
EXCEL_REFERENCE <- list(
  n_screened   = 16352,
  n_cxr        = 14925,
  n_ai_tb      =  2601,
  n_elig_sp    =  4241,
  n_sp_coll    =  2889,
  n_sp_test    =  2336,
  n_mbc        =    55,
  n_cd         =    51,
  n_notified   =   106,
  n_tx_started =    93,
  n_facility   =  1553,
  n_spiro      =  1412,
  n_copd       =   398,
  n_asthma     =   169,
  n_past_tb    =   904
)

test_that("full-period totals match the Excel reference dashboard", {
  skip_if_not(using_real_data(),
              "fixtures loaded — parity is only meaningful against a real RIS export")

  b <- test_bundle()
  total <- metrics_for_range(b)$total

  for (metric in names(EXCEL_REFERENCE)) {
    expect_equal(
      as.integer(total[[metric]]),
      as.integer(EXCEL_REFERENCE[[metric]]),
      info = sprintf("%s: got %s, Excel says %s",
                     metric, total[[metric]], EXCEL_REFERENCE[[metric]])
    )
  }
})

test_that("clinically diagnosed is notified minus microbiologically confirmed", {
  b <- test_bundle()
  total <- metrics_for_range(b)$total
  expect_equal(total$n_cd, total$n_notified - total$n_mbc)
})

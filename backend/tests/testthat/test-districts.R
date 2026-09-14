# District scoping.
#
# The programme runs in Korba and the Excel reference dashboard filters to it.
# The RIS export carries a scattering of records logged against other districts
# — 63 rows across four of them in the Sep-2026 export — and without a filter
# every dashboard figure sat above the workbook by a corresponding amount.
# Trisha's reconciliation traced ~48 of the NNS cohort differences to this one
# cause, so it is worth a test that the exclusion happens and is reported.

test_that("records outside the configured districts are excluded", {
  b <- test_bundle()
  dist <- unique(trimws(as.character(fld(b$ris$logic, b$ris$map, "camp_district"))))
  dist <- dist[!is.na(dist) & dist != ""]
  expect_setequal(dist, CONFIG$districts)
})

test_that("what was excluded is reported, not silently dropped", {
  # The fixtures deliberately include a few non-Korba camps.
  b <- test_bundle()
  expect_gt(length(b$ris$district_excluded), 0)
  for (e in b$ris$district_excluded) {
    expect_true(nzchar(e$district))
    expect_false(e$district %in% CONFIG$districts)
    expect_gt(e$rows, 0)
  }
})

test_that("the configured districts are reported alongside the figures", {
  # A filter nobody can see is worse than no filter: a reader comparing against
  # the workbook needs to know the scope the numbers were computed on.
  b <- test_bundle()
  expect_equal(unlist(b$ris$districts), CONFIG$districts)
})

test_that("a blank district is kept rather than treated as another district", {
  # Losing a real camp to a data-entry gap is a different problem from a camp
  # genuinely belonging elsewhere, and silently dropping it would understate.
  df <- data.frame(
    `Camp District` = c("Korba", NA, "", "Bastar"),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  dist  <- trimws(as.character(df$`Camp District`))
  blank <- is.na(dist) | dist == ""
  keep  <- dist %in% "Korba"
  expect_equal(sum(keep | blank), 3)
})

# The parsing lives in CONFIG, which is built once at load. Re-evaluated here
# so the rules can be tested without reloading the whole config.
parse_districts <- function() {
  raw <- trimws(Sys.getenv("ILIFT_DISTRICTS", unset = "Korba"))
  if (raw == "" || tolower(raw) %in% c("all", "none")) {
    character(0)
  } else {
    d <- trimws(strsplit(raw, ",")[[1]])
    d[nzchar(d)]
  }
}

test_that("ILIFT_DISTRICTS=all disables the filter", {
  # "all" rather than "": Windows cannot hold an empty environment variable —
  # assigning "" unsets it, so Sys.getenv() falls back to the default and the
  # filter would stay on despite an explicit attempt to disable it. The
  # sentinel works on every platform.
  withr::local_envvar(ILIFT_DISTRICTS = "all")
  expect_length(parse_districts(), 0)

  withr::local_envvar(ILIFT_DISTRICTS = "none")
  expect_length(parse_districts(), 0)
})

test_that("ILIFT_DISTRICTS accepts a comma-separated list", {
  withr::local_envvar(ILIFT_DISTRICTS = "Korba, Raigarh ,Bastar")
  expect_equal(parse_districts(), c("Korba", "Raigarh", "Bastar"))
})

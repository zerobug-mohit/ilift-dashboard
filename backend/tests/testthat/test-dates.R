# Date parsing.
#
# A live failure motivated these: RIS Hub exports ISO dates, someone opened the
# CSV in Excel and saved it, and the dates came back as "30-08-2025".
# base::as.Date() read "30" as the year, returned 0030-08-20 without warning,
# every row fell outside the project window, and the dashboard reported no data
# at all. The wrong answer was a valid Date, which is why nothing caught it.

test_that("ISO dates parse as themselves", {
  r <- parse_dates(c("2025-08-30", "2025-07-01"))
  expect_equal(r$dates, as.Date(c("2025-08-30", "2025-07-01")))
})

test_that("day-first dates are not read as year 30", {
  # The exact failure: "30-08-2025" must be 2025-08-30, not 0030-08-20.
  r <- suppressMessages(parse_dates(c("30-08-2025", "15-07-2025")))
  expect_equal(r$dates, as.Date(c("2025-08-30", "2025-07-15")))
  expect_true(all(format(r$dates, "%Y") == "2025"))
})

test_that("a day above 12 proves day-first even when most rows are ambiguous", {
  r <- suppressMessages(parse_dates(c("01-02-2025", "03-04-2025", "30-08-2025")))
  expect_equal(r$dates, as.Date(c("2025-02-01", "2025-04-03", "2025-08-30")))
})

test_that("a month-first file is detected from a second component above 12", {
  r <- suppressMessages(parse_dates(c("08-30-2025", "07-15-2025")))
  expect_equal(r$dates, as.Date(c("2025-08-30", "2025-07-15")))
})

test_that("contradictory formats are refused rather than half-parsed", {
  # 30-08 proves day-first, 08-30 proves month-first. Picking either would
  # silently mangle half the file.
  expect_error(
    parse_dates(c("30-08-2025", "08-30-2025")),
    "not in one consistent format"
  )
})

test_that("a wholly ambiguous column says so", {
  # Every value could be read either way. Day-first is assumed because these
  # exports are Indian, but the assumption is stated rather than hidden.
  expect_message(parse_dates(c("01-02-2025", "03-04-2025")), "ambiguous")
})

test_that("slash separators work as well as dashes", {
  expect_equal(suppressMessages(parse_dates(c("30/08/2025")))$dates, as.Date("2025-08-30"))
  expect_equal(parse_dates(c("2025/08/30"))$dates, as.Date("2025-08-30"))
})

test_that("blanks and the export's zero marker become NA, not a date", {
  r <- parse_dates(c("2025-08-30", "", "0", NA))
  expect_equal(sum(is.na(r$dates)), 3)
  expect_equal(r$dates[1], as.Date("2025-08-30"))
})

test_that("values already typed as dates are passed through", {
  d <- as.Date(c("2025-08-30", "2025-07-01"))
  expect_equal(parse_dates(d)$dates, d)
})

test_that("an all-blank column yields NAs rather than erroring", {
  r <- parse_dates(c("", NA, ""))
  expect_true(all(is.na(r$dates)))
})

test_that("a misread date lands outside the project window", {
  # This is what made the failure invisible: as.Date("30-08-2025") is not an
  # error, it is the year 30 — a valid Date that silently fails every
  # comparison against the project window.
  naive <- suppressWarnings(as.Date("30-08-2025"))
  expect_false(is.na(naive))                       # no error to catch
  expect_lt(naive, CONFIG$project_start)           # and it fails the filter

  fixed <- suppressMessages(parse_dates("30-08-2025"))$dates
  expect_gt(fixed, CONFIG$project_start)
})

# ─────────────────────────────────────────────────────────────────────────────
# Upload filename validation.
#
# POST /api/upload writes files to disk, so the filename is treated as
# untrusted input. These cases are all ones that previously slipped through or
# would have, and they must keep failing.
# ─────────────────────────────────────────────────────────────────────────────

test_that("ordinary spreadsheet names are accepted", {
  expect_equal(safe_filename("ris_2026-08-14.xlsx"), "ris_2026-08-14.xlsx")
  expect_equal(safe_filename("CRD MIS (June).xlsx"), "CRD MIS (June).xlsx")
  expect_equal(safe_filename("25Q1.XLS"), "25Q1.XLS")
})

test_that("path traversal is rejected", {
  expect_null(safe_filename("../../../evil.xlsx"))
  expect_null(safe_filename("..\\..\\evil.xlsx"))
  expect_null(safe_filename("../evil.xlsx"))
  expect_null(safe_filename(".."))
})

test_that("a directory component never survives into the stored name", {
  # Even when not a traversal, any path prefix must be stripped
  out <- safe_filename("C:/data/exports/ris.xlsx")
  expect_equal(out, "ris.xlsx")
  expect_false(grepl("[/\\\\]", out))
})

test_that("Excel lock files are rejected", {
  # Regression: base::basename() performs tilde expansion, so checking for
  # "~$" *after* calling it silently let these through as "<user>$lock.xlsx".
  expect_null(safe_filename("~$lock.xlsx"))
  expect_null(safe_filename("~$Offline_iLIFT_Dashboard.xlsx"))
})

test_that("base::basename would have mangled the lock-file marker on Windows", {
  # Documents why safe_filename() strips paths with a regex instead.
  # If this ever stops being true, the custom stripping can be reconsidered.
  #
  # Windows-only: tilde expansion happens there but not on Linux, where
  # basename("~$lock.xlsx") returns the string unchanged. The behaviour that
  # actually matters — safe_filename() rejecting these — is asserted above on
  # every platform, so skipping here loses no coverage.
  skip_if_not(.Platform$OS.type == "windows", "tilde expansion is Windows-only")
  expect_false(startsWith(basename("~$lock.xlsx"), "~$"))
})

test_that("hidden files and non-spreadsheets are rejected", {
  expect_null(safe_filename(".hidden.xlsx"))
  expect_null(safe_filename("notes.txt"))
  expect_null(safe_filename("script.R"))
  expect_null(safe_filename("payload.xlsx.exe"))
  expect_null(safe_filename("archive.zip"))
  expect_null(safe_filename(""))
  expect_null(safe_filename(NULL))
})

test_that("control characters are rejected", {
  # Built with rawToChar so the control byte is unambiguous in the source.
  # (R cannot hold an embedded NUL in a character vector at all, so that case
  # cannot reach safe_filename() as a string in the first place.)
  ctl <- function(byte) paste0("ris", rawToChar(as.raw(byte)), ".xlsx")
  expect_null(safe_filename(ctl(10)))   # LF
  expect_null(safe_filename(ctl(13)))   # CR
  expect_null(safe_filename(ctl(9)))    # TAB
  expect_null(safe_filename(ctl(27)))   # ESC
  expect_null(safe_filename(ctl(127)))  # DEL
})

test_that("unusual characters are sanitised rather than passed through", {
  out <- safe_filename("ris;rm -rf&.xlsx")
  expect_false(is.null(out))
  expect_false(grepl("[;&]", out))
  expect_true(grepl("\\.xlsx$", out))
})

test_that("overlong names are truncated but keep their extension", {
  long <- paste0(paste(rep("a", 300), collapse = ""), ".xlsx")
  out  <- safe_filename(long)
  expect_lte(nchar(out), 120)
  expect_true(grepl("\\.xlsx$", out))
})

test_that("only known slots resolve to a target directory", {
  for (s in UPLOAD_SLOTS) {
    expect_false(is.null(slot_target(s)$dir), info = s)
  }
  expect_null(slot_target("../../etc"))
  expect_error(save_upload("nonsense", "ris.xlsx", as.raw(c(0x50, 0x4B, 0x03, 0x04))),
               "unknown slot")
})

test_that("empty and non-xlsx payloads are rejected", {
  expect_error(save_upload("ris", "ris.xlsx", raw(0)), "empty")
  # .xlsx must actually be a zip (PK magic bytes)
  expect_error(save_upload("ris", "ris.xlsx", charToRaw("not a spreadsheet")),
               "does not look like a valid")
})

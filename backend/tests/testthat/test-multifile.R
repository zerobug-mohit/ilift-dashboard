# Combining a source that arrives as several files.
#
# A large export is often downloaded in chunks — ris1.csv, ris2.csv, ris3.csv.
# Each carries its own header row, so they are bound by column name rather than
# concatenated as text. The property that matters: splitting an export and
# recombining it must produce exactly what the single file produced.

# Write a data frame out as `n` chunks in `dir`, named <stem>1..<stem>n.
split_csv <- function(df, dir, stem, n) {
  rows <- split(seq_len(nrow(df)), cut(seq_len(nrow(df)), n, labels = FALSE))
  paths <- character(0)
  for (i in seq_along(rows)) {
    p <- file.path(dir, paste0(stem, i, ".csv"))
    write.csv(df[rows[[i]], , drop = FALSE], p, row.names = FALSE)
    paths <- c(paths, p)
  }
  paths
}

test_that("chunks of one export recombine to the original table", {
  df <- data.frame(
    `Beneficiary ID` = sprintf("IL%05d", 1:30),
    `Camp ID`        = rep(c("C1", "C2", "C3"), each = 10),
    Value            = 1:30,
    check.names = FALSE
  )
  dir <- withr::local_tempdir()
  paths <- split_csv(df, dir, "part", 3)

  combined <- suppressMessages(read_source_tables(paths, label = "test"))
  expect_equal(nrow(combined), nrow(df))
  expect_equal(colnames(combined), colnames(df))
  # Header rows must not survive as data
  expect_false(any(combined$Value == "Value"))
  expect_equal(sort(as.integer(combined$Value)), 1:30)
})

test_that("a chunk uploaded twice does not double the rows", {
  df <- data.frame(`Beneficiary ID` = sprintf("IL%05d", 1:12), V = 1:12,
                   check.names = FALSE)
  dir <- withr::local_tempdir()
  paths <- split_csv(df, dir, "part", 2)
  dup <- file.path(dir, "part1_again.csv")
  file.copy(paths[1], dup)

  combined <- suppressMessages(read_source_tables(c(paths, dup), label = "test"))
  expect_equal(nrow(combined), 12)
  expect_equal(attr(combined, "dropped_duplicates"), 6)
})

test_that("a genuine repeat visit is kept, not mistaken for a duplicate", {
  # Same beneficiary at two different camps is real data — the range-level
  # deduplication in calc_logic() handles counting them once, and dropping the
  # row here would lose the second visit entirely.
  df <- data.frame(
    `Beneficiary ID` = c("IL00001", "IL00001", "IL00002"),
    `Camp ID`        = c("C1", "C2", "C1"),
    check.names = FALSE
  )
  dir <- withr::local_tempdir()
  p <- file.path(dir, "one.csv")
  write.csv(df, p, row.names = FALSE)

  combined <- suppressMessages(read_source_tables(p, label = "test"))
  expect_equal(nrow(combined), 3)
})

test_that("chunks with differently ordered columns still line up", {
  a <- data.frame(`Beneficiary ID` = "IL00001", Age = 40, check.names = FALSE)
  b <- data.frame(Age = 50, `Beneficiary ID` = "IL00002", check.names = FALSE)
  dir <- withr::local_tempdir()
  pa <- file.path(dir, "a.csv"); write.csv(a, pa, row.names = FALSE)
  pb <- file.path(dir, "b.csv"); write.csv(b, pb, row.names = FALSE)

  combined <- suppressMessages(read_source_tables(c(pa, pb), label = "test"))
  expect_equal(nrow(combined), 2)
  expect_equal(combined$`Beneficiary ID`, c("IL00001", "IL00002"))
  expect_equal(as.numeric(combined$Age), c(40, 50))
})

test_that("a chunk missing a column is reported, not silently blanked", {
  a <- data.frame(`Beneficiary ID` = "IL00001", Extra = "x", check.names = FALSE)
  b <- data.frame(`Beneficiary ID` = "IL00002", check.names = FALSE)
  dir <- withr::local_tempdir()
  pa <- file.path(dir, "a.csv"); write.csv(a, pa, row.names = FALSE)
  pb <- file.path(dir, "b.csv"); write.csv(b, pb, row.names = FALSE)

  expect_message(read_source_tables(c(pa, pb), label = "test"),
                 "column\\(s\\) the other files lack")
})

test_that("find_source returns every matching file, name-ordered", {
  # Name order rather than modification time: which chunk finished downloading
  # first should not change the result.
  dir <- withr::local_tempdir()
  incoming <- file.path(dir, "incoming")
  dir.create(incoming, recursive = TRUE)
  for (n in c("ris3.csv", "ris1.csv", "ris2.csv")) {
    writeLines("Beneficiary ID\nIL00001", file.path(incoming, n))
  }

  withr::local_envvar(ILIFT_DATA_DIR = dir)
  old <- CONFIG$incoming_dir
  CONFIG$incoming_dir <<- incoming
  on.exit(CONFIG$incoming_dir <<- old, add = TRUE)

  found <- find_source("ris")
  expect_equal(basename(found), c("ris1.csv", "ris2.csv", "ris3.csv"))
})

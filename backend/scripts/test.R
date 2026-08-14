# Run the backend test suite.
#   Rscript backend/scripts/test.R

script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", args, value = TRUE)
  if (length(m)) dirname(normalizePath(sub("^--file=", "", m[1]))) else getwd()
}
backend_dir <- normalizePath(file.path(script_dir(), ".."), mustWork = TRUE)
setwd(backend_dir)
if (Sys.getenv("ILIFT_DATA_DIR") == "") Sys.setenv(ILIFT_DATA_DIR = file.path(backend_dir, "data"))

suppressPackageStartupMessages(library(testthat))
res <- testthat::test_dir(file.path(backend_dir, "tests", "testthat"), stop_on_failure = FALSE)

df <- as.data.frame(res)
if (sum(df$failed) > 0 || sum(df$error) > 0) quit(status = 1)

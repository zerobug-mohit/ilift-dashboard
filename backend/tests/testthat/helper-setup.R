# Shared test setup: locate the backend, load modules, expose the bundle.

backend_dir <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = TRUE)
if (Sys.getenv("ILIFT_DATA_DIR") == "") {
  Sys.setenv(ILIFT_DATA_DIR = file.path(backend_dir, "data"))
}

suppressPackageStartupMessages({ library(dplyr); library(digest) })

for (f in c("config.R", "schema.R", "ingest.R", "cache.R", "uploads.R", "auth.R",
            "metrics_core.R", "metrics_nns.R", "metrics_weekly.R")) {
  source(file.path(backend_dir, "R", f))
}

#' Is the loaded dataset the real programme export rather than fixtures?
#' Parity assertions against the Excel reference only make sense for real data.
#'
#' Driven by the marker file make_fixtures.R writes, not by sniffing filenames:
#' a filename heuristic treats any upload not containing "fixture" as real, so
#' a stray test file would silently switch the parity assertions on and fail
#' against synthetic numbers.
using_real_data <- function() {
  if (file.exists(file.path(CONFIG$incoming_dir, ".fixtures"))) return(FALSE)
  !is.null(find_source("ris"))
}

test_bundle <- function() get_bundle()

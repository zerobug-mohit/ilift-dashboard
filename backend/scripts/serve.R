# Start the iLIFT API server.
#   Rscript backend/scripts/serve.R
# Environment:
#   ILIFT_DATA_DIR  data root (default: backend/data)
#   ILIFT_PORT      listen port (default: 8000)

suppressPackageStartupMessages(library(plumber))

script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", args, value = TRUE)
  if (length(m)) dirname(normalizePath(sub("^--file=", "", m[1]))) else getwd()
}

backend_dir <- normalizePath(file.path(script_dir(), ".."), mustWork = TRUE)
setwd(backend_dir)

if (Sys.getenv("ILIFT_DATA_DIR") == "") {
  Sys.setenv(ILIFT_DATA_DIR = file.path(backend_dir, "data"))
}

port <- as.integer(Sys.getenv("ILIFT_PORT", unset = "8000"))

cat("iLIFT API\n")
cat("  data dir :", Sys.getenv("ILIFT_DATA_DIR"), "\n")
cat("  port     :", port, "\n\n")

pr <- plumber::pr(file.path(backend_dir, "plumber.R"))
pr$run(host = "127.0.0.1", port = port, docs = FALSE)

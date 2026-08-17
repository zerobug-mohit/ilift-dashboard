# Start the iLIFT server.
#   Rscript backend/scripts/serve.R
#
# Environment:
#   ILIFT_DATA_DIR   data root                     (default: backend/data)
#   ILIFT_PORT       listen port                   (default: 8000)
#   ILIFT_HOST       bind address                  (default: 127.0.0.1)
#   ILIFT_STATIC_DIR built frontend to serve at /  (default: frontend/dist if present)
#
# When a built frontend is present it is served from the same origin as the API.
# That is how the deployed container runs, and it removes three whole classes of
# problem that the split GitHub Pages + local backend arrangement has: no CORS,
# no browser local-network permission, and no API URL for anyone to configure.

suppressPackageStartupMessages(library(plumber))

script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", args, value = TRUE)
  if (length(m)) dirname(normalizePath(sub("^--file=", "", m[1]))) else getwd()
}

backend_dir <- normalizePath(file.path(script_dir(), ".."), mustWork = TRUE)
project_dir <- normalizePath(file.path(backend_dir, ".."), mustWork = TRUE)
setwd(backend_dir)

if (Sys.getenv("ILIFT_DATA_DIR") == "") {
  Sys.setenv(ILIFT_DATA_DIR = file.path(backend_dir, "data"))
}

port <- as.integer(Sys.getenv("ILIFT_PORT", unset = "8000"))

# Bind to all interfaces only when asked. A container needs 0.0.0.0 to be
# reachable; a laptop does not, and defaulting to it would silently expose the
# API to the local network.
host <- Sys.getenv("ILIFT_HOST", unset = "127.0.0.1")

static_dir <- Sys.getenv("ILIFT_STATIC_DIR", unset = "")
if (!nzchar(static_dir)) {
  candidate <- file.path(project_dir, "frontend", "dist")
  if (dir.exists(candidate) && file.exists(file.path(candidate, "index.html"))) {
    static_dir <- candidate
  }
}

cat("iLIFT server\n")
cat("  data dir :", Sys.getenv("ILIFT_DATA_DIR"), "\n")
cat("  host:port:", paste0(host, ":", port), "\n")
cat("  frontend :", if (nzchar(static_dir)) static_dir else "not served (API only)", "\n\n")

pr <- plumber::pr(file.path(backend_dir, "plumber.R"))

if (nzchar(static_dir)) {
  pr <- plumber::pr_static(pr, "/", static_dir)
}

pr$run(host = host, port = port, docs = FALSE)

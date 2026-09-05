# Quick backend smoke test — loads sources and exercises every metric module
# without starting the HTTP server.
#   Rscript backend/scripts/smoke.R

script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", args, value = TRUE)
  if (length(m)) dirname(normalizePath(sub("^--file=", "", m[1]))) else getwd()
}
backend_dir <- normalizePath(file.path(script_dir(), ".."), mustWork = TRUE)
setwd(backend_dir)
if (Sys.getenv("ILIFT_DATA_DIR") == "") Sys.setenv(ILIFT_DATA_DIR = file.path(backend_dir, "data"))

suppressPackageStartupMessages({ library(dplyr); library(digest) })
for (f in c("config.R","schema.R", "flags.R","ingest.R","cache.R",
            "metrics_core.R","metrics_nns.R","metrics_weekly.R")) source(file.path("R", f))

cat("── sources ──────────────────────────────────────────\n")
for (s in source_status()) {
  cat(sprintf("  %-8s present=%-5s files=%s\n", s$key, s$present,
              paste(unlist(s$files), collapse = ", ")))
}

b <- get_bundle()
cat("\n── schema ───────────────────────────────────────────\n")
if (length(b$ris$warnings) == 0) cat("  all columns confirmed by header\n")
for (w in b$ris$warnings) cat("  ! ", w, "\n", sep = "")

cat("\n── conflict check (cols 73/74) ──────────────────────\n")
for (c in b$ris$conflicts) {
  cat(sprintf("  col %-3s header='%s'\n    claimed by: %s\n",
              c$index, c$header, paste(c$claimants, collapse = " | ")))
}

cat("\n── full-range metrics ───────────────────────────────\n")
full <- metrics_for_range(b)
keys <- c("n_camps","n_screened","n_cxr","n_ai_tb","n_elig_sp","n_sp_coll",
          "n_sp_test","n_mbc","n_notified","n_tx_started","n_facility",
          "n_spiro","n_copd","n_asthma","n_past_tb")
for (k in keys) cat(sprintf("  %-14s %8s\n", k, format(full$total[[k]], big.mark = ",")))

cat("\n── THE FIX: range dedup vs legacy sum-of-months ──────\n")
cat("  (legacy build_v3.py:703 summed monthly buckets for any range)\n\n")
cat(sprintf("  %-14s %10s %10s %10s\n", "metric", "correct", "legacy", "overcount"))
for (k in c("n_screened","n_cxr","n_ai_tb","n_elig_sp","n_facility","n_past_tb")) {
  corr <- full$total[[k]]; leg <- full$sum_of_monthly[[k]]
  cat(sprintf("  %-14s %10s %10s %10s\n", k,
              format(corr, big.mark=","), format(leg, big.mark=","),
              format(leg - corr, big.mark=",")))
}

cat("\n── sub-range (2025-10 .. 2026-01) ───────────────────\n")
sub <- metrics_for_range(b, "2025-10", "2026-01")
cat(sprintf("  months=%s  screened=%s (legacy would say %s)\n",
            paste(sub$months, collapse=","),
            format(sub$total$n_screened, big.mark=","),
            format(sub$sum_of_monthly$n_screened, big.mark=",")))

cat("\n── gender split ─────────────────────────────────────\n")
for (g in c("all","F","M")) {
  r <- metrics_for_range(b, gender = g)
  cat(sprintf("  %-4s screened=%s\n", g, format(r$total$n_screened, big.mark=",")))
}

cat("\n── NNS ──────────────────────────────────────────────\n")
nns <- nns_for_range(b)
cat(sprintf("  cohorts=%d months=%d\n", length(nns$cohorts), length(nns$months)))
for (c in head(nns$cohorts, 4)) {
  cat(sprintf("    %-28s n=%-6s tb=%-4s mbc=%s\n",
              c$label, c$total$n, c$total$tb, c$total$mbc))
}

cat("\n── weekly ───────────────────────────────────────────\n")
wk <- weekly_for_range(b)
cat(sprintf("  weeks=%d  has_coordinates=%s\n", length(wk$weeks), wk$has_coordinates))
for (w in head(wk$weeks, 3)) {
  cat(sprintf("    %s..%s camps=%-3s screened=%-5s avg/camp=%s\n",
              w$week, w$week_end, w$n_camps, w$n_screen, w$avg_ff))
}

cat("\nOK — all modules ran.\n")

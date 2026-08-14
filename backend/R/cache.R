# ─────────────────────────────────────────────────────────────────────────────
# cache.R — source-aware caching
#
# This is what makes the dashboard non-static. The cache key includes a
# fingerprint of the source files (name + size + mtime), so dropping a fresh
# export into data/incoming/ invalidates every cached result automatically —
# no rebuild, no restart.
# ─────────────────────────────────────────────────────────────────────────────

.CACHE <- new.env(parent = emptyenv())
.CACHE$bundle      <- NULL
.CACHE$fingerprint <- NULL
.CACHE$results     <- list()
.CACHE$load_error  <- NULL

#' Get the current data bundle, reloading if the source files changed.
#' `force = TRUE` reloads unconditionally (used by POST /api/refresh).
get_bundle <- function(force = FALSE) {
  fp <- sources_fingerprint()

  if (!force && !is.null(.CACHE$bundle) && identical(.CACHE$fingerprint, fp)) {
    return(.CACHE$bundle)
  }

  message("[cache] loading sources (fingerprint ", substr(fp, 1, 8), ")")
  bundle <- tryCatch(ingest_all(), error = function(e) {
    .CACHE$load_error <<- conditionMessage(e)
    NULL
  })

  if (is.null(bundle)) {
    .CACHE$bundle <- NULL
    .CACHE$fingerprint <- NULL
    stop(.CACHE$load_error %||% "ingest failed")
  }

  .CACHE$load_error  <- NULL
  .CACHE$bundle      <- bundle
  .CACHE$fingerprint <- fp
  .CACHE$results     <- list()   # source data changed: drop derived results
  message("[cache] loaded ", bundle$ris$n_rows, " rows / ",
          bundle$ris$n_bids, " beneficiaries across ", length(bundle$months), " months")
  bundle
}

#' Memoise a computation against the current source fingerprint + parameters.
cached <- function(key, params, compute) {
  fp <- sources_fingerprint()
  k  <- digest::digest(list(key, params, fp))

  if (!is.null(.CACHE$results[[k]])) return(.CACHE$results[[k]])

  val <- compute()
  .CACHE$results[[k]] <- val
  val
}

#' Drop everything and reload from disk.
invalidate_cache <- function() {
  .CACHE$bundle      <- NULL
  .CACHE$fingerprint <- NULL
  .CACHE$results     <- list()
  invisible(TRUE)
}

cache_stats <- function() {
  list(
    loaded       = !is.null(.CACHE$bundle),
    fingerprint  = .CACHE$fingerprint,
    entries      = length(.CACHE$results),
    load_error   = .CACHE$load_error
  )
}

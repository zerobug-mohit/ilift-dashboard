# ─────────────────────────────────────────────────────────────────────────────
# auth.R — two levels of access
#
#   viewer : may read every metric endpoint
#   admin  : may additionally upload data and force a refresh
#
# Driven entirely by environment variables:
#
#   ILIFT_VIEWER_PASSWORD   shared password for the team
#   ILIFT_ADMIN_TOKEN       secret held only by whoever refreshes the data
#
# If NEITHER is set the API is open. That keeps local development friction-free
# (`npm run dev` needs no login) while a deployment that sets them is closed by
# default. A deployment that sets only ILIFT_ADMIN_TOKEN gets open reads and
# protected writes, which is also a legitimate configuration.
#
# Credentials arrive as `Authorization: Bearer <secret>`. Over HTTPS that is
# fine; over plain HTTP it is not, which is why deployments must terminate TLS.
# ─────────────────────────────────────────────────────────────────────────────

AUTH <- local({
  viewer <- Sys.getenv("ILIFT_VIEWER_PASSWORD", unset = "")
  admin  <- Sys.getenv("ILIFT_ADMIN_TOKEN",     unset = "")
  list(
    viewer_password = viewer,
    admin_token     = admin,
    read_protected  = nzchar(viewer),
    write_protected = nzchar(admin)
  )
})

#' Constant-time string comparison.
#'
#' `==` on strings short-circuits at the first differing byte, so how long a
#' comparison takes leaks how much of the secret was correct. The margin is
#' small over a network, but the fix is three lines.
secure_equals <- function(a, b) {
  a <- as.character(a %||% ""); b <- as.character(b %||% "")
  ab <- charToRaw(a); bb <- charToRaw(b)
  if (length(ab) != length(bb)) return(FALSE)
  if (length(ab) == 0) return(TRUE)
  sum(as.integer(xor(ab, bb))) == 0
}

#' Pull the bearer credential out of a request. Also accepts ?token= so a
#' viewer link can carry the password, and an X-ILIFT-Token header.
request_credential <- function(req) {
  hdr <- req$HTTP_AUTHORIZATION
  if (!is.null(hdr) && nzchar(hdr)) {
    if (grepl("^Bearer\\s+", hdr, ignore.case = TRUE)) {
      return(sub("^Bearer\\s+", "", hdr, ignore.case = TRUE))
    }
    return(hdr)
  }
  alt <- req$HTTP_X_ILIFT_TOKEN
  if (!is.null(alt) && nzchar(alt)) return(alt)

  if (!is.null(req$argsQuery$token)) return(as.character(req$argsQuery$token))
  ""
}

#' Classify a request: "admin", "viewer", or "anonymous".
auth_level <- function(req) {
  cred <- request_credential(req)

  if (AUTH$write_protected && secure_equals(cred, AUTH$admin_token)) return("admin")
  if (AUTH$read_protected  && secure_equals(cred, AUTH$viewer_password)) return("viewer")

  # Nothing configured for this tier means that tier is open
  if (!AUTH$read_protected) return(if (!AUTH$write_protected) "admin" else "viewer")
  "anonymous"
}

#' Endpoints that change state and therefore need admin.
WRITE_PATHS <- c("/api/upload", "/api/refresh")

is_write_path <- function(path) {
  any(vapply(WRITE_PATHS, function(p) startsWith(path, p), logical(1)))
}

#' Describe the configuration, for GET /api/meta and the startup banner.
auth_status <- function() {
  list(
    read_protected  = AUTH$read_protected,
    write_protected = AUTH$write_protected,
    mode = if (!AUTH$read_protected && !AUTH$write_protected) "open"
           else if (AUTH$read_protected && AUTH$write_protected) "viewer+admin"
           else if (AUTH$write_protected) "open reads, protected writes"
           else "protected reads, open writes"
  )
}

#' Warn loudly about configurations that are unsafe on a public deployment.
auth_startup_report <- function() {
  cat("Access control:\n")
  cat("  reads :", if (AUTH$read_protected) "viewer password required" else "OPEN", "\n")
  cat("  writes:", if (AUTH$write_protected) "admin token required" else "OPEN", "\n")

  if (!AUTH$write_protected) {
    cat("\n  ! ILIFT_ADMIN_TOKEN is not set — anyone who can reach this API can\n")
    cat("    upload data and overwrite the dashboard. Fine on a laptop; set it\n")
    cat("    before exposing this to a network.\n")
  }
  if (AUTH$read_protected && nchar(AUTH$viewer_password) < 8) {
    cat("\n  ! ILIFT_VIEWER_PASSWORD is shorter than 8 characters.\n")
  }
  if (AUTH$write_protected && nchar(AUTH$admin_token) < 16) {
    cat("\n  ! ILIFT_ADMIN_TOKEN is shorter than 16 characters. Use a random\n")
    cat("    string, not a memorable one — it is the only thing protecting\n")
    cat("    the upload endpoint.\n")
  }
  cat("\n")
}

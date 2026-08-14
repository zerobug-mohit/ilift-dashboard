# ─────────────────────────────────────────────────────────────────────────────
# uploads.R — accept source workbooks over HTTP and place them in incoming/
#
# The watched folder still works — dropping files in by hand is equivalent.
# This exists so the refresh can be done from the dashboard itself, without
# the person refreshing needing to know where the folder lives.
#
# SAFETY
# This endpoint writes files to disk, so it validates rather than trusts:
#   - the slot must be one of the three known sources
#   - the filename is reduced to a basename and re-checked (no traversal)
#   - only .xlsx / .xls are accepted
#   - a size ceiling is enforced
# The server binds to 127.0.0.1 only (scripts/serve.R), so it is not reachable
# from the network.
# ─────────────────────────────────────────────────────────────────────────────

UPLOAD_SLOTS <- c("ris", "crd_mis", "nikshay")

# Real RIS exports run to tens of MB; this is a sanity ceiling, not a target.
MAX_UPLOAD_BYTES <- as.numeric(Sys.getenv("ILIFT_MAX_UPLOAD_MB", unset = "150")) * 1024^2

#' Reduce an uploaded filename to something safe to write.
#' Returns NULL if the name cannot be made safe.
#'
#' NOTE: this deliberately does NOT use base::basename(). R's basename()
#' performs tilde expansion, so basename("~$book.xlsx") returns
#' "<user>$book.xlsx" — which silently destroys the "~$" marker that
#' identifies an Excel lock file, letting it through a later check.
#' The path component is stripped with a plain regex instead.
safe_filename <- function(name) {
  if (is.null(name) || !nzchar(name)) return(NULL)
  raw <- as.character(name)[1]

  # Reject on the raw name, before any transformation can disguise it
  if (grepl("^~\\$", raw)) return(NULL)                    # Excel lock file
  if (grepl("\\.\\.", raw, fixed = FALSE)) {
    # ".." anywhere is a traversal attempt; harmless once stripped, but there
    # is no legitimate reason for it in an export filename.
    if (grepl("(^|[/\\\\])\\.\\.([/\\\\]|$)", raw)) return(NULL)
  }
  if (grepl("[\x01-\x1f\x7f]", raw)) return(NULL)   # control characters

  # Strip every directory component, both path styles, without tilde expansion
  base <- sub(".*[/\\\\]", "", raw)

  if (!nzchar(base) || base %in% c(".", "..")) return(NULL)
  if (grepl("[/\\\\]", base)) return(NULL)
  if (grepl("^~\\$", base) || startsWith(base, ".")) return(NULL)

  # Only spreadsheet extensions
  if (!grepl("\\.xlsx?$", base, ignore.case = TRUE)) return(NULL)

  # Keep it to characters that behave on Windows and POSIX alike
  cleaned <- gsub("[^A-Za-z0-9._ ()-]", "_", base)
  if (nchar(cleaned) > 120) {
    ext <- sub(".*(\\.xlsx?)$", "\\1", cleaned, ignore.case = TRUE)
    cleaned <- paste0(substr(cleaned, 1, 120 - nchar(ext)), ext)
  }
  cleaned
}

#' Where a slot's files live, and the prefix new files must carry so that
#' find_source() in config.R will match them.
slot_target <- function(slot) {
  switch(slot,
    ris     = list(dir = CONFIG$incoming_dir, prefix = "ris_",  replace = TRUE),
    crd_mis = list(dir = CONFIG$incoming_dir, prefix = "crd_",  replace = TRUE),
    nikshay = list(dir = file.path(CONFIG$incoming_dir, "nikshay"),
                   prefix = "", replace = FALSE)
  )
}

#' Move superseded files out of the way rather than deleting them.
#' RIS and CRD MIS are single-file sources: a new upload replaces the old one,
#' but the old one is kept under incoming/archive/ so a bad upload is
#' recoverable without going back to the source system.
archive_existing <- function(slot) {
  files <- find_source(slot)
  if (is.null(files) || length(files) == 0) return(character(0))

  archive_dir <- file.path(CONFIG$incoming_dir, "archive")
  if (!dir.exists(archive_dir)) dir.create(archive_dir, recursive = TRUE, showWarnings = FALSE)

  stamp <- format(Sys.time(), "%Y%m%d-%H%M%S")
  moved <- character(0)
  for (f in files) {
    dest <- file.path(archive_dir, paste0(stamp, "__", basename(f)))
    if (file.rename(f, dest)) moved <- c(moved, basename(f))
  }
  moved
}

#' Persist one uploaded file into the correct slot.
#'
#' @param slot     one of UPLOAD_SLOTS
#' @param filename the client-supplied name
#' @param bytes    raw vector of file content
#' @return list describing what happened, or stops with a message
save_upload <- function(slot, filename, bytes) {
  if (!slot %in% UPLOAD_SLOTS) {
    stop("unknown slot '", slot, "' — expected one of: ", paste(UPLOAD_SLOTS, collapse = ", "))
  }
  if (is.null(bytes) || length(bytes) == 0) {
    stop("uploaded file is empty")
  }
  if (length(bytes) > MAX_UPLOAD_BYTES) {
    stop(sprintf("file is %.1f MB, which exceeds the %.0f MB limit",
                 length(bytes) / 1024^2, MAX_UPLOAD_BYTES / 1024^2))
  }

  safe <- safe_filename(filename)
  if (is.null(safe)) {
    stop("'", filename, "' is not an accepted filename — must be a .xlsx or .xls file")
  }

  # xlsx is a zip: check the magic bytes so a renamed file fails here rather
  # than deep inside read_excel() on the next request.
  if (grepl("\\.xlsx$", safe, ignore.case = TRUE)) {
    if (length(bytes) < 4 || !identical(as.integer(bytes[1:2]), c(0x50L, 0x4BL))) {
      stop("'", safe, "' does not look like a valid .xlsx file")
    }
  }

  target <- slot_target(slot)
  if (!dir.exists(target$dir)) dir.create(target$dir, recursive = TRUE, showWarnings = FALSE)

  archived <- if (target$replace) archive_existing(slot) else character(0)

  # Ensure the stored name matches the pattern find_source() looks for
  stored <- safe
  if (nzchar(target$prefix) && !grepl(paste0("^", target$prefix), stored, ignore.case = TRUE)) {
    stored <- paste0(target$prefix, stored)
  }

  path <- file.path(target$dir, stored)
  writeBin(bytes, path)

  list(
    slot     = slot,
    stored   = stored,
    original = filename,
    bytes    = length(bytes),
    archived = as.list(archived)
  )
}

#' Extract uploaded files from a parsed multipart body.
#' Accepts any field name so the client is not forced into one convention.
extract_uploads <- function(body) {
  if (is.null(body) || length(body) == 0) return(list())

  out <- list()
  for (nm in names(body)) {
    part <- body[[nm]]
    # webutils gives file parts as a list with `value` (raw) and `filename`
    if (is.list(part) && !is.null(part$value) && is.raw(part$value)) {
      out[[length(out) + 1]] <- list(
        filename = part$filename %||% nm,
        bytes    = part$value
      )
    } else if (is.raw(part)) {
      out[[length(out) + 1]] <- list(filename = nm, bytes = part)
    }
  }
  out
}

# ─────────────────────────────────────────────────────────────────────────────
# Schema resolution — guards against silent column drift.
#
# The legacy scripts addressed columns purely by position, so a reordered
# RISHUB export would change every metric with no error. These tests assert
# the resolver catches that instead.
# ─────────────────────────────────────────────────────────────────────────────

test_that("every schema field resolves against the loaded workbook", {
  b <- test_bundle()
  missing <- Filter(function(d) is.na(d$index), b$ris$diagnostics)
  expect_equal(length(missing), 0,
               info = paste("unresolved:",
                            paste(sapply(missing, `[[`, "field"), collapse = ", ")))
})

test_that("resolver prefers header text over legacy position", {
  # Two columns swapped relative to their legacy positions: the resolver should
  # follow the headers, not the indices.
  df <- as.data.frame(matrix("", nrow = 1, ncol = 180), stringsAsFactors = FALSE)
  hdr <- paste0("col_", 1:180)
  hdr[50]  <- "Beneficiary ID"
  hdr[106] <- "Gender"          # gender sitting where genki_result normally is
  hdr[54]  <- "Genki Edge Result"
  colnames(df) <- hdr

  res <- resolve_schema(df)
  expect_equal(res$index$gender, 106)
  expect_equal(res$index$genki_result, 54)
  expect_equal(res$index$beneficiary_id, 50)
})

test_that("a missing column is reported rather than silently zero", {
  df <- as.data.frame(matrix("", nrow = 1, ncol = 10), stringsAsFactors = FALSE)
  colnames(df) <- paste0("col_", 1:10)

  res <- resolve_schema(df)
  expect_true(is.na(res$index$eligible_sputum))   # legacy index 177 > ncol
  expect_gt(length(schema_warnings(res)), 0)
})

test_that("fld() returns NA rather than erroring on an unresolved column", {
  df <- data.frame(a = 1:3)
  expect_true(all(is.na(fld(df, list(missing_col = NA_integer_), "missing_col"))))
})

test_that("the col 73/74 conflict is surfaced with the actual header", {
  b <- test_bundle()
  conflicts <- b$ris$conflicts
  expect_equal(length(conflicts), 2)
  for (c in conflicts) {
    expect_true(c$index %in% c(73, 74))
    expect_equal(length(c$claimants), 2)
  }
})

test_that("weekly coordinates come from named headers, not positions 73/74", {
  b <- test_bundle()
  wk <- weekly_for_range(b)
  skip_if(!wk$has_coordinates, "no latitude/longitude headers in this dataset")

  camps <- unlist(lapply(wk$camps, function(w) w$camps), recursive = FALSE)
  skip_if(length(camps) == 0, "no camps in recent weeks")

  with_coords <- Filter(function(c) !is.null(c$lat), camps)
  expect_gt(length(with_coords), 0)
  # Chhattisgarh bounding box — proves these are coordinates, not symptom flags
  for (c in head(with_coords, 20)) {
    expect_true(c$lat > 17 && c$lat < 25)
    expect_true(c$lon > 79 && c$lon < 85)
  }
})

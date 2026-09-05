# Tests for the Logic sheet port (flags.R).
#
# These are the only guard on formulas that used to live in an Excel workbook,
# so they assert the definitions themselves — not merely that something ran.
# Each case names the legacy section it covers ([13A] … [13Z] of
# `iLift Data and Dashboard.R`) so a disagreement can be traced to a formula.

# A minimal raw export: every column compute_logic_flags() requires, so a test
# can override just the fields it cares about.
raw_row <- function(...) {
  base <- list(
    `Camp ID`                            = "C1",
    `Beneficiary ID`                     = "IL00001",
    `Genki Edge Result`                  = "Normal",
    `Symptoms`                           = "None",
    `Sputum Result(Same Day)`            = "",
    `Sputum Result(Next Day)`            = "",
    `Sputum Result(Other Day)`           = "",
    `Sputum Collected(Same Day)`         = "",
    `Sputum Collected(Next Day)`         = "",
    `Sputum Collected(Other Day)`        = "",
    `mMRC Scale`                         = "0",
    `TB Confirmed by Clinician`          = "",
    `Chronic Respiratory Diseases`       = "",
    `BMI`                                = "22",
    `Blood Sugar (mg/dL)`                = "90",
    `Cough (in Last 2 Weeks)`            = "No",
    `Chest Pain (in Last 2 Weeks)`       = "No",
    `Night Sweats (in Last 2 Weeks)`     = "No",
    `Fever (in Last 2 Weeks)`            = "No",
    `Loss of Weight (in Last 3 Months)`  = "No",
    `Blood in Sputum (in Last 6 Months)` = "No"
  )
  base[names(list(...))] <- list(...)
  as.data.frame(base, check.names = FALSE, stringsAsFactors = FALSE)
}

flags_for <- function(...) suppressMessages(compute_logic_flags(raw_row(...), quiet = TRUE))

test_that("[13A] MB+ is Yes on a positive at any sputum timepoint", {
  expect_equal(flags_for(`Sputum Result(Same Day)`  = "Positive")$`MB+`, "Yes")
  expect_equal(flags_for(`Sputum Result(Next Day)`  = "MTB Positive")$`MB+`, "Yes")
  expect_equal(flags_for(`Sputum Result(Other Day)` = "positive")$`MB+`, "Yes")
  expect_equal(flags_for(`Sputum Result(Same Day)`  = "Negative")$`MB+`, "No")
})

test_that("[13A] MB+ is blank, not No, when there is no camp record", {
  # The distinction matters: "No" asserts a negative result, blank asserts
  # nothing was recorded at all.
  expect_equal(flags_for(`Camp ID` = NA)$`MB+`, "")
  expect_equal(flags_for(`Camp ID` = "")$`MB+`, "")
})

test_that("[13A] a molecular diagnosis basis also counts as MB+", {
  expect_equal(flags_for(`Sputum Result(Same Day)` = "Negative",
                         DiagnosisBasis = "CBNAAT")$`MB+`, "Yes")
  expect_equal(flags_for(DiagnosisBasis = "Truenat")$`MB+`, "Yes")
})

test_that("[13H] Symptomatic follows Deeptek's Symptoms category", {
  expect_true(flags_for(Symptoms = "Symptomatic only")$Symptomatic)
  expect_true(flags_for(Symptoms = "Symptomatic and Vulnerable")$Symptomatic)
  expect_false(flags_for(Symptoms = "Vulnerable only")$Symptomatic)
  expect_false(flags_for(Symptoms = "None")$Symptomatic)
})

test_that("[13G] TB is microbiological OR clinical confirmation", {
  expect_true(flags_for(`Sputum Result(Same Day)` = "Positive")$TB)
  expect_true(flags_for(`TB Confirmed by Clinician` = "Yes")$TB)
  expect_false(flags_for(`TB Confirmed by Clinician` = "No")$TB)
})

test_that("[13R] sputum eligibility is symptomatic OR a TB-suggestive X-ray", {
  expect_equal(flags_for(Symptoms = "Symptomatic only")$`Eligible for sputum`, "Yes")
  expect_equal(flags_for(`Genki Edge Result` = "TB Related Abnormalities")$`Eligible for sputum`, "Yes")
  expect_equal(flags_for()$`Eligible for sputum`, "No")
})

test_that("[13L] the CXR x symptom cross-tabs are mutually exclusive", {
  f <- flags_for(`Genki Edge Result` = "TB Related Abnormalities",
                 Symptoms = "Symptomatic only")
  expect_true(f$`CXR TB S+`)
  expect_false(f$`CXR TB S-`)
  expect_false(f$`CXR normal S+`)
  expect_false(f$`CXR OCA S+`)

  g <- flags_for(`Genki Edge Result` = "Other Chest Related Abnormalities")
  expect_true(g$`CXR OCA S-`)
  expect_false(g$`CXR OCA S+`)
})

test_that("[13L] 'Beneficiary ID not present' counts as a normal X-ray", {
  # Preserved from the Excel sheet. Surprising, but changing it would move
  # published figures, which is a separate decision from porting the logic.
  f <- flags_for(`Genki Edge Result` = "Beneficiary ID not present")
  expect_true(f$`CXR normal S-`)
})

test_that("[13O] vulnerability covers comorbidity, low BMI and high blood sugar", {
  expect_true(flags_for(`(Common) Diabetes` = "Yes")$`Vulnerable Flag`)
  expect_true(flags_for(`(Social) Miner` = "yes")$`Vulnerable Flag`)
  expect_true(flags_for(BMI = "17")$`Vulnerable Flag`)
  expect_true(flags_for(`Blood Sugar (mg/dL)` = "180")$`Vulnerable Flag`)
  expect_false(flags_for()$`Vulnerable Flag`)
})

test_that("[13O] a BMI of zero is missing data, not underweight", {
  # The legacy formula guards with BMI > 0 for exactly this reason.
  expect_false(flags_for(BMI = "0")$`Vulnerable Flag`)
})

test_that("[13J] spirometry is not done when the result is LTFU", {
  expect_true(flags_for(`Chronic Respiratory Diseases` = "COPD")$`Spiro done`)
  expect_false(flags_for(`Chronic Respiratory Diseases` = "LTFU")$`Spiro done`)
  expect_false(flags_for(`Chronic Respiratory Diseases` = "")$`Spiro done`)
})

test_that("[13T] the vulnerability category combines both flags", {
  expect_equal(flags_for(Symptoms = "Symptomatic only",
                         `(Common) Diabetes` = "Yes")$Vulnerability,
               "Symptomatic and Vulnerable")
  expect_equal(flags_for(Symptoms = "Symptomatic only")$Vulnerability, "Symptomatic only")
  expect_equal(flags_for(`(Common) Diabetes` = "Yes")$Vulnerability, "Vulnerable only")
  expect_equal(flags_for()$Vulnerability, "None")
})

test_that("a missing required column is reported by name, not guessed around", {
  df <- raw_row()
  df$`Genki Edge Result` <- NULL
  expect_error(compute_logic_flags(df, quiet = TRUE), "Genki Edge Result")
})

test_that("headers are matched despite RIS Hub's inconsistent qualifiers", {
  # The export ships "Cough" but "Chest Pain (in Last 2 Weeks)". Both spellings
  # must resolve, or the symptom flag silently loses a symptom.
  df <- raw_row()
  names(df)[names(df) == "Cough (in Last 2 Weeks)"] <- "Cough"
  f <- suppressMessages(compute_logic_flags(df, quiet = TRUE))
  expect_false(f$`Symptom Flag`)

  df$Cough <- "Yes"
  f2 <- suppressMessages(compute_logic_flags(df, quiet = TRUE))
  expect_true(f2$`Symptom Flag`)
})

test_that("a Logic sheet is recognised so its flags are not recomputed", {
  bundle <- test_bundle()
  expect_true(has_logic_flags(bundle$ris$logic))
  expect_false(has_logic_flags(raw_row()))
})

test_that("computed columns win a schema tie against raw columns", {
  # "sputum collected" matches both the computed aggregate and the raw
  # per-timepoint column. Without the preference, the legacy index would win and
  # n_sp_coll would count same-day collections only.
  f <- flags_for(`Sputum Collected(Same Day)` = "Collected")
  res <- resolve_schema(f, prefer = attr(f, "computed_columns"))
  idx <- res$index$sputum_collected
  expect_equal(colnames(f)[idx], "Sputum Collected")
})

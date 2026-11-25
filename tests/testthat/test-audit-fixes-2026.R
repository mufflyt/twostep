# ==============================================================================
# Adversarial regression tests for the six audit fixes (2026-08 audit).
# Each block is written to fail if the original silent-coercion bug returns.
# ==============================================================================
suppressWarnings(suppressMessages(library(testthat)))
.root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION") | rprojroot::is_git_root)
source(file.path(.root, "R", "study_join_accounting.R"))
source(file.path(.root, "R", "desjardins7_e2sfca.R"))
source(file.path(.root, "R", "generate_bivariate_choropleth.R"))
source(file.path(.root, "tests", "testthat", "helper-e2sfca.R"))
ms_env <- new.env(parent = globalenv())
sys.source(file.path(.root, "scripts", "manuscript_catalog",
                     "build_multisite_e2sfca_weights.R"), envir = ms_env)

script_text <- function(p) paste(readLines(file.path(.root, p), warn = FALSE),
                                 collapse = "\n")

# --- Fix 1: run_2sfca.R vector path must not zero-fill NA population ------------
test_that("run_2sfca.R no longer masks NA female_pop before the fail-closed engine", {
  txt <- script_text("scripts/run_2sfca.R")
  expect_false(grepl("female_pop\\[is\\.na", txt))
  expect_false(grepl("na_pop_policy\\s*=\\s*[\"']zero", txt))
  expect_true(grepl("compute_e2sfca\\(", txt))
  expect_true(grepl("attach_e2sfca_population", txt))
})

test_that("compute_e2sfca still refuses NA population (the guard fix 1 relies on)", {
  fx <- make_fixture(11, n_prov = 2, n_tract = 3)
  fx$tract_pop$female_pop[1] <- NA
  expect_error(compute_e2sfca(fx$overlap, fx$tract_pop, fx$supply), "NA")
})

# --- Fix 2: fail-closed denominator alignment ----------------------------------
test_that("align_denominator_to_reference is fail-closed in both directions", {
  ref <- data.frame(GEOID = c("a", "b", "c"), stringsAsFactors = FALSE)

  # Missing reference key: unknown demand is not zero.
  den_missing <- data.frame(GEOID = c("a", "b"), pop = c(1, 2))
  expect_error(align_denominator_to_reference(den_missing, ref, by = "GEOID"),
               "no denominator")

  # Extra denominator key: unmatched population must not be dropped silently.
  den_extra <- data.frame(GEOID = c("a", "b", "c", "d"), pop = 1:4)
  expect_error(align_denominator_to_reference(den_extra, ref, by = "GEOID"),
               "outside the reference")
  ok_extra <- align_denominator_to_reference(den_extra, ref, by = "GEOID",
                                             allow_extra = TRUE)
  expect_equal(ok_extra$GEOID, c("a", "b", "c"))

  # Duplicated keys on either side are ambiguous joins.
  den_dup <- data.frame(GEOID = c("a", "a", "b", "c"), pop = 1:4)
  expect_error(align_denominator_to_reference(den_dup, ref, by = "GEOID"),
               "duplicated")
  ref_dup <- data.frame(GEOID = c("a", "a", "b", "c"), stringsAsFactors = FALSE)
  den_ok <- data.frame(GEOID = c("a", "b", "c"), pop = 1:3)
  expect_error(align_denominator_to_reference(den_ok, ref_dup, by = "GEOID"),
               "duplicated")

  # NA key and NA complete column are both refused.
  den_na_key <- data.frame(GEOID = c("a", NA, "c"), pop = 1:3)
  expect_error(align_denominator_to_reference(den_na_key, ref, by = "GEOID"), "NA")
  den_na_pop <- data.frame(GEOID = c("a", "b", "c"), pop = c(1, NA, 3))
  expect_error(align_denominator_to_reference(den_na_pop, ref, by = "GEOID",
                                              complete_cols = "pop"), "NA")

  # Success path returns reference order with an audit attribute.
  den <- data.frame(GEOID = c("c", "a", "b"), pop = c(30, 10, 20))
  out <- align_denominator_to_reference(den, ref, by = "GEOID")
  expect_equal(out$GEOID, c("a", "b", "c"))
  expect_equal(out$pop, c(10, 20, 30))
  expect_true(!is.null(attr(out, "join_audit")))
})

test_that("ported denominator scripts use the fail-closed aligner, not match()+zero-fill", {
  files <- c(
    "scripts/desjardins7/00_build_data.R",
    "scripts/desjardins7/06_tract_e2sfca_denominator.R",
    "scripts/desjardins7/09_surface_recovery.R",
    "scripts/desjardins7/13_decay_weight_sensitivity.R",
    "scripts/seam_test_subgroup.R",
    "scripts/cell_level_zero_access_2020.R",
    "scripts/sensitivity_e2sfca_2020.R",
    "scripts/spatial_outcomes_2020.R")
  for (f in files) {
    txt <- script_text(f)
    expect_true(grepl("align_denominator_to_reference", txt, fixed = TRUE),
                info = f)
    expect_false(grepl("den\\[match", txt), info = f)
  }
  for (f in c("scripts/desjardins7/00_build_data.R",
             "scripts/desjardins7/10_rebuild_workforce_recovery.R",
             "scripts/seam_test_subgroup.R",
             "scripts/cell_level_zero_access_2020.R")) {
    txt <- script_text(f)
    expect_false(grepl("rurality\\[is\\.na", txt), info = f)
  }
})

# --- Fix 3: Desjardins7 scripts 06/09/13 run on the tested SSOT module ------------
test_that("desjardins7 06/09/13 source desjardins7_e2sfca.R and use dj7 helpers", {
  for (f in c("scripts/desjardins7/06_tract_e2sfca_denominator.R",
              "scripts/desjardins7/09_surface_recovery.R",
              "scripts/desjardins7/13_decay_weight_sensitivity.R")) {
    txt <- script_text(f)
    expect_true(grepl("desjardins7_e2sfca.R", txt, fixed = TRUE), info = f)
    expect_true(grepl("dj7_tract_access|dj7_weighted_outcomes|dj7_incr_weights", txt),
                info = f)
    expect_true(grepl("dj7_tract_access", txt, fixed = TRUE), info = f)
  }
})

# --- dj7_weighted_outcomes: unreached tracts are zero, NA weights are not --------
test_that("dj7_weighted_outcomes counts unreached tracts as zero access", {
  acc <- data.frame(GEOID = c("A", "B"), A = c(0.1, 0.2))
  den <- data.frame(GEOID = c("A", "B", "C"), total_f = c(10, 20, 30),
                    rurality = c("Metropolitan", "Rural", NA))
  out <- dj7_weighted_outcomes(acc, den, weight_col = "total_f",
                               rurality_col = "rurality", scale = 1)
  expect_equal(out$mean, (0.1 * 10 + 0.2 * 20) / 60)
  expect_equal(out$no_access, 50)                 # C holds 30 of 60 women
  expect_equal(out$metro, 0.1)
  expect_equal(out$rural, 0.2)
  expect_equal(out$ratio, 0.5)
  expect_equal(out$n_tracts, 3L)
  expect_equal(out$n_reached, 2L)
  expect_equal(out$n_uncoded_rurality, 1L)
})

test_that("dj7_weighted_outcomes refuses NA/duplicate denominator and access keys", {
  acc <- data.frame(GEOID = c("A", "B"), A = c(0.1, 0.2))
  den <- data.frame(GEOID = c("A", "B"), total_f = c(10, NA))
  expect_error(dj7_weighted_outcomes(acc, den), "NA")
  den_dup <- data.frame(GEOID = c("A", "A"), total_f = c(10, 20))
  expect_error(dj7_weighted_outcomes(acc, den_dup), "unique")
  acc_dup <- data.frame(GEOID = c("A", "A"), A = c(0.1, 0.2))
  den_ok <- data.frame(GEOID = c("A", "B"), total_f = c(10, 20))
  expect_error(dj7_weighted_outcomes(acc_dup, den_ok), "unique")
  acc_na <- data.frame(GEOID = "A", A = NA_real_)
  expect_error(dj7_weighted_outcomes(acc_na, den_ok), "finite")
})

test_that("dj7_tract_access fails closed when membership demand keys are missing", {
  membership <- list(`30` = data.frame(coord_id = "P1", GEOID = "T1",
                                       stringsAsFactors = FALSE))
  supply <- c(P1 = 1)
  dvec <- c(T2 = 10)                               # T1 demand absent, not zero
  expect_error(dj7_tract_access(membership, supply, dvec), "dvec")
})

# --- Fix 4: GO stratification scripts use the accessibility SSOT ------------------
test_that("stratify_go_* scripts use SSOT stratification and join accounting", {
  for (f in c("scripts/stratify_go_2020_access.R",
              "scripts/stratify_go_allyears_access.R")) {
    txt <- script_text(f)
    expect_true(grepl("accessibility_stratification.R", txt, fixed = TRUE), info = f)
    expect_true(grepl("study_join_accounting.R", txt, fixed = TRUE), info = f)
    expect_true(grepl("acs_year_of|tract_vintage_of|rurality_from_ruca", txt), info = f)
    expect_true(grepl("assert_state_join_loss|partition_unknown_access", txt), info = f)
    expect_false(grepl("d\\$access\\[is\\.na", txt), info = f)
  }
})

# --- Fix 5: classify_bivariate preserves NA as unclassified ----------------------
test_that("classify_bivariate keeps NA out of the lowest bin and never emits NA-*", {
  d <- data.frame(x = c(1, 2, 3, NA, 5), y = c(5, 4, 3, 2, NA))
  o <- classify_bivariate(d, "x", "y", n_bins = 2, method = "equal")
  expect_true(is.na(o$bivar_class[4]))
  expect_true(is.na(o$bivar_class[5]))
  expect_false(any(o$bivar_class %in% c("NA-1", "1-NA", "NA-NA")))
  expect_false(any(is.na(o$bivar_class[1:3])))
})

# --- Fix 6: multisite NPI/ZIP canonicalization ------------------------------------
test_that("multisite helpers canonicalize NPI and ZIP to the ecosystem convention", {
  expect_equal(suppressMessages(ms_env$canonicalize_npi("123-456-7890")), "1234567890")
  expect_equal(suppressMessages(ms_env$canonicalize_npi(123456789)), "0123456789")
  expect_true(is.na(suppressMessages(ms_env$canonicalize_npi("12A4567890"))))

  expect_equal(ms_env$normalize_zip(c("1234", "12345-6789", " 00601 ", "7001, 90210")),
               c("01234", "12345", "00601", "07001"))
  expect_true(is.na(ms_env$normalize_zip("ABC")))
})

test_that("multisite weight builder routes NPIs through mufflyaccess::canon_npi", {
  txt <- script_text("scripts/manuscript_catalog/build_multisite_e2sfca_weights.R")
  expect_true(grepl("mufflyaccess::canon_npi", txt, fixed = TRUE))
  expect_true(grepl("canonicalize_npi", txt, fixed = TRUE))
  expect_true(grepl("normalize_zip", txt, fixed = TRUE))
})

# --- Additional same-pattern scripts found in the follow-up sweep -----------------
test_that("inferential_stats_access.R uses accounted joins and never zero-fills access/ACS", {
  txt <- script_text("scripts/inferential_stats_access.R")
  expect_true(grepl("study_join_accounting.R", txt, fixed = TRUE))
  expect_true(grepl("accessibility_stratification.R", txt, fixed = TRUE))
  expect_true(grepl("assert_state_join_loss", txt, fixed = TRUE))
  expect_true(grepl("partition_unknown_access", txt, fixed = TRUE))
  expect_true(grepl("rurality_from_ruca", txt, fixed = TRUE))
  expect_false(grepl("inner_join\\(ruca", txt))
  expect_false(grepl("d\\$access\\[is\\.na", txt))
  expect_false(grepl("x\\[is\\.na\\(x\\)\\]\\s*<-\\s*0", txt))
  expect_false(grepl("s\\[is\\.na\\(s\\)\\]\\s*<-\\s*0", txt))
})

test_that("analyze_ct_correction.R aligns cells fail-closed and refuses NA population", {
  txt <- script_text("scripts/analyze_ct_correction.R")
  expect_true(grepl("study_join_accounting.R", txt, fixed = TRUE))
  expect_true(grepl("align_denominator_to_reference", txt, fixed = TRUE))
  expect_false(grepl("co\\[match\\(fr\\$GEOID", txt))
  expect_true(grepl("anyNA\\(P\\)", txt))
})

test_that("desjardins7 00 no longer zero-fills NA access before quintiles", {
  txt <- script_text("scripts/desjardins7/00_build_data.R")
  expect_false(grepl("d\\$access\\[is\\.na", txt))
  expect_true(grepl("is\\.na\\(access\\)", txt))
})

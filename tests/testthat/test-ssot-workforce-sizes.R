# ==============================================================================
# SSOT guard: the seven 2020 subspecialty workforce sizes.
#
# These are HEADLINE manuscript numbers (Table 1 + Results prose). The canonical
# quantity is the frozen run's 2020 supply per subspecialty, which by the E2SFCA
# conservation property is derivable from the national summary:
#   n_providers = round(mean_pop_weighted_per100k * acs_pop_source / 1e5).
# The manuscript consumes a staged CSV (manuscript/data/workforce_counts_2020.csv);
# e2sfca_workforce_counts(national_tbl=) now cross-checks that CSV against the
# run-derived counts and fails loudly on drift. This guard pins the derivation, the
# cross-check, and that the manuscript prose reads the values (spec_wk) rather than
# hardcoding them.
# ==============================================================================
library(testthat)

root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION"))
source(file.path(root, "scripts", "manuscript_e2sfca_values.R"))

nat <- load_e2sfca_national_summary(e2sfca_run_dir(root = root))
csv <- readr::read_csv(file.path(root, "manuscript", "data",
                                 "workforce_counts_2020.csv"), show_col_types = FALSE)

test_that("run-derived 2020 workforce counts match the staged CSV", {
  d <- e2sfca_workforce_from_run(nat)
  m <- merge(csv, d, by = "subspecialty")
  expect_identical(nrow(m), 7L)
  expect_true(all(abs(m$n_providers - m$n_providers_derived) <= 1L),
              info = paste(m$subspecialty, m$n_providers, m$n_providers_derived,
                           collapse = " | "))
})

test_that("e2sfca_workforce_counts cross-check passes on the real staged CSV", {
  wt <- e2sfca_workforce_counts(
    path = file.path(root, "manuscript", "data", "workforce_counts_2020.csv"),
    national_tbl = nat)
  expect_identical(nrow(wt), 7L)
})

test_that("the cross-check FAILS loudly when the staged CSV drifts from the run", {
  # Adversarial: perturb one count by 100 and confirm the validator stops.
  tmp <- file.path(tempdir(), "wf-drift.csv")
  bad <- csv; bad$n_providers[bad$subspecialty == "GO"] <-
    bad$n_providers[bad$subspecialty == "GO"] + 100L
  readr::write_csv(bad, tmp)
  expect_error(e2sfca_workforce_counts(path = tmp, national_tbl = nat),
               "disagrees with the frozen run")
})

test_that("the manuscript reads workforce counts via spec_wk(), not hardcoded numbers", {
  rmd <- readLines(file.path(root, "manuscript",
                             "e2sfca_accessibility_manuscript.Rmd"), warn = FALSE)
  # every per-subspecialty count in prose goes through spec_wk(<CODE>)
  for (code in c("MFM", "GO", "REI", "FPMRS", "MIGS", "PAG", "CFP"))
    expect_true(any(grepl(sprintf("spec_wk(\"%s\")", code), rmd, fixed = TRUE)),
                info = paste("no spec_wk() for", code))
  # no bare workforce integer literal from the CSV appears in the prose
  for (n in csv$n_providers)
    expect_false(any(grepl(sprintf("\\b%d\\b", n), rmd) &
                     !grepl("spec_wk|workforce_tbl|r ", rmd)),
                 info = paste("possible hardcoded count", n))
})

# ==============================================================================
# SSOT guard: the non-contiguous (non-CONUS) FIPS exclusion set.
#
# Canonical: NON_CONUS_FIPS in scripts/manuscript_e2sfca_values.R, DERIVED as
# setdiff(US_STATE_TERRITORY_FIPS, CONUS_STATE_FIPS) — never hardcoded independently,
# so the exclusion set and the CONUS inclusion set are exact complements and cannot
# drift apart. Several scripts exclude non-contiguous areas with a literal
# c("02","15","60","66","69","72","78"); this guard pins the derivation, the
# partition, and that every such literal equals the canonical set.
# ==============================================================================
library(testthat)

root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION"))
source(file.path(root, "scripts", "manuscript_e2sfca_values.R"))

EXPECTED_NON <- c("02", "15", "60", "66", "69", "72", "78")  # AK, HI, AS, GU, MP, PR, VI

test_that("NON_CONUS_FIPS is AK, HI + 5 territories, derived as the CONUS complement", {
  expect_setequal(NON_CONUS_FIPS, EXPECTED_NON)
  expect_length(NON_CONUS_FIPS, 7L)
  # it is literally the set difference (not an independent hardcode)
  expect_setequal(NON_CONUS_FIPS,
                  setdiff(US_STATE_TERRITORY_FIPS, CONUS_STATE_FIPS))
})

test_that("CONUS and non-CONUS partition the 56-code US universe", {
  expect_length(US_STATE_TERRITORY_FIPS, 56L)
  expect_length(intersect(CONUS_STATE_FIPS, NON_CONUS_FIPS), 0L)   # disjoint
  expect_setequal(union(CONUS_STATE_FIPS, NON_CONUS_FIPS),
                  US_STATE_TERRITORY_FIPS)                          # exhaustive
})

test_that("every non-CONUS literal in the repo equals the canonical set", {
  files <- c(
    list.files(c(file.path(root, "R"), file.path(root, "scripts")),
               pattern = "[.]R$", full.names = TRUE, recursive = TRUE))
  offenders <- character(0)
  for (f in files) {
    txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
    blocks <- regmatches(txt, gregexpr('c\\(\\s*"0?2"[^)]*\\)', txt))[[1]]
    for (b in blocks) {
      toks <- gsub('"', "", regmatches(b, gregexpr('"[0-9]{2}"', b))[[1]])
      # a non-CONUS exclusion literal = one that contains AK(02) + HI(15) + a territory
      if (all(c("02", "15") %in% toks) && any(c("72", "78", "66") %in% toks)) {
        if (!setequal(toks, EXPECTED_NON))
          offenders <- c(offenders, sprintf("%s: %s", basename(f), b))
      }
    }
  }
  expect_true(length(offenders) == 0,
              info = paste("non-CONUS literals that drift:",
                           paste(offenders, collapse = " | ")))
})

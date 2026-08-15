# The compute_e2sfca() -> SPAR seam for the scenario accessibility layer.
# urps_e2sfca_spar_summary() operates only on the returned data.frames, so its
# SPAR math is verifiable with a synthetic $access frame -- no sf/terra/dplyr.
# A second block runs the REAL compute_e2sfca() when dplyr is available, proving
# the wiring end to end; it skips cleanly otherwise.

# Same omission as test-urps-accessibility-scenarios.R: the module under test was
# never sourced, so all 4 blocks errored with "could not find function
# urps_e2sfca_spar_summary" and the SPAR seam was untested.
root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION"))
source(file.path(root, "R", "urps_accessibility_scenarios.R"))

# analytic fixture from test-e2sfca-m2sfca-gaussian.R: provider p, near+far tracts,
# supply 1, weights (30=1.0, 60=0.5) -> access near = 1/150, far = 0.5/150.
# access_scaled = access * 1e5 -> near 666.667, far 333.333.
res_analytic <- list(access = data.frame(
  GEOID = c("near", "far"),
  access_scaled = c(1/150, 0.5/150) * 1e5,
  stringsAsFactors = FALSE))
pop2 <- data.frame(GEOID = c("near", "far"), female_pop = c(100, 100),
                   stringsAsFactors = FALSE)

test_that("SPAR summary: national mean is 1.00 and mean access is pop-weighted", {
  s <- urps_e2sfca_spar_summary(res_analytic, pop2)
  expect_equal(s$spar_national_mean, 1, tolerance = 1e-9)      # 1.00 by construction
  expect_equal(s$mean_access_per100k, 500, tolerance = 1e-9)   # (666.7+333.3)/2
  expect_equal(s$low_access_pop_share, 0)                      # SPARs 1.33 / 0.67, none < 0.5
  expect_equal(s$zero_access_pop_share, 0)
  expect_equal(s$n_reached_tracts, 2L)
})

test_that("unreached tracts (absent from $access) count as zero access", {
  pop3 <- rbind(pop2, data.frame(GEOID = "iso", female_pop = 100))  # not in $access
  s <- urps_e2sfca_spar_summary(res_analytic, pop3)
  expect_equal(s$spar_national_mean, 1, tolerance = 1e-9)      # still 1.00
  expect_equal(s$zero_access_pop_share, 1/3, tolerance = 1e-9) # the isolated third
  expect_gte(s$low_access_pop_share, 1/3 - 1e-9)              # zero-access is also low
  expect_equal(s$n_reached_tracts, 2L)
})

test_that("SPAR summary validates its inputs", {
  expect_error(urps_e2sfca_spar_summary(data.frame(GEOID = "a"), pop2),
               "compute_e2sfca")
  expect_error(urps_e2sfca_spar_summary(res_analytic, data.frame(GEOID = "near")),
               "female_pop")
})

# ---- real-engine integration: proves the compute_e2sfca() -> SPAR path --------
test_that("the real compute_e2sfca() feeds urps_e2sfca_spar_summary() to a valid SPAR", {
  skip_if_not_installed("dplyr")
  engine <- testthat::test_path("..", "..", "R", "two_step_floating_catchment.R")
  skip_if(!file.exists(engine), "E2SFCA engine source not found")
  suppressWarnings(suppressMessages(sys.source(normalizePath(engine), envir = environment())))
  skip_if(!exists("compute_e2sfca"), "compute_e2sfca not available")

  ov  <- dplyr::tibble(coord_id = "p", band = c(30L, 60L, 60L),
                       GEOID = c("near", "near", "far"), overlap_fraction = 1)
  pop <- dplyr::tibble(GEOID = c("near", "far"), female_pop = c(100, 100))
  sup <- dplyr::tibble(coord_id = "p", supply = 1)
  res <- compute_e2sfca(ov, pop, sup, weights = c("30" = 1.0, "60" = 0.5))

  s <- urps_e2sfca_spar_summary(res, as.data.frame(pop))
  expect_equal(s$spar_national_mean, 1, tolerance = 1e-9)
  expect_gt(s$mean_access_per100k, 0)
  # doubling supply doubles per-capita access but leaves SPAR (relative) at mean 1
  res2 <- compute_e2sfca(ov, pop, dplyr::tibble(coord_id = "p", supply = 2),
                         weights = c("30" = 1.0, "60" = 0.5))
  s2 <- urps_e2sfca_spar_summary(res2, as.data.frame(pop))
  expect_gt(s2$mean_access_per100k, s$mean_access_per100k)
  expect_equal(s2$spar_national_mean, 1, tolerance = 1e-9)
})

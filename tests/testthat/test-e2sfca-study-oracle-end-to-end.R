# =============================================================================
# End-to-end study oracle: raw inputs -> reported accessibility.
# =============================================================================
# Every other scientific suite here tests the EQUATION. This one tests the glue
# around it, because the larger risk in a real study is not a wrong formula --
# it is a correct formula fed the wrong rows: a join on the wrong key, a
# duplicated provider-tract edge, a denominator built from the wrong year, an
# unmatched tract silently dropped, an aggregation that forgets to weight by
# population. All of those produce entirely believable numbers.
#
# The fixture enters at the EARLIEST practical contract -- provider cohort and
# coordinate map, isochrone and tract GEOMETRY -- so the joins, the subspecialty
# and year filters, catchment construction and area-overlap arithmetic all run.
#
# The oracle in study_oracle_expected.json was derived by hand from the E2SFCA
# equations in an independent implementation. No twostep code produced any
# number in it, and no expected value is regenerated during these tests.
suppressWarnings(suppressMessages(library(testthat)))
suppressWarnings(suppressMessages(library(sf)))
.root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION") | rprojroot::is_git_root)
source(file.path(.root, "R", "two_step_floating_catchment.R"))
source(file.path(.root, "tests", "fixtures", "study_oracle.R"))
ORACLE <- jsonlite::fromJSON(file.path(.root, "tests", "fixtures",
                                       "study_oracle_expected.json"),
                             simplifyVector = FALSE)

TOL <- 1e-12
A_TRACTS <- c("A01", "A02", "A03", "A04", "A05")

# Run the WHOLE pipeline from raw inputs. Optional hooks let the adversarial
# tests perturb an input without reaching inside the pipeline.
run_study <- function(cohort = study_cohort(), ycm = study_year_coord_map(),
                      iso = study_iso_sf(), tracts = study_tracts_sf(),
                      pop = study_tract_pop(), W = STUDY_W,
                      year = 2020L, subspec = "GO", ...) {
  supply  <- compute_provider_supply(ycm, cohort, subspec, year)
  overlap <- compute_band_tract_overlap(iso, tracts, verbose = FALSE)
  res     <- compute_e2sfca(overlap, pop, supply, weights = W, ...)
  list(supply = as.data.frame(supply), overlap = as.data.frame(overlap),
       res = res, access = as.data.frame(res$access),
       ratios = as.data.frame(res$provider_ratios))
}

acc_of <- function(r, g) r$access$access[match(g, r$access$GEOID)]
# The algebraic (zero-filled) form, for invariance comparisons where an NA at an
# unreached tract would otherwise poison an otherwise exact equality.
accm_of <- function(r, g) r$access$access_math[match(g, r$access$GEOID)]
pw_mean <- function(r, g, pop = study_tract_pop()) {
  a <- acc_of(r, g); p <- pop$female_pop[match(g, pop$GEOID)]
  sum(a * p) / sum(p)
}

# =============================================================================
# 3. STAGE-BY-STAGE RECONCILIATION
# =============================================================================
# Each stage is checked separately so a disagreement localises to the boundary
# where it first appears, rather than surfacing only as a wrong final number.
S <- run_study()

test_that("STAGE 1 supply: cohort and coordinate-map joins select the right physicians", {
  exp_sup <- ORACLE$stage_1_supply
  for (j in names(exp_sup))
    expect_equal(S$supply$supply[S$supply$coord_id == j], exp_sup[[j]],
                 info = paste("supply at", j))
  # The fixture deliberately contains rows that must NOT contribute: a physician
  # in another subspecialty, one in another analysis year, and a placeholder
  # location with NA match_source. If any leaked in, a count above would be high.
  expect_setequal(S$supply$coord_id, names(exp_sup))
})

test_that("STAGE 2 overlap: catchment membership and area fractions come from geometry", {
  exp_ov <- ORACLE$stage_2_overlap_fraction
  n_expected <- sum(vapply(exp_ov, function(b) sum(lengths(b)), integer(1)))
  expect_equal(nrow(S$overlap), n_expected)
  for (j in names(exp_ov)) for (b in names(exp_ov[[j]])) for (g in names(exp_ov[[j]][[b]])) {
    got <- S$overlap$overlap_fraction[S$overlap$coord_id == j &
                                        S$overlap$band == as.integer(b) &
                                        S$overlap$GEOID == g]
    expect_equal(got, exp_ov[[j]][[b]][[g]], tolerance = 1e-9,
                 info = sprintf("overlap %s band %s tract %s", j, b, g))
  }
  # A05 is reachable by nobody and must appear in NO overlap row.
  expect_false("A05" %in% S$overlap$GEOID)
})

test_that("STAGE 3 weighted demand matches the independent derivation", {
  for (j in names(ORACLE$stage_3_weighted_demand))
    expect_equal(S$ratios$weighted_demand[S$ratios$coord_id == j],
                 ORACLE$stage_3_weighted_demand[[j]], tolerance = 1e-9,
                 info = paste("demand at", j))
})

test_that("STAGE 4 provider ratios match, and a no-demand provider is audited not divided", {
  for (j in names(ORACLE$stage_4_provider_ratio))
    expect_equal(S$ratios$ratio_for_surface[S$ratios$coord_id == j],
                 ORACLE$stage_4_provider_ratio[[j]], tolerance = TOL,
                 info = paste("ratio at", j))
  expect_setequal(unlist(ORACLE$audit_expectations$zero_demand_coord_ids),
                  S$res$audit$zero_demand_coord_ids)
  expect_equal(S$res$audit$supply_zero_demand,
               ORACLE$audit_expectations$excluded_supply)
})

test_that("STAGE 5 tract accessibility matches, and unreached is NA rather than zero", {
  # Semantics per #10: `access` is the scientific value and is NA outside every
  # modelled catchment, because such a tract has no MEASURED accessibility --
  # distinct from a reached tract that scores zero. `access_math` keeps the
  # zero-filled algebraic form.
  for (g in names(ORACLE$stage_5_tract_access_math))
    expect_equal(S$access$access_math[match(g, S$access$GEOID)],
                 ORACLE$stage_5_tract_access_math[[g]], tolerance = TOL,
                 info = paste("access_math at", g))
  for (g in names(ORACLE$stage_5_reached))
    expect_equal(S$access$reached[match(g, S$access$GEOID)],
                 ORACLE$stage_5_reached[[g]], info = paste("reached at", g))

  # An unreachable tract must be PRESENT, never dropped -- dropping it would
  # silently shrink every denominator built from this output -- and must be NA,
  # not a measured zero.
  expect_true(all(A_TRACTS %in% S$access$GEOID))
  expect_true(is.na(acc_of(S, "A05")))
  expect_false(S$access$reached[match("A05", S$access$GEOID)])
  expect_equal(S$access$coverage_status[match("A05", S$access$GEOID)],
               ORACLE$stage_5_coverage_status$A05)

  # A04 IS reached -- by PA3, whose supply is excluded for having no demand --
  # so it scores a real zero and must NOT be conflated with A05.
  expect_equal(acc_of(S, "A04"), 0)
  expect_true(S$access$reached[match("A04", S$access$GEOID)])
})

test_that("STAGE 6 reporting: conservation holds and the summary is population-weighted", {
  e <- ORACLE$stage_6_component_A
  pop <- study_tract_pop()
  # Conservation is an ALGEBRAIC identity, so it is stated against access_math:
  # the unreached tract contributes 0 to the algebra and NA to the report.
  a <- S$access$access_math[match(A_TRACTS, S$access$GEOID)]
  p <- pop$female_pop[match(A_TRACTS, pop$GEOID)]
  expect_equal(sum(a * p), e$sum_pop_times_access, tolerance = 1e-9)
  expect_equal(sum(a * p), e$usable_supply, tolerance = 1e-9)   # exact identity
  expect_equal(sum(a * p) / sum(p), e$population_weighted_mean_access, tolerance = TOL)
  # An UNWEIGHTED mean is the classic wrong aggregation and must differ.
  expect_false(isTRUE(all.equal(mean(a), e$population_weighted_mean_access,
                                tolerance = 1e-6)))
})

# =============================================================================
# 5. DISCONNECTED-COMPONENT INVARIANCE
# =============================================================================
test_that("a far larger disconnected component cannot move component A", {
  # Component B carries 80,000 people against A's 4,300 and its own provider.
  # Any global normalisation, denominator leakage or group-wise slip would show
  # up here while leaving entirely plausible numbers.
  keep <- function(x, ids) x[x$GEOID %in% ids | (("coord_id" %in% names(x)) &
                                                   !("GEOID" %in% names(x))), , drop = FALSE]
  iso_A    <- study_iso_sf()[!startsWith(study_iso_sf()$coord_id, "PB"), ]
  tracts_A <- study_tracts_sf()[startsWith(study_tracts_sf()$GEOID, "A"), ]
  pop_A    <- study_tract_pop()[startsWith(study_tract_pop()$GEOID, "A"), ]
  ycm_A    <- study_year_coord_map()[!startsWith(study_year_coord_map()$coord_id, "PB"), ]

  alone <- run_study(ycm = ycm_A, iso = iso_A, tracts = tracts_A, pop = pop_A)
  for (g in A_TRACTS)
    expect_equal(acc_of(alone, g), acc_of(S, g), tolerance = TOL,
                 info = paste("component A moved when B was present:", g))
  expect_equal(pw_mean(alone, A_TRACTS, pop_A), pw_mean(S, A_TRACTS), tolerance = TOL)
})

# =============================================================================
# 4. ATTACK THE GLUE AROUND THE CORRECT EQUATION
# =============================================================================
test_that("shuffling every input table independently changes nothing", {
  set.seed(11)
  sh <- function(d) d[sample.int(nrow(d)), , drop = FALSE]
  r <- run_study(cohort = sh(study_cohort()), ycm = sh(study_year_coord_map()),
                 iso = study_iso_sf()[sample.int(nrow(study_iso_sf())), ],
                 tracts = study_tracts_sf()[sample.int(nrow(study_tracts_sf())), ],
                 pop = sh(study_tract_pop()))
  for (g in A_TRACTS) expect_equal(acc_of(r, g), acc_of(S, g), tolerance = TOL)
})

test_that("reversing input order changes nothing", {
  rev_df <- function(d) d[rev(seq_len(nrow(d))), , drop = FALSE]
  r <- run_study(cohort = rev_df(study_cohort()), ycm = rev_df(study_year_coord_map()),
                 iso = study_iso_sf()[rev(seq_len(nrow(study_iso_sf()))), ],
                 tracts = study_tracts_sf()[rev(seq_len(nrow(study_tracts_sf()))), ],
                 pop = rev_df(study_tract_pop()))
  for (g in A_TRACTS) expect_equal(acc_of(r, g), acc_of(S, g), tolerance = TOL)
})

test_that("relabelling tract and provider identifiers changes nothing but the labels", {
  gm <- c(A01="Z1", A02="Z2", A03="Z3", A04="Z4", A05="Z5", B01="Z6", B02="Z7")
  pm <- c(PA1="Q1", PA2="Q2", PA3="Q3", PB1="Q4")
  tr <- study_tracts_sf(); tr$GEOID <- unname(gm[tr$GEOID])
  po <- study_tract_pop(); po$GEOID <- unname(gm[po$GEOID])
  is <- study_iso_sf();    is$coord_id <- unname(pm[is$coord_id])
  ym <- study_year_coord_map(); ym$coord_id <- unname(pm[ym$coord_id])
  r <- run_study(ycm = ym, iso = is, tracts = tr, pop = po)
  for (g in A_TRACTS)
    expect_equal(acc_of(r, unname(gm[g])), acc_of(S, g), tolerance = TOL, info = g)
})

test_that("a duplicated provider-tract edge does not double that provider's reach", {
  # compute_band_tract_overlap sums duplicate geometry then caps at 1, so an
  # accidentally duplicated isochrone row must not inflate the overlap fraction.
  is <- study_iso_sf(); is <- rbind(is, is[is$coord_id == "PA2" & is$drive_time_minutes == 30, ])
  r <- run_study(iso = is)
  expect_equal(r$overlap$overlap_fraction[r$overlap$coord_id == "PA2" &
                                            r$overlap$band == 30], 1.0, tolerance = 1e-9)
  for (g in A_TRACTS) expect_equal(acc_of(r, g), acc_of(S, g), tolerance = TOL, info = g)
})

test_that("FAIL CLOSED: a duplicated tract row is rejected, not silently double-counted", {
  # FOUND BY THIS SUITE. Before the guard, duplicating A02's population row took
  # PA1's Step 1 denominator from 2850 to 4530 -- A02's 1680 counted twice --
  # and quietly UNDERSTATED accessibility everywhere PA1 reaches. dplyr warned
  # about a many-to-many join; nothing acted on it.
  po <- study_tract_pop(); po <- rbind(po, po[po$GEOID == "A02", ])
  expect_error(run_study(pop = po), "duplicate GEOID in tract_pop")
  expect_error(run_study(pop = po), "A02")               # names the offender
  expect_error(run_study(pop = po), "understates accessibility")
})

test_that("FAIL CLOSED: a duplicated supply row is rejected, not silently double-counted", {
  # The same hole in the other direction, and the more dangerous one: before the
  # guard a repeated provider row DOUBLED A01's accessibility, from 0.000702 to
  # 0.001404. Overstating access is the direction that flatters a study.
  sup <- as.data.frame(compute_provider_supply(study_year_coord_map(),
                                               study_cohort(), "GO", 2020L))
  ov  <- compute_band_tract_overlap(study_iso_sf(), study_tracts_sf(), verbose = FALSE)
  expect_error(
    compute_e2sfca(ov, study_tract_pop(), rbind(sup, sup[1, ]), weights = STUDY_W),
    "duplicate coord_id in supply")
  expect_error(
    compute_e2sfca(ov, study_tract_pop(), rbind(sup, sup[1, ]), weights = STUDY_W),
    "OVERSTATES accessibility")
})

test_that("a duplicated physician row does not inflate supply", {
  # supply counts DISTINCT npi, so an exact duplicate row must be absorbed.
  ym <- study_year_coord_map(); ym <- rbind(ym, ym[ym$npi == 101, ])
  r <- run_study(ycm = ym)
  expect_equal(r$supply$supply[r$supply$coord_id == "PA1"], 2)
  for (g in A_TRACTS) expect_equal(acc_of(r, g), acc_of(S, g), tolerance = TOL)
})

test_that("removing one reachable edge changes exactly the tracts it served", {
  is <- study_iso_sf(); is <- is[!(is$coord_id == "PA2"), ]
  r  <- run_study(iso = is)
  expect_lt(acc_of(r, "A02"), acc_of(S, "A02"))          # lost a provider
  expect_equal(acc_of(r, "A01"), acc_of(S, "A01"), tolerance = TOL)  # untouched
  expect_equal(acc_of(r, "A03"), acc_of(S, "A03"), tolerance = TOL)
})

test_that("adding an unreachable provider or an unreachable tract changes nothing", {
  # Unreachable provider, 1000 km away with its own catchment and physicians.
  is <- study_iso_sf()
  far <- is[1, ]; sf::st_geometry(far) <- sf::st_sfc(
    .rect(5e6, 5e6 + 1000, 0, 1000), crs = 5070)
  far$coord_id <- "PFAR"; far$drive_time_minutes <- 30L
  ym <- rbind(study_year_coord_map(),
              data.frame(npi = 999, analysis_year = 2020L, coord_id = "PFAR",
                         match_source = "geo", stringsAsFactors = FALSE))
  co <- rbind(study_cohort(),
              data.frame(npi = 999, subspecialty_normalized = "GO",
                         stringsAsFactors = FALSE))
  r <- run_study(cohort = co, ycm = ym, iso = rbind(is, far))
  for (g in A_TRACTS) expect_equal(acc_of(r, g), acc_of(S, g), tolerance = TOL, info = g)

  # Unreachable tract with a large population.
  tr <- study_tracts_sf()
  extra <- tr[1, ]; sf::st_geometry(extra) <- sf::st_sfc(
    .rect(7e6, 7e6 + 1000, 0, 1000), crs = 5070); extra$GEOID <- "FART"
  po <- rbind(study_tract_pop(),
              data.frame(GEOID = "FART", female_pop = 99999, stringsAsFactors = FALSE))
  r2 <- run_study(tracts = rbind(tr, extra), pop = po)
  for (g in A_TRACTS)
    expect_equal(r2$access$access_math[match(g, r2$access$GEOID)],
                 S$access$access_math[match(g, S$access$GEOID)], tolerance = TOL, info = g)
  # The far tract is outside every catchment, so NA, not a measured zero.
  expect_true(is.na(acc_of(r2, "FART")))
  expect_false(r2$access$reached[match("FART", r2$access$GEOID)])
})

test_that("integer and double population columns agree exactly", {
  po <- study_tract_pop(); po$female_pop <- as.integer(po$female_pop)
  ri <- run_study(pop = po)
  po$female_pop <- as.double(po$female_pop)
  rd <- run_study(pop = po)
  for (g in A_TRACTS) expect_equal(acc_of(ri, g), acc_of(rd, g), tolerance = 1e-15)
})

# =============================================================================
# MISSING POPULATION IS NOT ZERO POPULATION
# =============================================================================
# Policy adopted after this suite showed the old behaviour inflated
# accessibility: a tract whose population is UNKNOWN was treated as empty,
# removing its residents from the Step 1 denominator and raising every affected
# provider's ratio. Accessibility improved because data disappeared.
#
#   record present, value 0   -> valid measurement, proceed
#   record present, value NA  -> unknown, FAIL
#   record absent entirely    -> unmatched join, FAIL
#
test_that("an explicit ZERO population is valid and still proceeds", {
  # A04 carries a literal 0 throughout the fixture and must never be confused
  # with a missing record. This is the case the fail-closed rule must NOT break.
  expect_equal(study_tract_pop()$female_pop[study_tract_pop()$GEOID == "A04"], 0)
  expect_silent(r <- run_study())
  expect_equal(acc_of(S, "A04"), 0)
  expect_true(S$access$reached[match("A04", S$access$GEOID)])
})

test_that("FAIL CLOSED: NA population is refused, not coerced to zero", {
  po <- study_tract_pop(); po$female_pop[po$GEOID == "A02"] <- NA
  expect_error(run_study(pop = po), "NA in population column")
  expect_error(run_study(pop = po), "A02")                  # names the tract
  expect_error(run_study(pop = po), "inflate accessibility") # states the direction
  # The escape hatch exists but must be taken deliberately, never by default.
  sup <- compute_provider_supply(study_year_coord_map(), study_cohort(), "GO", 2020L)
  ov  <- compute_band_tract_overlap(study_iso_sf(), study_tracts_sf(), verbose = FALSE)
  expect_silent(compute_e2sfca(ov, po, sup, weights = STUDY_W, na_pop_policy = "zero"))
})

test_that("FAIL CLOSED: a tract in a catchment with NO population record is refused", {
  po <- study_tract_pop(); po <- po[po$GEOID != "A02", ]    # A02 is reached
  expect_error(run_study(pop = po), "NO population record")
  expect_error(run_study(pop = po), "A02")
  expect_error(run_study(pop = po), "unmatched POPULATION JOIN")
})

test_that("FAIL CLOSED: a wrong-year population join is refused and reports the years", {
  # The realistic form of the bug: the right tracts for the wrong year, so the
  # GEOIDs do not line up and every reached tract goes unmatched.
  po <- study_tract_pop()
  po$GEOID <- sub("^A", "Y", po$GEOID)                      # a different vintage's ids
  po$analysis_year <- 2010L
  expect_error(run_study(pop = po), "NO population record")
  expect_error(run_study(pop = po), "year/vintage/GEOID mismatch")
  expect_error(run_study(pop = po), "2010")                 # surfaces the year present
})

test_that("FAIL CLOSED: a GEOID vintage mismatch is refused", {
  po <- study_tract_pop(); po$GEOID <- paste0("08", po$GEOID)  # state-prefixed ids
  expect_error(run_study(pop = po), "NO population record")
})

test_that("detection does not depend on row order", {
  po <- study_tract_pop(); po <- po[po$GEOID != "A02", ]
  for (ord in list(rev(seq_len(nrow(po))), sample(nrow(po)), order(po$GEOID))) {
    expect_error(run_study(pop = po[ord, , drop = FALSE]), "NO population record")
  }
  po2 <- study_tract_pop(); po2$female_pop[po2$GEOID == "A02"] <- NA
  for (ord in list(rev(seq_len(nrow(po2))), sample(nrow(po2)))) {
    expect_error(run_study(pop = po2[ord, , drop = FALSE]), "NA in population column")
  }
})

test_that("an unexpected many-to-many population join is an error, not a warning", {
  # dplyr previously WARNED here and the pipeline carried on. In an accessibility
  # model a many-to-many join multiplies a tract's population through every
  # denominator while the output stays entirely plausible.
  po <- study_tract_pop(); po <- rbind(po, po[po$GEOID == "A02", ])
  expect_error(run_study(pop = po), "duplicate GEOID in tract_pop")
})

test_that("a physician with a placeholder location is excluded from supply", {
  ym <- study_year_coord_map(); ym$match_source[ym$npi == 101] <- NA
  r <- run_study(ycm = ym)
  expect_equal(r$supply$supply[r$supply$coord_id == "PA1"], 1)   # was 2
  expect_lt(acc_of(r, "A01"), acc_of(S, "A01"))
})

test_that("catchment boundaries: exactly on, just inside, just outside", {
  # A tract edge sitting exactly on a catchment edge is the classic off-by-one.
  # PA1@30 ends at x = 1500; A02 spans 1000-2000, so exactly half is inside.
  expect_equal(S$overlap$overlap_fraction[S$overlap$coord_id == "PA1" &
                                            S$overlap$band == 30 &
                                            S$overlap$GEOID == "A02"], 0.5, tolerance = 1e-9)
  shift <- function(dx) {
    is <- study_iso_sf()
    i <- which(is$coord_id == "PA1" & is$drive_time_minutes == 30)
    sf::st_geometry(is)[i] <- sf::st_sfc(.rect(0, 1500 + dx, 0, 1000), crs = 5070)
    run_study(iso = is)
  }
  inside  <- shift(+1)     # 1 m further in
  outside <- shift(-1)     # 1 m further out
  f_in  <- inside$overlap$overlap_fraction[inside$overlap$coord_id == "PA1" &
             inside$overlap$band == 30 & inside$overlap$GEOID == "A02"]
  f_out <- outside$overlap$overlap_fraction[outside$overlap$coord_id == "PA1" &
             outside$overlap$band == 30 & outside$overlap$GEOID == "A02"]
  expect_gt(f_in, 0.5); expect_lt(f_out, 0.5)
  expect_equal(f_in,  0.501, tolerance = 1e-6)
  expect_equal(f_out, 0.499, tolerance = 1e-6)
})

# =============================================================================
# 6. PARTITION / RECOMBINATION METAMORPHIC TESTS
# =============================================================================
# No frozen expected value is needed: the transformation itself determines what
# must hold.
test_that("splitting a tract PROPORTIONALLY is exactly invariant", {
  # The invariant holds only under the assumption areal interpolation already
  # makes: population is uniform within a tract. Split A02 (area 1e6, pop 2000)
  # into two equal-area halves of 1000 each and nothing may move -- PA1's
  # denominator, the untouched tracts, or the recombined parent value.
  #
  # THIS TEST FAILED FIRST TIME with a 1200/800 split, and the code was right.
  # Splitting non-proportionally moves PA1's demand from 1680 to 1744 because it
  # RESOLVES which half of A02 is actually inside the 30-minute catchment, which
  # the uniform-density assumption could only average. That is new information,
  # not a bug -- and it is exactly the areal-interpolation error a real study
  # carries. Recorded here because the distinction is easy to mistake for one.
  tr <- study_tracts_sf()
  keep <- tr[tr$GEOID != "A02", ]
  halves <- tr[c(2, 2), ]
  sf::st_geometry(halves) <- sf::st_sfc(list(.rect(1000, 1500, 0, 1000),
                                             .rect(1500, 2000, 0, 1000)), crs = 5070)
  halves$GEOID <- c("A02a", "A02b")
  po <- study_tract_pop(); po <- po[po$GEOID != "A02", ]
  po <- rbind(po, data.frame(GEOID = c("A02a", "A02b"), female_pop = c(1000, 1000),
                             stringsAsFactors = FALSE))
  r <- run_study(tracts = rbind(keep, halves), pop = po)

  # Step 1 denominators are untouched: 0.32*1*1000 + 0.68*1*1000 + 0.68*1*1000
  # = 1680, exactly what whole-A02 contributed.
  expect_equal(r$ratios$weighted_demand[r$ratios$coord_id == "PA1"],
               ORACLE$stage_3_weighted_demand$PA1, tolerance = 1e-9)
  # Every untouched tract is bit-identical.
  for (g in c("A01", "A03", "A04", "A05"))
    expect_equal(acc_of(r, g), acc_of(S, g), tolerance = TOL, info = g)
  # And the population-weighted recombination recovers the parent exactly.
  expect_equal((acc_of(r, "A02a") + acc_of(r, "A02b")) / 2, acc_of(S, "A02"),
               tolerance = 1e-12)
  # The halves are NOT equal to each other: A02a is fully inside the 30-minute
  # catchment and A02b only inside the 60. If they were equal the split would be
  # resolving nothing and the test would be vacuous.
  expect_gt(acc_of(r, "A02a"), acc_of(r, "A02b"))
})

test_that("splitting a provider into two colocated providers preserves total access", {
  # PA1 has 2 physicians. Split it into two colocated coordinates with 1 each and
  # identical catchments: the same supply reaches the same people, so every
  # tract's accessibility must be unchanged.
  is <- study_iso_sf()
  pa1 <- is[is$coord_id == "PA1", ]
  pa1a <- pa1; pa1a$coord_id <- "PA1a"
  pa1b <- pa1; pa1b$coord_id <- "PA1b"
  is2 <- rbind(is[is$coord_id != "PA1", ], pa1a, pa1b)
  ym <- study_year_coord_map()
  ym$coord_id[ym$npi == 101] <- "PA1a"
  ym$coord_id[ym$npi == 102] <- "PA1b"
  ym$coord_id[ym$npi == 501] <- "PA1a"   # wrong-year decoy, still excluded
  r <- run_study(ycm = ym, iso = is2)
  expect_equal(r$supply$supply[r$supply$coord_id == "PA1a"], 1)
  expect_equal(r$supply$supply[r$supply$coord_id == "PA1b"], 1)
  for (g in A_TRACTS)
    expect_equal(acc_of(r, g), acc_of(S, g), tolerance = 1e-12, info = g)
})

# =============================================================================
# 7. WHOLE-SYSTEM SCALING
# =============================================================================
test_that("scaling all supply by k scales all accessibility by exactly k", {
  for (k in c(1e-6, 0.5, 3, 1e6)) {
    ym <- study_year_coord_map()
    # Supply is a physician COUNT, so scale it at the ratio layer instead: run
    # the pipeline, then rescale supply and rerun compute_e2sfca directly.
    sup <- as.data.frame(compute_provider_supply(ym, study_cohort(), "GO", 2020L))
    ov  <- compute_band_tract_overlap(study_iso_sf(), study_tracts_sf(), verbose = FALSE)
    sup$supply <- sup$supply * k
    a <- as.data.frame(compute_e2sfca(ov, study_tract_pop(), sup, weights = STUDY_W)$access)
    for (g in c("A01", "A02", "A03"))
      expect_equal(a$access[a$GEOID == g], acc_of(S, g) * k, tolerance = 1e-9 * max(1, k),
                   info = sprintf("k = %g at %s", k, g))
  }
})

test_that("scaling all population by k scales accessibility by exactly 1/k", {
  for (k in c(1e-3, 4, 1e3)) {
    po <- study_tract_pop(); po$female_pop <- po$female_pop * k
    r <- run_study(pop = po)
    for (g in c("A01", "A02", "A03"))
      expect_equal(acc_of(r, g), acc_of(S, g) / k, tolerance = 1e-12,
                   info = sprintf("k = %g at %s", k, g))
  }
})

test_that("scaling supply and population together leaves accessibility unchanged", {
  for (k in c(1e-4, 7, 1e4)) {
    sup <- as.data.frame(compute_provider_supply(study_year_coord_map(),
                                                 study_cohort(), "GO", 2020L))
    ov  <- compute_band_tract_overlap(study_iso_sf(), study_tracts_sf(), verbose = FALSE)
    po  <- study_tract_pop(); po$female_pop <- po$female_pop * k
    sup$supply <- sup$supply * k
    a <- as.data.frame(compute_e2sfca(ov, po, sup, weights = STUDY_W)$access)
    for (g in c("A01", "A02", "A03"))
      expect_equal(a$access[a$GEOID == g], acc_of(S, g), tolerance = 1e-9,
                   info = sprintf("common k = %g at %s", k, g))
  }
})

test_that("changing the linear unit of the geometry cannot change conclusions", {
  # Overlap is a RATIO of areas, so scaling every coordinate leaves it invariant.
  # A pipeline that compared raw areas against an absolute threshold would break.
  scale_geom <- function(x, f) {
    sf::st_geometry(x) <- sf::st_sfc(lapply(sf::st_geometry(x), function(p) p * f),
                                     crs = 5070)
    x
  }
  r <- run_study(iso = scale_geom(study_iso_sf(), 3),
                 tracts = scale_geom(study_tracts_sf(), 3))
  for (g in A_TRACTS) expect_equal(acc_of(r, g), acc_of(S, g), tolerance = 1e-9, info = g)
})

test_that("the corpus mutant target still exists: unmatched tracts cannot reach the imputation", {
  # missing_population_becomes_zero_silently mutates the NA-imputation branch.
  # Under the fail-closed contract that branch is now unreachable for unmatched
  # tracts, so this asserts the ERROR path is what runs -- which is what kills
  # the mutant, since a mutated imputation can never execute.
  po <- study_tract_pop(); po <- po[po$GEOID != "A02", ]
  expect_error(run_study(pop = po), "NO population record")
  # And under the explicit opt-in the imputation DOES run, so the mutant has a
  # live target and remains killable rather than becoming dead code.
  sup <- compute_provider_supply(study_year_coord_map(), study_cohort(), "GO", 2020L)
  ov  <- compute_band_tract_overlap(study_iso_sf(), study_tracts_sf(), verbose = FALSE)
  po2 <- study_tract_pop(); po2$female_pop[po2$GEOID == "A02"] <- NA
  r <- compute_e2sfca(ov, po2, sup, weights = STUDY_W, na_pop_policy = "zero")
  expect_equal(as.data.frame(r$provider_ratios)$weighted_demand[1],
               0.32 * 1000 + 0.68 * (1000 + 0.5 * 500), tolerance = 1e-9)
})

# compute_e2sfca(): measured zero versus outside every modelled catchment.
#
# The defect this pins: the all-tract join used to end with
#
#     access$access[is.na(access$access)] <- 0
#
# which gave a tract no isochrone reaches the same value as a tract inside a
# catchment whose weighted supply works out to zero. On a rare-subspecialty
# surface that is most of the map -- 190 of 1,447 Colorado tracts -- and every
# one of them was reported as a measured zero.
#
# Fixtures here are hand-sized so every expected number can be derived on
# paper rather than recorded from a run.

# One band, weight 1.0, so access reduces to sum_j overlap_ij * R_j and
# R_j = supply_j / sum_i overlap_ij * pop_i. Nothing here needs a calculator.
W1 <- c(`30` = 1.0)

ov <- function(...) {
  rows <- list(...)
  dplyr::bind_rows(lapply(rows, function(r)
    dplyr::tibble(coord_id = r[[1]], band = 30L, GEOID = r[[2]],
                  overlap_fraction = as.numeric(r[[3]]))))
}
tp <- function(...) {
  x <- c(...)
  dplyr::tibble(GEOID = names(x), female_pop = as.numeric(x))
}
sp <- function(...) {
  x <- c(...)
  dplyr::tibble(coord_id = names(x), supply = as.numeric(x))
}
run <- function(overlap, tract_pop, supply, ...) {
  compute_e2sfca(overlap, tract_pop, supply, weights = W1, ...)
}
row_for <- function(res, geoid) res$access[res$access$GEOID == geoid, ]

test_that("a reached tract with positive access gets a numeric public score", {
  # T1 fully covered by P1 (supply 10, demand 100*1.0 = 100) -> R = 0.1,
  # access = 1.0 * 0.1 = 0.1.
  res <- run(ov(list("P1", "T1", 1)), tp(T1 = 100), sp(P1 = 10))
  r <- row_for(res, "T1")
  expect_equal(r$access, 0.1)
  expect_equal(r$access_math, 0.1)
  expect_true(r$reached)
  expect_identical(r$coverage_status, "within_modeled_catchment")
})

test_that("NEGATIVE CONTROL: a reached tract computing to zero stays 0, not NA", {
  # The mandatory control. T2 is inside P1's catchment but P1 has zero supply,
  # so T2's access is genuinely zero -- a measurement, not an absence. If
  # coverage were inferred from the score (or from supply), this row would be
  # mislabelled and the defect would simply have moved.
  res <- run(ov(list("P1", "T1", 1), list("P1", "T2", 1)),
             tp(T1 = 100, T2 = 50), sp(P1 = 0))
  r <- row_for(res, "T2")
  expect_equal(r$access, 0)
  expect_false(is.na(r$access))
  expect_equal(r$access_math, 0)
  expect_true(r$reached)
  expect_identical(r$coverage_status, "within_modeled_catchment")
})

test_that("an unreached tract is NA scientifically and 0 algebraically", {
  res <- run(ov(list("P1", "T1", 1)), tp(T1 = 100, T9 = 500), sp(P1 = 10))
  r <- row_for(res, "T9")
  expect_true(is.na(r$access))
  expect_true(is.na(r$access_scaled))
  expect_equal(r$access_math, 0)
  expect_equal(r$access_scaled_math, 0)
  expect_false(r$reached)
  expect_identical(r$coverage_status, "outside_all_modeled_catchments")
})

test_that("zero population does not by itself make a tract unreached", {
  # An empty tract inside a catchment is covered. It contributes no demand, but
  # coverage is a topological fact about the isochrone, not about who lives
  # there.
  res <- run(ov(list("P1", "T1", 1), list("P1", "TE", 1)),
             tp(T1 = 100, TE = 0), sp(P1 = 10))
  r <- row_for(res, "TE")
  expect_true(r$reached)
  expect_identical(r$coverage_status, "within_modeled_catchment")
  expect_false(is.na(r$access))
})

test_that("zero provider supply does not by itself make a tract unreached", {
  res <- run(ov(list("P0", "T1", 1)), tp(T1 = 100), sp(P0 = 0))
  r <- row_for(res, "T1")
  expect_true(r$reached)
  expect_identical(r$coverage_status, "within_modeled_catchment")
  expect_equal(r$access, 0)
})

test_that("coverage comes from catchment membership, not score magnitude", {
  # Two tracts both score exactly 0. One is in a catchment, one is not. If the
  # implementation looked at the number it could not tell them apart -- which is
  # precisely the bug. They must differ.
  res <- run(ov(list("P0", "TIN", 1)), tp(TIN = 100, TOUT = 100), sp(P0 = 0))
  a_in <- row_for(res, "TIN")
  a_out <- row_for(res, "TOUT")
  expect_equal(a_in$access_math, a_out$access_math)      # identical arithmetic
  expect_false(identical(a_in$coverage_status, a_out$coverage_status))
  expect_equal(a_in$access, 0)
  expect_true(is.na(a_out$access))
})

test_that("reached agrees exactly with coverage_status, on every row", {
  res <- run(ov(list("P1", "T1", 1), list("P1", "T2", 0.5), list("P0", "T3", 1)),
             tp(T1 = 100, T2 = 80, T3 = 60, T9 = 10, T8 = 0), sp(P1 = 5, P0 = 0))
  expect_identical(
    res$access$coverage_status,
    ifelse(res$access$reached, "within_modeled_catchment",
           "outside_all_modeled_catchments"))
  expect_false(any(is.na(res$access$reached)))
  expect_setequal(unique(res$access$coverage_status),
                  c("within_modeled_catchment", "outside_all_modeled_catchments"))
})

test_that("reordering the overlap rows changes nothing", {
  o <- ov(list("P1", "T1", 1), list("P2", "T2", 0.4), list("P1", "T2", 0.6))
  p <- tp(T1 = 100, T2 = 80, T9 = 5)
  s <- sp(P1 = 5, P2 = 3)
  a <- run(o, p, s)$access
  b <- run(o[rev(seq_len(nrow(o))), ], p, s)$access
  expect_equal(a$access, b$access)
  expect_identical(a$coverage_status, b$coverage_status)
  expect_identical(a$GEOID, b$GEOID)
})

test_that("adding an unreachable tract does not disturb any existing tract", {
  o <- ov(list("P1", "T1", 1), list("P1", "T2", 0.5))
  s <- sp(P1 = 10)
  before <- run(o, tp(T1 = 100, T2 = 50), s)$access
  after <- run(o, tp(T1 = 100, T2 = 50, TNEW = 999), s)$access
  keep <- after[after$GEOID %in% before$GEOID, ]
  expect_equal(keep$access, before$access)
  expect_equal(keep$access_math, before$access_math)
  expect_identical(keep$coverage_status, before$coverage_status)
  expect_false(after$reached[after$GEOID == "TNEW"])
})

test_that("every tract in tract_pop appears exactly once", {
  p <- tp(T1 = 100, T2 = 50, T3 = 0, T9 = 7)
  res <- run(ov(list("P1", "T1", 1), list("P1", "T1", 1)), p, sp(P1 = 10))
  expect_setequal(res$access$GEOID, p$GEOID)
  expect_equal(nrow(res$access), nrow(p))
  expect_false(anyDuplicated(res$access$GEOID) > 0)
})

test_that("the scientific and algebraic columns agree wherever a tract is reached", {
  res <- run(ov(list("P1", "T1", 1), list("P0", "T2", 1)),
             tp(T1 = 100, T2 = 50, T9 = 5), sp(P1 = 10, P0 = 0))
  hit <- res$access[res$access$reached, ]
  expect_equal(hit$access, hit$access_math)
  expect_equal(hit$access_scaled, hit$access_scaled_math)
})

test_that("the audit counts the two states", {
  res <- run(ov(list("P1", "T1", 1), list("P0", "T2", 1)),
             tp(T1 = 100, T2 = 50, T9 = 5, T8 = 5), sp(P1 = 10, P0 = 0))
  expect_equal(res$audit$n_tracts, 4L)
  expect_equal(res$audit$n_within_modeled_catchment, 2L)
  expect_equal(res$audit$n_outside_all_modeled_catchments, 2L)
  expect_equal(res$audit$n_reached_scoring_zero, 1L)   # T2, inside P0's catchment
})

test_that("MUTATION: restoring the old zero-fill is caught", {
  # The guard on the guard. Collapse the two states the way the old code did
  # and prove a test notices. If this passes silently, everything above is
  # decoration.
  res <- run(ov(list("P1", "T1", 1)), tp(T1 = 100, T9 = 500), sp(P1 = 10))

  mutated <- res$access
  mutated$access[is.na(mutated$access)] <- 0          # the deleted line
  mutated$coverage_status <- "within_modeled_catchment"
  mutated$reached <- TRUE

  unreached <- mutated[mutated$GEOID == "T9", ]
  expect_false(is.na(unreached$access))               # mutant scores 0
  # ... and the assertions that protect the real behaviour therefore fail:
  expect_failure(expect_true(is.na(unreached$access)))
  expect_failure(expect_identical(unreached$coverage_status,
                                  "outside_all_modeled_catchments"))
})

test_that("supply conservation holds on the ALGEBRAIC column", {
  # sum_i P_i A_i^math == sum_j S_j, for E2SFCA with no zero-demand provider.
  # This is why the unreached rows keep a mathematical zero: dropping them or
  # NA-ing them here would break the identity or need na.rm, which silently
  # changes the estimand.
  o <- ov(list("P1", "T1", 1), list("P1", "T2", 0.5),
          list("P2", "T2", 0.5), list("P2", "T3", 1))
  p <- tp(T1 = 100, T2 = 80, T3 = 60, T9 = 25)
  s <- sp(P1 = 7, P2 = 4)
  res <- run(o, p, s)

  pv <- setNames(p$female_pop, p$GEOID)[res$access$GEOID]
  expect_equal(sum(pv * res$access$access_math), sum(s$supply), tolerance = 1e-9)
  expect_equal(res$audit$n_zero_demand_origins, 0L)

  # And the scientific column cannot be used for this without na.rm, which is
  # the point of keeping them separate.
  expect_true(is.na(sum(pv * res$access$access)))
})

test_that("an unreached tract contributes exactly zero to the identity", {
  o <- ov(list("P1", "T1", 1))
  s <- sp(P1 = 7)
  with_extra <- run(o, tp(T1 = 100, T9 = 10000), s)$access
  without <- run(o, tp(T1 = 100), s)$access
  expect_equal(with_extra$access_math[with_extra$GEOID == "T1"],
               without$access_math[without$GEOID == "T1"])
  expect_equal(with_extra$access_math[with_extra$GEOID == "T9"], 0)
})

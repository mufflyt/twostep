# =============================================================================
# Metamorphic geography, weight algebra, overlap algebra, and closed forms.
# =============================================================================
# Where the invariant suite checks properties of one run and the simulation
# suite checks behaviour across many, this file checks RELATIONSHIPS between
# runs: transformations whose effect on the answer is known exactly in advance.
# That is the strongest kind of test available without an external oracle,
# because the expected value is derived from the mathematics rather than from
# the code that produces it.

# --- helpers for tiny hand-built systems -------------------------------------
mk <- function(overlap, pop, supply) list(overlap = overlap, tract_pop = pop, supply = supply)
row1 <- function(j, g, b, f) data.frame(coord_id = j, GEOID = g, band = b,
                                        overlap_fraction = f, stringsAsFactors = FALSE)
W1 <- c("30" = 1)                       # single band, no decay
acc_of <- function(fx, g, W = W1, ...) {
  a <- prod_access(fx, W = W, ...)
  a$access[match(g, a$GEOID)]
}

# =============================================================================
# 3. METAMORPHIC GEOGRAPHY
# =============================================================================
test_that("relabelling every identifier leaves accessibility unchanged", {
  # Section 32's provider-ID renaming: the answer must depend on the structure
  # of the system, never on the tokens naming it.
  for (s in c(501L, 502L, 503L)) {
    fx <- make_fixture(s, n_prov = 4L, n_tract = 7L)
    base <- prod_access(fx)

    gmap <- stats::setNames(sprintf("Z%09d", seq_along(fx$tract_pop$GEOID)),
                            fx$tract_pop$GEOID)
    jmap <- stats::setNames(paste0("Q", seq_along(fx$supply$coord_id)),
                            fx$supply$coord_id)
    re <- fx
    re$overlap$GEOID    <- gmap[as.character(fx$overlap$GEOID)]
    re$overlap$coord_id <- jmap[as.character(fx$overlap$coord_id)]
    re$tract_pop$GEOID  <- gmap[as.character(fx$tract_pop$GEOID)]
    re$supply$coord_id  <- jmap[as.character(fx$supply$coord_id)]

    got <- prod_access(re)
    expect_equal(got$access[match(gmap[base$GEOID], got$GEOID)], base$access,
                 tolerance = 1e-12)
  }
})

test_that("a disconnected duplicate of the whole system reproduces the original answers", {
  # Two identical, mutually unreachable copies. Each copy must get exactly what
  # it got alone. This is the sharpest join/key-leak detector here: any
  # aggregation that forgets to group by provider or tract will bleed between
  # the copies and move both.
  for (s in c(511L, 512L)) {
    fx   <- make_fixture(s, n_prov = 3L, n_tract = 5L)
    solo <- prod_access(fx)

    dup <- fx
    dup$overlap$GEOID    <- paste0("D", fx$overlap$GEOID)
    dup$overlap$coord_id <- paste0("D", fx$overlap$coord_id)
    dup$tract_pop$GEOID  <- paste0("D", fx$tract_pop$GEOID)
    dup$supply$coord_id  <- paste0("D", fx$supply$coord_id)
    both <- mk(rbind(fx$overlap, dup$overlap),
               rbind(fx$tract_pop, dup$tract_pop),
               rbind(fx$supply, dup$supply))
    got <- prod_access(both)

    expect_equal(got$access[match(solo$GEOID, got$GEOID)], solo$access, tolerance = 1e-12)
    expect_equal(got$access[match(paste0("D", solo$GEOID), got$GEOID)], solo$access,
                 tolerance = 1e-12)
  }
})

test_that("splitting a tract in two leaves BOTH halves at the original accessibility", {
  # Accessibility is an intensity, not a total. Splitting a tract into two
  # sub-tracts whose populations sum to the original and which share its overlap
  # leaves Step 1 demand unchanged (w f p1 + w f p2 = w f p), so the ratio is
  # unchanged, so each half reports exactly what the whole did. A pipeline that
  # treats access as a count would halve it.
  ov <- rbind(row1("P1", "T1", 30, 0.5), row1("P1", "T2", 30, 0.8))
  fx <- mk(ov,
           data.frame(GEOID = c("T1", "T2"), female_pop = c(1000, 400),
                      stringsAsFactors = FALSE),
           data.frame(coord_id = "P1", supply = 10, stringsAsFactors = FALSE))
  base <- acc_of(fx, c("T1", "T2"))

  sp <- mk(rbind(row1("P1", "T1a", 30, 0.5), row1("P1", "T1b", 30, 0.5),
                 row1("P1", "T2", 30, 0.8)),
           data.frame(GEOID = c("T1a", "T1b", "T2"), female_pop = c(600, 400, 400),
                      stringsAsFactors = FALSE),
           data.frame(coord_id = "P1", supply = 10, stringsAsFactors = FALSE))
  got <- acc_of(sp, c("T1a", "T1b", "T2"))

  expect_equal(got[1], base[1], tolerance = 1e-12)   # both halves keep
  expect_equal(got[2], base[1], tolerance = 1e-12)   # the parent's value
  expect_equal(got[3], base[2], tolerance = 1e-12)   # the untouched tract
})

# =============================================================================
# 4. WEIGHT-FUNCTION INVARIANTS
# =============================================================================
test_that("all cumulative weights equal to 1 reduces to the single-catchment case", {
  # w'_b = W_b - W_{b+1} is 0 everywhere except the outermost band, where it is
  # 1. The model must collapse to plain 2SFCA on the largest catchment.
  fx <- make_fixture(521L, n_prov = 3L, n_tract = 6L)
  flat <- c("30" = 1, "60" = 1, "120" = 1, "180" = 1)
  got  <- prod_access(fx, W = flat)

  only180 <- fx
  only180$overlap <- fx$overlap[fx$overlap$band == 180, , drop = FALSE]
  ref <- prod_access(only180, W = c("180" = 1))
  expect_equal(got$access, ref$access[match(got$GEOID, ref$GEOID)], tolerance = 1e-12)
})

test_that("accessibility is invariant to rescaling ALL cumulative weights", {
  # Scaling W by c scales every incremental weight by c, hence demand by c,
  # hence the ratio by 1/c -- which cancels exactly in Step 2. A pipeline that
  # applied the weights once in one step and twice in the other would not
  # survive this.
  fx <- make_fixture(531L, n_prov = 4L, n_tract = 6L)
  base <- prod_access(fx, W = W4)
  for (cc in c(0.25, 2, 10)) {
    expect_equal(prod_access(fx, W = W4 * cc)$access, base$access, tolerance = 1e-10,
                 info = paste("rescaling all weights by", cc, "changed the answer"))
  }
})

test_that("a band with zero incremental weight is equivalent to deleting its rows", {
  # W_b == W_{b+1} makes w'_b exactly 0, so band b can contribute nothing.
  # Deleting those overlap rows must therefore change nothing at all.
  fx <- make_fixture(541L, n_prov = 3L, n_tract = 6L)
  W <- c("30" = 1.0, "60" = 0.6, "120" = 0.6, "180" = 0.2)   # 60 and 120 tie
  with_rows <- prod_access(fx, W = W)
  without   <- fx
  without$overlap <- fx$overlap[fx$overlap$band != 60, , drop = FALSE]
  expect_equal(prod_access(without, W = W)$access,
               with_rows$access[match(prod_access(without, W = W)$GEOID, with_rows$GEOID)],
               tolerance = 1e-12)
})

test_that("a band outside the weight vector contributes exactly zero", {
  # The inclusion convention: bands not named in the weights are not part of the
  # model and must be dropped, not silently treated as weight 1.
  fx <- make_fixture(551L, n_prov = 3L, n_tract = 5L)
  narrow <- c("30" = 1.0, "60" = 0.5)
  got <- prod_access(fx, W = narrow)
  trimmed <- fx
  trimmed$overlap <- fx$overlap[fx$overlap$band %in% c(30, 60), , drop = FALSE]
  expect_equal(got$access, prod_access(trimmed, W = narrow)$access, tolerance = 1e-12)
})

# =============================================================================
# 5. OVERLAP-FRACTION ALGEBRA
# =============================================================================
test_that("a zero overlap fraction is equivalent to the connection being absent", {
  base <- mk(rbind(row1("P1", "T1", 30, 0.5), row1("P1", "T2", 30, 0.0)),
             data.frame(GEOID = c("T1", "T2"), female_pop = c(500, 900),
                        stringsAsFactors = FALSE),
             data.frame(coord_id = "P1", supply = 4, stringsAsFactors = FALSE))
  gone <- mk(row1("P1", "T1", 30, 0.5),
             base$tract_pop, base$supply)
  expect_equal(acc_of(base, c("T1", "T2")), acc_of(gone, c("T1", "T2")), tolerance = 1e-12)
})

test_that("a partitioned overlap reproduces the unsplit contribution (0.25 + 0.75 = 1)", {
  whole <- mk(row1("P1", "T1", 30, 1.0),
              data.frame(GEOID = "T1", female_pop = 800, stringsAsFactors = FALSE),
              data.frame(coord_id = "P1", supply = 6, stringsAsFactors = FALSE))
  split <- mk(rbind(row1("P1", "T1", 30, 0.25), row1("P1", "T1", 30, 0.75)),
              whole$tract_pop, whole$supply)
  expect_equal(acc_of(split, "T1"), acc_of(whole, "T1"), tolerance = 1e-12)
})

test_that("DOCUMENTED GAP: overlap fractions summing above 1 are not rejected", {
  # A tract cannot be more than fully inside a catchment, so fractions summing
  # past 1 mean upstream geometry is wrong. The engine currently accepts them
  # and overcounts demand silently. This test pins CURRENT behaviour rather than
  # asserting it is correct: if a fail-closed guard is added, this test should be
  # updated in the same commit, which is precisely the review moment wanted.
  over <- mk(rbind(row1("P1", "T1", 30, 0.8), row1("P1", "T1", 30, 0.9)),
             data.frame(GEOID = "T1", female_pop = 1000, stringsAsFactors = FALSE),
             data.frame(coord_id = "P1", supply = 5, stringsAsFactors = FALSE))
  expect_silent(a <- acc_of(over, "T1"))
  expect_true(is.finite(a))
  # Closed form: demand = 1.7 * 1000, ratio = 5/1700, access = 1.7 * 5/1700 = 5/1000.
  expect_equal(a, 5 / 1000, tolerance = 1e-12)
})

# =============================================================================
# 7. CLOSED-FORM "PHYSICS EXPERIMENTS"
# =============================================================================
test_that("one provider, one tract: access is exactly supply / population", {
  # demand = f*p ; R = S/(f*p) ; A = f*R = S/p, independent of f. The overlap
  # fraction cancels: a provider that half-covers a tract serves half its
  # population and is credited to half of it.
  for (f in c(0.2, 0.5, 1.0)) {
    fx <- mk(row1("P1", "T1", 30, f),
             data.frame(GEOID = "T1", female_pop = 250, stringsAsFactors = FALSE),
             data.frame(coord_id = "P1", supply = 5, stringsAsFactors = FALSE))
    expect_equal(acc_of(fx, "T1"), 5 / 250, tolerance = 1e-12,
                 info = paste("overlap fraction", f, "failed to cancel"))
  }
})

test_that("two identical providers double a single tract's access", {
  fx <- mk(rbind(row1("P1", "T1", 30, 0.6), row1("P2", "T1", 30, 0.6)),
           data.frame(GEOID = "T1", female_pop = 400, stringsAsFactors = FALSE),
           data.frame(coord_id = c("P1", "P2"), supply = c(3, 3),
                      stringsAsFactors = FALSE))
  expect_equal(acc_of(fx, "T1"), 2 * 3 / 400, tolerance = 1e-12)
})

test_that("one provider, two tracts: supply splits by weighted demand share", {
  # demand = f1 p1 + f2 p2 ; R = S/demand ; A_i = f_i R.
  f1 <- 1.0; f2 <- 0.5; p1 <- 100; p2 <- 300; S <- 8
  fx <- mk(rbind(row1("P1", "T1", 30, f1), row1("P1", "T2", 30, f2)),
           data.frame(GEOID = c("T1", "T2"), female_pop = c(p1, p2),
                      stringsAsFactors = FALSE),
           data.frame(coord_id = "P1", supply = S, stringsAsFactors = FALSE))
  D <- f1 * p1 + f2 * p2
  expect_equal(acc_of(fx, c("T1", "T2")), c(f1 * S / D, f2 * S / D), tolerance = 1e-12)
  # The whole of the usable supply is distributed, and no more.
  expect_equal(sum(acc_of(fx, c("T1", "T2")) * c(p1, p2)), S, tolerance = 1e-12)
})

test_that("a dominant provider and a tiny one rank in the correct order", {
  fx <- mk(rbind(row1("Big", "T1", 30, 1), row1("Small", "T2", 30, 1)),
           data.frame(GEOID = c("T1", "T2"), female_pop = c(1000, 1000),
                      stringsAsFactors = FALSE),
           data.frame(coord_id = c("Big", "Small"), supply = c(100, 1e-6),
                      stringsAsFactors = FALSE))
  a <- acc_of(fx, c("T1", "T2"))
  expect_gt(a[1], a[2])
  expect_equal(a, c(100 / 1000, 1e-6 / 1000), tolerance = 1e-15)
  expect_true(a[2] > 0)                       # a tiny supply is not rounded away
})

# =============================================================================
# 8. NUMERICAL ROBUSTNESS
# =============================================================================
test_that("scaling population and supply together leaves accessibility unchanged", {
  # A = S/p in the closed form, so a common factor cancels. Checks the pipeline
  # over six orders of magnitude in both directions.
  for (k in c(1e-6, 1e-3, 1e3, 1e6)) {
    fx <- make_fixture(561L, n_prov = 3L, n_tract = 5L)
    base <- prod_access(fx)
    sc <- fx
    sc$tract_pop$female_pop <- sc$tract_pop$female_pop * k
    sc$supply$supply        <- sc$supply$supply * k
    expect_equal(prod_access(sc)$access, base$access, tolerance = 1e-8,
                 info = paste("common scale factor", k, "did not cancel"))
  }
})

test_that("scaling population alone scales accessibility by exactly 1/k", {
  fx <- make_fixture(571L, n_prov = 3L, n_tract = 5L)
  base <- prod_access(fx)
  for (k in c(2, 1000)) {
    sc <- fx; sc$tract_pop$female_pop <- sc$tract_pop$female_pop * k
    expect_equal(prod_access(sc)$access, base$access / k, tolerance = 1e-10)
  }
})

test_that("integer and double population columns give identical answers", {
  fx <- make_fixture(581L, n_prov = 3L, n_tract = 5L)
  fx$tract_pop$female_pop <- as.integer(fx$tract_pop$female_pop)
  int_ans <- prod_access(fx)
  fx$tract_pop$female_pop <- as.double(fx$tract_pop$female_pop)
  expect_equal(prod_access(fx)$access, int_ans$access, tolerance = 1e-15)
})

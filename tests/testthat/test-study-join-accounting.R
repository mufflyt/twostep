# ==============================================================================
# Study-layer join accounting -- ported from isochrones fe25f0ed3, 2026-08-18.
# ==============================================================================
# THE TWO BUGS THESE PIN
#   (1) Two inner_join()s dropped unmatched tracts with no record. The entire
#       state of Connecticut left the 2022/2023 analysis this way while every
#       national match-rate gate stayed green.
#   (2) `d$access[is.na(d$access)] <- 0` turned a provenance gap into a MEASURED
#       observation of no access, biasing the population-weighted mean down and
#       the zero-access share up.
#
# Measured downstream impact of fixing both, from the isochrones rerun: the
# metropolitan-rural gap had been OVERSTATED by 2.1-2.5% in every subspecialty
# and both years; Asian mean access -1.8 to -1.9%; Asian-vs-White gap narrowed
# 4.6% (GO 2023). No conclusion reversed.
# ==============================================================================

# source() rather than library(twostep): the nightly testthat job deliberately
# does NOT install the package, so every suite reaches the code through the
# working tree.
suppressWarnings(suppressMessages(library(testthat)))
.root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION") | rprojroot::is_git_root)
source(file.path(.root, "R", "study_join_accounting.R"))

# --- (1) per-state fail-closed gate -------------------------------------------

test_that("a whole small state vanishing is caught", {
  # THE CONNECTICUT CASE. 100 CT tracts, all unmatched, inside a national
  # population large enough that the NATIONAL rate stays high.
  ct <- sprintf("09001%06d", 1:100)
  ma <- sprintf("25025%06d", 1:9900)
  g  <- c(ct, ma)
  lost <- c(rep(TRUE, 100), rep(FALSE, 9900))

  # National loss is only 1% -- a national gate would pass this.
  expect_lt(mean(lost), 0.02)
  # The per-state gate must still fail closed, and must NAME the state.
  expect_error(assert_state_join_loss(g, lost, "GO 2023"), "09")
  expect_error(assert_state_join_loss(g, lost, "GO 2023"), "national match rate")
})

test_that("NEGATIVE CONTROL: a clean join passes and returns no offenders", {
  # If this failed, the gate would block correct runs.
  g <- c(sprintf("09001%06d", 1:50), sprintf("25025%06d", 1:50))
  expect_silent(assert_state_join_loss(g, rep(FALSE, 100), "clean"))
  expect_length(assert_state_join_loss(g, rep(FALSE, 100), "clean"), 0L)
})

test_that("NEGATIVE CONTROL: diffuse sub-threshold loss does NOT trip the gate", {
  # A few unmatched tracts spread across states is normal (RUCA gaps). The gate
  # must target a state DISAPPEARING, not ordinary attrition, or it would be
  # switched off in practice.
  g    <- c(sprintf("09001%06d", 1:100), sprintf("25025%06d", 1:100))
  lost <- rep(FALSE, 200); lost[c(1:3, 101:103)] <- TRUE   # 3% each
  expect_silent(assert_state_join_loss(g, lost, "diffuse"))
})

test_that("the threshold boundary behaves as specified (>5%, not >=)", {
  g <- sprintf("09001%06d", 1:100)
  lost5 <- rep(FALSE, 100); lost5[1:5] <- TRUE    # exactly 5% -> allowed
  lost6 <- rep(FALSE, 100); lost6[1:6] <- TRUE    # 6%          -> blocked
  expect_silent(assert_state_join_loss(g, lost5, "boundary"))
  expect_error(assert_state_join_loss(g, lost6, "boundary"), "lost >5%")
})

test_that("max_frac is honoured", {
  g    <- sprintf("09001%06d", 1:100)
  lost <- rep(FALSE, 100); lost[1:10] <- TRUE
  expect_silent(assert_state_join_loss(g, lost, "loose", max_frac = 0.20))
  expect_error(assert_state_join_loss(g, lost, "tight", max_frac = 0.01))
})

test_that("multiple offending states are all named", {
  g    <- c(sprintf("09001%06d", 1:100), sprintf("44007%06d", 1:100))
  lost <- rep(TRUE, 200)
  err  <- tryCatch(assert_state_join_loss(g, lost, "multi"), error = function(e) conditionMessage(e))
  expect_match(err, "09")
  expect_match(err, "44")
})

# --- (2) NA access is not zero access -----------------------------------------

test_that("unknown access is excluded, and a measured zero is NOT", {
  # THE CORE DISTINCTION. A measured 0 is real data and must survive; an NA is a
  # provenance gap and must not be silently converted into a measured 0.
  d <- data.frame(GEOID = c("a", "b", "c"), access = c(10, NA, 0))
  p <- partition_unknown_access(d)
  expect_equal(p$n_unknown, 1L)
  expect_equal(nrow(p$kept), 2L)
  expect_true(0 %in% p$kept$access)      # the measured zero survived
  expect_false(anyNA(p$kept$access))
})

test_that("zeroing NA biases the mean down and the zero-share up (the old bug)", {
  # This is the quantitative reason the old line was wrong. It demonstrates the
  # direction of the bias that the isochrones rerun then measured nationally.
  d <- data.frame(GEOID = sprintf("t%03d", 1:10),
                  access = c(rep(100, 5), rep(NA_real_, 5)))

  old_mean <- mean(ifelse(is.na(d$access), 0, d$access))          # zeroed
  new_mean <- mean(partition_unknown_access(d)$kept$access)       # partitioned
  expect_equal(old_mean, 50)
  expect_equal(new_mean, 100)
  expect_lt(old_mean, new_mean)                                   # biased DOWN

  old_zero <- mean(ifelse(is.na(d$access), 0, d$access) == 0)
  new_zero <- mean(partition_unknown_access(d)$kept$access == 0)
  expect_equal(old_zero, 0.5)
  expect_equal(new_zero, 0)
  expect_gt(old_zero, new_zero)                                   # biased UP
})

test_that("NEGATIVE CONTROL: a frame with no NA is returned unchanged", {
  d <- data.frame(GEOID = c("a", "b"), access = c(1, 2))
  p <- partition_unknown_access(d)
  expect_equal(p$n_unknown, 0L)
  expect_equal(p$frac_unknown, 0)
  expect_equal(nrow(p$kept), 2L)
})

test_that("all-unknown input yields an empty frame, not a column of zeros", {
  # The failure mode that would silently report a whole year as zero-access.
  d <- data.frame(GEOID = c("a", "b"), access = c(NA_real_, NA_real_))
  p <- partition_unknown_access(d)
  expect_equal(nrow(p$kept), 0L)
  expect_equal(p$frac_unknown, 1)
})

test_that("a missing access column fails closed", {
  expect_error(partition_unknown_access(data.frame(GEOID = "a"), "access"),
               "not present")
})

# --- (3) the old zeroing line must not come back ------------------------------

test_that("REGRESSION GUARD: the study script no longer zeroes NA access", {
  # A textual guard, because this exact line is what silently reintroduces the
  # bias if someone 'simplifies' the partition back to a coercion.
  f <- file.path(.root, "scripts", "stratify_allyears_access.R")
  skip_if_not(file.exists(f), "study script not present in this context")
  # Parse and deparse rather than grep the raw text: the file DISCUSSES the old
  # line in a comment, and a raw grep would match that prose forever.
  src <- paste(vapply(parse(f, keep.source = FALSE),
                      function(e) paste(deparse(e), collapse = "\n"),
                      character(1)),
               collapse = "\n")
  expect_false(grepl("access\\[is\\.na\\(d\\$access\\)\\]\\s*<-\\s*0", src))
  expect_true(grepl("partition_unknown_access", src, fixed = TRUE))
  expect_true(grepl("assert_state_join_loss", src, fixed = TRUE))
  # and the CT relabel must still be wired to the denominators
  expect_true(grepl("relabel_ct_geoids_safe", src, fixed = TRUE))
  # the joins must not have reverted to inner_join
  expect_false(grepl("inner_join", src, fixed = TRUE))
})

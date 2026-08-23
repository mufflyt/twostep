#!/usr/bin/env Rscript
# =============================================================================
# Data-adversarial corpus: corrupt the STUDY, not the code.
# =============================================================================
# tools/ci/mutation_corpus.R mutates R source and asks whether the tests notice.
# Nothing in this repository asked the other question:
#
#   How many ways can we manufacture a believable but scientifically FALSE
#   access disparity in the frozen results, and does twostep catch every one?
#
# That matters more than code mutation here, because the manuscript does not
# read the engine -- it reads e2sfca_national_summary.csv. A wrong number in
# that file is a wrong number in the paper, whatever the engine does.
#
# WHY THE HASH GATE IS DELIBERATELY EXCLUDED AS A DETECTOR
#
# scientific_diff.R hashes this file, so it kills every mutant below trivially
# and proves nothing scientific. It answers "was the artifact edited?" The
# question that matters is different: when the artifact is legitimately
# REGENERATED -- new hash, new run, honest intent -- does anything notice that
# the numbers are impossible? Only the invariants can answer that, so the
# invariants are the detector and the hash gate is held out on purpose.
#
# A surviving mutant is a corruption that could enter a re-run, pass every
# check, and be published.
#
# Usage: Rscript tools/ci/data_adversarial_corpus.R
suppressWarnings(suppressMessages({
  okpkg <- requireNamespace("digest", quietly = TRUE)
}))
if (!okpkg) { cat("::error::data corpus needs 'digest'\n"); quit(status = 1L) }
if (!file.exists("DESCRIPTION")) { cat("::error::run from the repository root\n"); quit(status = 1L) }

RUN <- "artifacts/2sfca/ec2/e2sfca_20260712_190734"
NS  <- file.path(RUN, "e2sfca_national_summary.csv")
DETECTOR <- "tools/ci/check_scientific_invariants.R"
for (f in c(NS, DETECTOR)) if (!file.exists(f)) {
  cat("::error::missing ", f, "\n", sep = ""); quit(status = 1L)
}

ORIGINAL_LINES <- readLines(NS, warn = FALSE)
ORIGINAL_SHA   <- digest::digest(file = NS, algo = "sha256")
restore <- function() writeLines(ORIGINAL_LINES, NS)
# The artifact is a tracked file the manuscript reads. If this script dies
# mid-mutation it must not leave a corrupted study on disk.
on.exit(restore(), add = TRUE)

read_ns  <- function() utils::read.csv(NS, stringsAsFactors = FALSE)
write_ns <- function(d) utils::write.csv(d, NS, row.names = FALSE)

# ---------------------------------------------------------------------------
# The mutants. Each is stated as the scientific lie it tells, not as a diff.
# ---------------------------------------------------------------------------
MUTANTS <- list(
  list(id = "headline_inflated",
       what = "Raise one subspecialty-year's population-weighted mean by 25%.",
       why  = "A fabricated improvement in access. The single most consequential
               edit anyone could make to this file, and the hardest to see.",
       f = function(d) { i <- which(d$subspecialty == "GO" & d$year == 2020)[1]
                         d$mean_pop_weighted_per100k[i] <-
                           d$mean_pop_weighted_per100k[i] * 1.25; d }),

  list(id = "threshold_shares_non_monotone",
       what = "Make share_ge_5 exceed share_ge_1.",
       why  = "The share of population at or above a HIGHER access threshold can
               never exceed the share above a lower one. Non-monotone shares are
               arithmetically impossible, so any run producing them is invalid.",
       f = function(d) { i <- which(d$share_ge_1 > 0)[1]
                         d$share_ge_5[i] <- d$share_ge_1[i] + 0.1; d }),

  list(id = "share_out_of_unit_interval",
       what = "Push a population share above 1.",
       why  = "A share of the population cannot exceed 100%.",
       f = function(d) { d$share_ge_0[1] <- 1.4; d }),

  list(id = "population_not_conserved",
       what = "Shrink pop_valid_total without moving the excluded columns.",
       why  = "valid + excluded must equal the raster total. Breaking it means
               population vanished silently -- the exact failure that made the
               reproduction attempt land 0.786% low.",
       f = function(d) { d$pop_valid_total[1] <- d$pop_valid_total[1] * 0.9; d }),

  # NOTE: "zero the excluded population" was the obvious mutant here and is
  # NOT expressible on this artifact -- all 77 rows already carry zero excluded
  # population, so the edit was a silent no-op that looked like a surviving
  # mutant. The no-op guard below now catches that class outright. The lie it
  # was meant to express (population counted as measured when it was not) is
  # covered by population_not_conserved.
  list(id = "raster_pop_diverges_from_acs_source",
       what = "Change pop_raster_total away from the acs_pop_source it claims.",
       why  = "The rasterised population must reconcile with the ACS total it
               was built from. Divergence means the demand denominator is not
               the population the paper says it is, which rescales every
               accessibility value without touching a single access number.",
       f = function(d) { d$pop_raster_total[3] <- d$pop_raster_total[3] * 1.02; d }),

  list(id = "subspecialty_year_dropped",
       what = "Delete one subspecialty-year row.",
       why  = "A ragged table. Whichever cell is missing silently drops out of
               every mean and every trend, and the remaining years still look
               internally consistent.",
       f = function(d) d[-which(d$subspecialty == "MFM" & d$year == 2016)[1], ]),

  list(id = "row_duplicated",
       what = "Duplicate one subspecialty-year row.",
       why  = "Double-counts that cell in any aggregate, inflating its weight
               without changing any individual value.",
       f = function(d) rbind(d, d[which(d$subspecialty == "CFP" &
                                        d$year == 2020)[1], ])),

  list(id = "subspecialty_labels_swapped",
       what = "Swap the GO and CFP labels for every year.",
       why  = "Reverses which subspecialty is least accessible -- the direction
               of the headline finding -- while every number stays individually
               valid and every total is unchanged.",
       f = function(d) { g <- d$subspecialty == "GO"; c_ <- d$subspecialty == "CFP"
                         d$subspecialty[g] <- "CFP"; d$subspecialty[c_] <- "GO"; d }),

  list(id = "negative_access",
       what = "Make one mean access value negative.",
       why  = "Accessibility is supply over demand; it cannot be below zero.",
       f = function(d) { d$mean_pop_weighted_per100k[2] <- -1; d }),

  list(id = "year_shifted",
       what = "Shift every year by one for a single subspecialty.",
       why  = "Misaligns that subspecialty's trend against every other, which is
               how a decline becomes an increase without any value changing.",
       f = function(d) { i <- d$subspecialty == "REI"; d$year[i] <- d$year[i] + 1; d })
)

# ---------------------------------------------------------------------------
run_detector <- function() {
  out <- suppressWarnings(system2("Rscript", DETECTOR, stdout = TRUE, stderr = TRUE))
  st  <- attr(out, "status")
  list(failed = !is.null(st) && st != 0L, output = out)
}

cat("Data-adversarial corpus\n")
cat("  artifact: ", NS, "\n", sep = "")
cat("  detector: ", DETECTOR, " (the hash gate is deliberately NOT used)\n", sep = "")
cat("  mutants:  ", length(MUTANTS), "\n\n", sep = "")

# --- 2. CONTROL: the uncorrupted artifact must PASS -------------------------
base <- run_detector()
if (base$failed) {
  cat("::error::the UNCORRUPTED artifact already fails the invariants; every\n")
  cat("mutant would look killed for the wrong reason.\n")
  cat(paste(utils::tail(base$output, 15), collapse = "\n"), "\n")
  quit(status = 1L)
}
cat("control (uncorrupted): invariants PASS\n\n")

# --- 3. POISON: every corrupted artifact must FAIL --------------------------
survivors <- character(0); noops <- character(0); ran <- 0L
for (m in MUTANTS) {
  d <- tryCatch(m$f(read_ns()), error = function(e) NULL)
  if (is.null(d)) {
    cat(sprintf("  ERROR    %-32s (mutation could not be applied)\n", m$id))
    survivors <- c(survivors, m$id); restore(); next
  }
  write_ns(d)
  # A mutation that does not actually change the artifact is indistinguishable
  # from a detector that failed to notice one -- both read as "SURVIVED". That
  # happened here: zeroing an already-zero column edited nothing and looked
  # like an invariant gap for a full cycle. Silence must not look like success,
  # so a no-op is reported as a CORPUS BUG and fails the run on its own.
  if (identical(digest::digest(file = NS, algo = "sha256"), ORIGINAL_SHA)) {
    cat(sprintf("  NO-OP    %-32s (mutation changed nothing)\n", m$id))
    noops <- c(noops, m$id); restore(); ran <- ran + 1L; next
  }
  r <- run_detector()
  restore()
  ran <- ran + 1L
  if (r$failed) cat(sprintf("  KILLED   %-32s\n", m$id))
  else { cat(sprintf("  SURVIVED %-32s\n", m$id)); survivors <- c(survivors, m$id) }
}

# --- 1. EXECUTED, and the artifact is byte-identical afterwards -------------
restore()
final_sha <- digest::digest(file = NS, algo = "sha256")
cat("\n")
if (!identical(final_sha, ORIGINAL_SHA)) {
  cat("::error::the corpus did not restore the artifact byte-identically.\n")
  cat("  before ", ORIGINAL_SHA, "\n  after  ", final_sha, "\n", sep = "")
  quit(status = 1L)
}
cat("artifact restored byte-identically: ", substr(final_sha, 1, 16), "\n", sep = "")
if (ran != length(MUTANTS)) {
  cat("::error::only ", ran, " of ", length(MUTANTS), " mutants were evaluated.\n", sep = "")
  quit(status = 1L)
}
cat("every one of ", ran, " mutants was evaluated against a passing control\n", sep = "")

if (length(noops)) {
  cat("::error::", length(noops), " mutant(s) changed nothing: ",
      paste(noops, collapse = ", "), "\n", sep = "")
  cat("  A no-op mutant proves nothing and reads exactly like a detector gap.\n")
  cat("  Fix the mutation so it actually corrupts the artifact, or remove it.\n")
  quit(status = 1L)
}
if (length(survivors)) {
  cat("\n::error::", length(survivors), " data mutant(s) SURVIVED.\n", sep = "")
  for (id in survivors) {
    m <- Filter(function(x) identical(x$id, id), MUTANTS)[[1]]
    cat("\n  ", m$id, "\n", sep = "")
    cat("    corruption:  ", m$what, "\n", sep = "")
    cat("    consequence: ", gsub("\\s+", " ", m$why), "\n", sep = "")
  }
  cat("\n  A surviving mutant is a corruption that could enter a legitimate\n")
  cat("  re-run of the study, pass every check, and reach the manuscript.\n")
  quit(status = 1L)
}
cat("\nAll data mutants killed by the scientific invariants.\n")

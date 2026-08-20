#!/usr/bin/env Rscript
# =============================================================================
# The README must agree with the repository it describes
# =============================================================================
# The README is the front page: the first and often only thing a reader
# evaluates. It carries figures, counts and result claims, and every one of them
# can go stale silently -- exactly as the manuscript's verbal quantifiers could
# before they were gated, and as the abstract's "Disparities held across all
# sensitivity specifications" did until the specification curve falsified it.
#
# Hand-maintained numbers are the worst offenders because they look precise.
# "1653 assertions" and "35/35 exercised" were true the hour they were written
# and will drift the next time anyone adds a test.
#
# Checks, in order of how badly a failure would mislead a reader:
#   1. every referenced figure EXISTS in the repository
#   2. self-referential counts match what the tools actually report
#   3. claims about scientific results match the frozen artifacts
#   4. internal file links point at files that exist
#
# Usage: Rscript tools/ci/check_readme.R [--offline]
#   --offline skips nothing here; all checks are local by design, so this runs
#   in seconds and needs no network.

root <- tryCatch(rprojroot::find_root(rprojroot::has_file("DESCRIPTION")),
                 error = function(e) ".")
setwd(root)
rd <- readLines("README.md", warn = FALSE)
txt <- paste(rd, collapse = "\n")
# Badge URLs are percent-encoded: "35%2F35" and "1653%20assertions". Extracting
# digits from the raw text splices the encoding's own digits into the number --
# 1653 + %20 reads as 165320. Decode the two sequences that appear here before
# any numeric comparison.
dec <- function(x) gsub("%2F", "/", gsub("%20", " ", x, fixed = TRUE), fixed = TRUE)
txt <- dec(txt)
fail <- character(0)
note <- function(...) cat("  ", ..., "\n", sep = "")
bad  <- function(...) fail <<- c(fail, paste0(...))

cat("README consistency audit\n\n")

# ---- 1. figures referenced must exist ---------------------------------------
cat("figures\n")
figs <- regmatches(txt, gregexpr("!\\[[^]]*\\]\\([^)]+\\)", txt))[[1]]
repo_figs <- grep("shields\\.io|badge\\.svg", figs, value = TRUE, invert = TRUE)
paths <- sub("^.*/main/", "", sub("\\)$", "", sub("^!\\[[^]]*\\]\\(", "", repo_figs)))
missing <- paths[!file.exists(paths)]
note(length(paths), " repository figures referenced")
if (length(missing)) {
  for (m in missing) bad("README references a figure that does not exist: ", m)
} else note("all referenced figures exist on disk")

# ---- 2. self-referential counts ---------------------------------------------
cat("\nself-referential counts\n")
# assertions actually in the suite: count expect_* calls, the same unit the
# badge claims. Comments and strings stripped so prose cannot inflate it.
tf <- list.files("tests/testthat", pattern = "^test-.*[.]R$", full.names = TRUE)
src <- unlist(lapply(tf, function(f) {
  l <- readLines(f, warn = FALSE)
  l <- sub("(?<!\\\\)#.*$", "", l, perl = TRUE)
  gsub('"[^"]*"', '""', l)
}))
n_expect <- sum(vapply(gregexpr("\\bexpect_[a-z_]+\\(", src), function(m) sum(m > 0), integer(1)))

# mutants declared in the corpus
n_mut <- length(grep("^  [a-z0-9_]+ = list\\(", readLines("tools/ci/mutation_corpus.R", warn = FALSE)))

# CORE exports the coverage tool tracks
cov <- readLines("tools/ci/scientific_coverage.R", warn = FALSE)
i <- grep("^CORE <- c\\(", cov); j <- grep("^\\)$", cov); j <- j[j > i][1]
n_core <- length(unlist(regmatches(paste(cov[i:j], collapse = " "),
                                   gregexpr('"[A-Za-z0-9._]+"', paste(cov[i:j], collapse = " ")))))

# prespecified specifications
spec <- yaml::read_yaml("inst/multiverse/specification_manifest.yml")
n_exec <- sum(vapply(spec$specifications, function(s) identical(s$status, "frozen"), logical(1)))

claim_num <- function(pattern, label) {
  m <- regmatches(txt, regexpr(pattern, txt, perl = TRUE))
  if (!length(m)) { bad("README no longer states ", label, " -- the badge was removed or reworded"); return(NA_integer_) }
  as.integer(gsub("\\D", "", m))
}
c_mut  <- claim_num("scientific mutants-\\d+/\\d+", "the mutant count")
c_core <- claim_num("scientific core-\\d+/\\d+", "the core-coverage count")
c_spec <- claim_num("multiverse-\\d+ prespecified", "the specification count")

# mutants/core/spec are exact; the two-number badges encode N/N so compare halves
if (!is.na(c_mut)) {
  halves <- as.integer(strsplit(gsub("[^0-9]+", " ",
    regmatches(txt, regexpr("scientific mutants-\\d+/\\d+", txt))), " +")[[1]])
  halves <- halves[!is.na(halves)]
  note("mutants: README ", halves[1], "/", halves[2], "  corpus declares ", n_mut)
  if (!identical(halves[2], n_mut)) bad("README claims ", halves[2], " mutants; the corpus declares ", n_mut)
}
if (!is.na(c_core)) {
  halves <- as.integer(strsplit(gsub("[^0-9]+", " ",
    regmatches(txt, regexpr("scientific core-\\d+/\\d+", txt))), " +")[[1]])
  halves <- halves[!is.na(halves)]
  note("core exports: README ", halves[1], "/", halves[2], "  tool tracks ", n_core)
  if (!identical(halves[2], n_core)) bad("README claims ", halves[2], " CORE exports; the tool tracks ", n_core)
}
if (!is.na(c_spec)) {
  note("specifications: README ", c_spec, "  manifest has ", n_exec, " executable")
  if (!identical(c_spec, n_exec)) bad("README claims ", c_spec, " specifications; the manifest has ", n_exec, " executable")
}

# The assertion count is testthat's PASS tally, which is NOT the number of
# expect_* calls: an expectation inside a loop contributes many. Comparing the
# badge to a static call count would flag a correct badge, so compare against
# the accounting the suite itself recorded, when a run has produced one.
m <- regmatches(txt, regexpr("tests-\\d+ assertions", txt))
acct <- "artifacts/ci/testthat-accounting.txt"
if (length(m) && file.exists(acct)) {
  claimed <- as.integer(gsub("\\D", "", m))
  line <- paste(readLines(acct, warn = FALSE), collapse = " ")
  actual <- suppressWarnings(as.integer(sub(".*PASS[^0-9]*([0-9]+).*", "\\1", line)))
  if (!is.na(actual)) {
    note("assertions: README ", claimed, "  last recorded suite run ", actual)
    # Overclaiming is the failure that misleads; undercounting is merely stale.
    if (claimed > actual)
      bad("README claims ", claimed, " assertions but the last recorded run had ",
          actual, ". Overclaiming test coverage on the front page.")
  }
} else if (length(m)) {
  note("assertions: README ", as.integer(gsub("\\D", "", m)),
       "  (no recorded suite accounting yet; nightly writes ", acct, ")")
}

# ---- 3. result claims must match the frozen artifacts -----------------------
cat("\nscientific result claims\n")
if (file.exists("artifacts/multiverse/claim_matrix.csv")) {
  cm <- utils::read.csv("artifacts/multiverse/claim_matrix.csv", stringsAsFactors = FALSE)
  rural_all <- all(as.logical(cm$C2))
  aian_all  <- all(as.logical(cm$C3))
  note("multiverse: rural disparity holds in all specs = ", rural_all,
       "; AIAN in all specs = ", aian_all)
  # The README says the rural disparity holds in all seven and the AIAN one
  # does not. If that ever flips, the front page is asserting a falsehood.
  # Checked in BOTH directions. An earlier version only caught the README
  # UNDERSTATING robustness, so rewording "contrast does not" into "contrast
  # also holds" -- asserting a robustness the multiverse denies -- passed
  # silently. Overstating is the more damaging error, and it was the one that
  # slipped through. Found by negative-testing this checker.
  says_rural_holds <- grepl("rural.{0,40}disparity holds in all seven", txt, perl = TRUE)
  says_aian_fails  <- grepl("contrast does not|does not[^.]{0,30}hold|reverses", txt, perl = TRUE)
  says_aian_holds  <- grepl("contrast also holds|AIAN[^.]{0,60}holds in all|both[^.]{0,40}hold in all",
                            txt, perl = TRUE)
  if (says_rural_holds && !rural_all)
    bad("README says the rural disparity holds in all seven specifications; the multiverse disagrees")
  if (says_aian_fails && aian_all)
    bad("README says the AIAN contrast does NOT hold everywhere; the multiverse says it does")
  if (says_aian_holds && !aian_all)
    bad("README asserts the AIAN contrast holds everywhere, but the multiverse shows it ",
        "reverses under at least one prespecified specification. Overstating robustness ",
        "on the front page is the same error the abstract made.")
  if (!says_rural_holds && !says_aian_fails && !says_aian_holds)
    bad("README no longer describes the multiverse result at all. The specification ",
        "curve falsified a manuscript claim; silently dropping that from the front ",
        "page is not a neutral edit.")
} else note("multiverse claim matrix absent -- run tools/multiverse/run_multiverse.R")

# CFP distance from parity, quoted as "2.5% from parity"
if (file.exists("artifacts/2sfca/sensitivity/sensitivity_2020.csv")) {
  s <- utils::read.csv("artifacts/2sfca/sensitivity/sensitivity_2020.csv", stringsAsFactors = FALSE)
  cfp <- s$aian_white_ratio[s$variant == "base" & s$subspec == "CFP"]
  from_parity <- 100 * (1 - cfp)
  m <- regmatches(txt, regexpr("sits ([0-9.]+)% from parity", txt))
  if (length(m)) {
    claimed <- as.numeric(gsub("[^0-9.]", "", m))
    note("CFP distance from parity: README ", claimed, "%  artifact ", round(from_parity, 2), "%")
    if (abs(claimed - from_parity) > 0.5)
      bad("README says CFP sits ", claimed, "% from parity; the frozen artifact gives ",
          round(from_parity, 2), "%")
  }
}

# ---- 4. internal links must resolve ------------------------------------------
cat("\ninternal links\n")
links <- unlist(regmatches(txt, gregexpr("\\]\\(([^)h][^)]*)\\)", txt)))
links <- sub("\\)$", "", sub("^\\]\\(", "", links))
links <- links[!grepl("^#", links)]
links <- sub("#.*$", "", links)
links <- links[nzchar(links)]
dead <- unique(links[!file.exists(links)])
note(length(unique(links)), " internal links")
if (length(dead)) for (d in dead) bad("README links to a path that does not exist: ", d)

# ---- verdict -----------------------------------------------------------------
cat("\n")
if (length(fail)) {
  message("FAIL: the README disagrees with the repository:")
  for (f in fail) message("  - ", f)
  message("\n  The README is the front page. A stale count or a missing figure there",
          "\n  misleads more readers than the same error anywhere else.")
  quit(status = 1L, save = "no")
}
cat("README agrees with the repository\n")

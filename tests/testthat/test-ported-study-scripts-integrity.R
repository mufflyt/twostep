# ==============================================================================
# Integrity of the six study scripts ported from isochrones, 2026-08-18.
# ==============================================================================
# WHAT MOTIVATED THE MIGRATION
#   `feature/seven-subspecialty-expansion` deleted R/accessibility_stratification.R
#   while twelve files still source()d it. Those source() calls resolved to a file
#   that did not exist: the branch was broken, silently, because nothing ever
#   parsed those scripts in CI.
#
#   Six of the twelve compute ACCESS and therefore belong here. Moving them
#   introduced exactly one rewiring risk: isochrones reaches the frozen-run
#   pointer via R/e2sfca_frozen_run.R, a file this repo does not have. If that
#   line survives the move, the script dies on the first line that needs
#   E2SFCA_FROZEN_RUN_ID -- the same class of breakage the migration was fixing.
#
# WHAT THIS ASSERTS
#   For every ported script: it parses; it reaches only dependencies that exist
#   HERE; it carries no isochrones-only source(); and it defines no local copy of
#   an SSOT primitive. All checks are static, so they run without the production
#   artifacts the scripts themselves need.
# ==============================================================================

suppressWarnings(suppressMessages(library(testthat)))
.root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION") | rprojroot::is_git_root)

PORTED <- c(
  "scripts/cell_level_zero_access_2020.R",
  "scripts/desjardins7/00_build_data.R",
  "scripts/desjardins7/09_surface_recovery.R",
  "scripts/desjardins7/10_rebuild_workforce_recovery.R",
  "scripts/desjardins7/13_decay_weight_sensitivity.R",
  "scripts/seam_test_subgroup.R")

# SSOT primitives that must come from mufflyaccess (via R/accessibility_stratification.R),
# never be redefined locally in a study script.
SSOT_FNS <- c("weighted_mean_all", "zero_access_share", "rurality_from_ruca",
              "tract_vintage_of", "acs_year_of", "mc_weighted_ci", "annual_trend")

test_that("all six ported scripts are present", {
  for (p in PORTED) {
    expect_true(file.exists(file.path(.root, p)), info = paste(p, "is missing"))
  }
})

test_that("all six parse", {
  # The cheapest possible guard against the breakage that motivated this: on the
  # isochrones feature branch these scripts were never parsed by anything.
  for (p in PORTED) {
    expect_silent(invisible(parse(file.path(.root, p), keep.source = FALSE)))
  }
})

test_that("NEGATIVE CONTROL: no script still sources isochrones-only R/e2sfca_frozen_run.R", {
  # This is the exact line the port had to rewire. If a future re-copy from
  # isochrones reintroduces it, this fails instead of dying at runtime.
  for (p in PORTED) {
    src <- paste(readLines(file.path(.root, p), warn = FALSE), collapse = "\n")
    expect_false(grepl("e2sfca_frozen_run", src, fixed = TRUE),
                 info = paste(p, "still sources isochrones' R/e2sfca_frozen_run.R,",
                              "which does not exist in this repo"))
  }
})

test_that("every source() target in a ported script exists in THIS repo", {
  # Follows the parsed calls rather than grepping, so a renamed dependency is
  # caught wherever it appears in the file.
  for (p in PORTED) {
    exprs <- parse(file.path(.root, p), keep.source = FALSE)
    targets <- character(0)
    walk <- function(e) {
      if (is.call(e)) {
        if (identical(as.character(e[[1]])[1], "source")) {
          lits <- unlist(lapply(as.list(e)[-1], function(a) {
            if (is.call(a)) Filter(is.character, as.list(a)[-1]) else NULL
          }))
          if (length(lits)) targets <<- c(targets, do.call(file.path, as.list(lits)))
        }
        for (a in as.list(e)[-1]) if (!missing(a)) try(walk(a), silent = TRUE)
      }
    }
    for (e in exprs) walk(e)
    for (t in unique(targets)) {
      expect_true(file.exists(file.path(.root, t)),
                  info = paste0(p, " sources '", t, "', which does not exist here"))
    }
  }
})

test_that("NO DUPLICATE IMPLEMENTATIONS: no ported script redefines an SSOT primitive", {
  # The whole point of the mufflyaccess SSOT is that exactly one definition
  # exists. A convenience copy pasted into a study script is how drift restarts.
  for (p in PORTED) {
    exprs <- parse(file.path(.root, p), keep.source = FALSE)
    defined <- character(0)
    for (e in exprs) {
      if (is.call(e) && length(e) >= 3 &&
          as.character(e[[1]])[1] %in% c("<-", "=") && is.name(e[[2]])) {
        rhs <- e[[3]]
        if (is.call(rhs) && identical(as.character(rhs[[1]])[1], "function")) {
          defined <- c(defined, as.character(e[[2]]))
        }
      }
    }
    clash <- intersect(defined, SSOT_FNS)
    expect_identical(clash, character(0),
                     info = paste0(p, " defines a local copy of: ",
                                   paste(clash, collapse = ", ")))
  }
})

test_that("the frozen-run pointer resolves here, and its env override still works", {
  # Preserves the command-line/environment contract the scripts were written
  # against: E2SFCA_RUN_ID overrides the frozen id.
  env <- new.env(parent = globalenv())
  sys.source(file.path(.root, "scripts", "manuscript_e2sfca_values.R"), envir = env)
  expect_true(exists("E2SFCA_FROZEN_RUN_ID", envir = env))
  expect_match(get("E2SFCA_FROZEN_RUN_ID", envir = env), "^e2sfca_[0-9]{8}_[0-9]{6}$")

  old <- Sys.getenv("E2SFCA_RUN_ID", unset = NA)
  on.exit(if (is.na(old)) Sys.unsetenv("E2SFCA_RUN_ID") else Sys.setenv(E2SFCA_RUN_ID = old))
  Sys.setenv(E2SFCA_RUN_ID = "e2sfca_19990101_000000")
  env2 <- new.env(parent = globalenv())
  sys.source(file.path(.root, "scripts", "manuscript_e2sfca_values.R"), envir = env2)
  expect_identical(get("E2SFCA_FROZEN_RUN_ID", envir = env2), "e2sfca_19990101_000000")
})

test_that("REGRESSION: twostep now owns a generator for every published study artifact", {
  # Two results were committed here with no generating code -- results without a
  # generator are not reproducible. Porting closed that; this keeps it closed.
  pairs <- list(
    c("artifacts/2sfca/cell_zero/cell_zero_2020.csv",   "scripts/cell_level_zero_access_2020.R"),
    c("artifacts/2sfca/seam_subgroup/seam_subgroup.csv", "scripts/seam_test_subgroup.R"))
  for (pr in pairs) {
    if (file.exists(file.path(.root, pr[1]))) {
      expect_true(file.exists(file.path(.root, pr[2])),
                  info = paste0(pr[1], " is published here but its generator ",
                                pr[2], " is missing"))
    }
  }
})

# ==============================================================================
# The allocator identity gate must be pinned to THIS repo's engine.
# ==============================================================================
# THE BUG THIS PINS
#   scripts/run_2sfca.R fails closed unless sha256(R/two_step_floating_catchment.R)
#   equals SEAM_ALLOCATOR_SHA256. On 2026-08-18 that constant was found STALE: it
#   still carried 11abdec3, from before the 2026-08-16 engine work (53cfd45,
#   998ad40, a5ed663, ce7841c), while the engine hashed to e162507c. The gate was
#   therefore failing closed against its own repo -- every production run blocked,
#   and the failure looks like tampering rather than like a forgotten re-pin.
#
#   Nothing detected that, because the constant and the file it hashes were only
#   ever compared at RUN time, on a machine with the production inputs.
#
#   The neighbouring trap: the sibling repo (isochrones) pins 674f7113, which is
#   the hash of THEIR engine file. Copying a sibling's constant across repos
#   produces exactly the same fail-closed breakage while looking like a fix.
#
# WHAT THIS ASSERTS
#   (1) the pinned constant equals this repo's actual engine hash;
#   (2) the gated allocator's BODY still matches the seam-validated lineage,
#       which is the condition the gate's own protocol requires for a re-pin.
# ==============================================================================

suppressWarnings(suppressMessages(library(testthat)))
.root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION") | rprojroot::is_git_root)

.engine_path <- file.path(.root, "R", "two_step_floating_catchment.R")
.script_path <- file.path(.root, "scripts", "run_2sfca.R")

# Pull the pinned default out of `Sys.getenv("E2SFCA_SEAM_ALLOCATOR_SHA256", "<lit>")`
# by PARSING run_2sfca.R, not by running it (the script needs production inputs).
.pinned_sha <- local({
  found <- NA_character_
  for (e in parse(.script_path, keep.source = FALSE)) {
    if (is.call(e) && length(e) >= 3 &&
        as.character(e[[1]])[1] %in% c("<-", "=") &&
        identical(as.character(e[[2]]), "SEAM_ALLOCATOR_SHA256")) {
      rhs <- e[[3]]
      # Sys.getenv(name, default) -> take the default literal
      if (is.call(rhs) && grepl("Sys.getenv", paste(deparse(rhs[[1]]), collapse = ""))) {
        args <- as.list(rhs)[-1]
        lits <- Filter(is.character, args)
        if (length(lits) >= 2) found <- lits[[2]] else if (length(lits) == 1) found <- lits[[1]]
      } else if (is.character(rhs)) {
        found <- rhs
      }
    }
  }
  found
})

test_that("the pinned constant was found in run_2sfca.R", {
  # If this fails the rest cannot be trusted -- the parse shape changed.
  expect_true(is.character(.pinned_sha) && !is.na(.pinned_sha))
  expect_match(.pinned_sha, "^[0-9a-f]{64}$")
})

test_that("SEAM_ALLOCATOR_SHA256 matches THIS repo's engine file", {
  # THE CORE ASSERTION. Fails the moment someone edits the engine without
  # re-pinning, or pastes a sibling repo's constant.
  skip_if_not(file.exists(.engine_path), "engine file not present")
  actual <- digest::digest(file = .engine_path, algo = "sha256")
  expect_identical(
    .pinned_sha, actual,
    info = paste0(
      "Allocator gate is out of sync. Pinned=", substr(.pinned_sha, 1, 12),
      " actual=", substr(actual, 1, 12),
      ". Re-pin ONLY after checking the allocator body per the protocol in ",
      "run_2sfca.R; do NOT copy the constant from another repo."))
})

test_that("NEGATIVE CONTROL: the historic stale pin does NOT match the engine", {
  # Proves this suite would have FAILED before the 2026-08-18 re-pin, rather
  # than being a tautology that passes whatever the file says.
  skip_if_not(file.exists(.engine_path), "engine file not present")
  stale_pin <- "11abdec3e577e81e098846c51e71821a3b3d0ad12b69c0d8d597d06cbd48362a"
  actual    <- digest::digest(file = .engine_path, algo = "sha256")
  expect_false(identical(stale_pin, actual))
})

test_that("NEGATIVE CONTROL: the sibling repo's pin does NOT match this engine", {
  # 674f7113 is isochrones' engine hash. Adopting it here would re-break the
  # gate while looking like a correction.
  skip_if_not(file.exists(.engine_path), "engine file not present")
  sibling_pin <- "674f7113992504bea41626d2ac97bc8f3ed55383a9a03c9dd22afd7aa314b08a"
  actual      <- digest::digest(file = .engine_path, algo = "sha256")
  expect_false(identical(sibling_pin, actual))
  expect_false(identical(.pinned_sha, sibling_pin))
})

test_that("the gated allocator body still matches the seam-validated lineage", {
  # The gate hashes the WHOLE file, so it trips on any edit -- including edits to
  # functions the seam test never certified. The protocol says a re-pin is only
  # legitimate while allocate_pop_areaweighted's BODY is unchanged. This encodes
  # that precondition so a future re-pin cannot quietly skip it.
  skip_if_not(file.exists(.engine_path), "engine file not present")

  defs <- new.env(parent = emptyenv())
  for (e in parse(.engine_path, keep.source = FALSE)) {
    if (is.call(e) && length(e) >= 3 &&
        as.character(e[[1]])[1] %in% c("<-", "=") && is.name(e[[2]])) {
      rhs <- e[[3]]
      if (is.call(rhs) && identical(as.character(rhs[[1]])[1], "function")) {
        assign(as.character(e[[2]]),
               paste(deparse(rhs), collapse = "\n"), envir = defs)
      }
    }
  }

  # Deparsed-definition hashes certified 2026-08-18 as byte-identical to the
  # seam-validated ancestor ff3aac4a (via isochrones@origin/main).
  certified <- c(
    allocate_pop_areaweighted  = "f25bfdfaff3a",
    build_e2sfca_raster_grid   = "0ea5d3135509",
    build_e2sfca_grid_geometry = "4e42d9a390ac",
    e2sfca_cell_summaries      = "5e612404610f",
    compute_provider_supply    = "79d204f4320f",
    e2sfca_incremental_weights = "f5bc77a8138a")

  for (fn in names(certified)) {
    expect_true(exists(fn, envir = defs), info = paste(fn, "vanished from the engine"))
    got <- substr(digest::digest(get(fn, envir = defs), algo = "sha256",
                                 serialize = FALSE), 1, 12)
    expect_identical(
      got, unname(certified[fn]),
      info = paste0(fn, "() changed (", got, " != ", certified[fn],
                    "). The seam gate certified the OLD body: re-run the seam ",
                    "test, do not simply re-pin the file hash."))
  }
})

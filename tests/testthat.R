# Standalone test entrypoint. The three E2SFCA test files source the engine
# directly (via rprojroot / test_path) and use only inline fixtures, so no
# setup.R or helper files are required.
if (!requireNamespace("here", quietly = TRUE))
  stop("tests/testthat.R requires the `here` package.", call. = FALSE)
testthat::test_dir(here::here("tests/testthat"))

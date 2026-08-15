#!/usr/bin/env Rscript
# Installed-package isolation smoke test.
#
# Run from a working directory OUTSIDE the repository, against twostep installed
# from the tarball. This is the only check that can catch a function which
# silently depends on the source tree -- here::here(), a relative path, an
# untracked file, or a package that happens to sit in a developer library. Inside
# the repo every one of those resolves by accident.
stopifnot(requireNamespace("twostep", quietly = TRUE))
library(twostep)

wd <- getwd()
cat("working directory:", wd, "\n")
cat("twostep", as.character(packageVersion("twostep")),
    "from", dirname(system.file(package = "twostep")), "\n")

# Guard the guard: if this somehow runs inside a checkout, the test proves nothing.
if (file.exists(file.path(wd, "DESCRIPTION")) && file.exists(file.path(wd, "R")))
  stop("smoke test must run OUTSIDE the repository; it is in a source tree", call. = FALSE)

ok <- function(what) cat("  ok:", what, "\n")

# --- exported constants resolve without the source tree -------------------------
stopifnot(is.numeric(CANONICAL_BANDS), length(CANONICAL_BANDS) > 0)
stopifnot(identical(get_canonical_bands(), CANONICAL_BANDS))
ok("CANONICAL_BANDS / get_canonical_bands()")

stopifnot(PRIMARY_ACCESS_BAND_SEC == PRIMARY_ACCESS_BAND_MIN * 60L)
ok("primary access band constants agree")

# These three carried @export tags that never reached NAMESPACE. They are the
# original bug, so the smoke test asserts them by name from the INSTALLED package.
stopifnot(is.character(DJ7_SUBS), length(DJ7_SUBS) == 7L)
stopifnot(is.numeric(DJ7_BANDS), length(DJ7_BANDS) == 4L)
stopifnot(is.numeric(DJ7_WC_BASE), identical(names(DJ7_WC_BASE), as.character(DJ7_BANDS)))
ok("DJ7_SUBS / DJ7_BANDS / DJ7_WC_BASE -- the three exports that were missing")

# --- the distance-decay weight chain --------------------------------------------
w <- e2sfca_band_weights()
stopifnot(is.numeric(w), !is.unsorted(rev(w)), all(w >= 0))
ok("e2sfca_band_weights() defaults and is monotone non-increasing")

inc1 <- e2sfca_incremental_weights(c("30" = 1, "60" = 0.5), step2_power = 1)
stopifnot(all.equal(unname(inc1), c(0.5, 0.5)))
inc2 <- e2sfca_incremental_weights(c("30" = 1, "60" = 0.5), step2_power = 2)
stopifnot(all.equal(unname(inc2), c(0.75, 0.25)))
ok("E2SFCA and M2SFCA incremental weights match their analytic values")

g <- gaussian_band_weights(c(30, 60, 120, 180), sigma = 60)
stopifnot(is.numeric(g), all(g >= 0), all(diff(g) <= 1e-9))
ok("gaussian_band_weights() is non-increasing in band")

# --- a function that takes data, on a synthetic frame ---------------------------
df <- data.frame(a = c(1, 2, 3, 4, 5, 6, 7, 8, 9),
                 b = c(9, 8, 7, 6, 5, 4, 3, 2, 1))
cl <- classify_bivariate(df, "a", "b", n_bins = 3, method = "quantile")
stopifnot(nrow(cl) == nrow(df), "bivar_class" %in% names(cl))
ok("classify_bivariate() on a synthetic frame")

# --- errors are still errors ------------------------------------------------------
bad <- tryCatch({ e2sfca_band_weights(c("30" = 0.5, "60" = 1)); FALSE },
                error = function(e) TRUE)
stopifnot(bad)
ok("non-monotone weights are rejected")

cat("\ninstalled-package isolation smoke test PASSED\n")

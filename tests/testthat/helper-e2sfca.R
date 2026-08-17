# =============================================================================
# Shared harness for the E2SFCA scientific-validity tests.
# =============================================================================
# Holds the fixture generators and the two INDEPENDENT reference
# implementations, so that every scientific test file draws on the same
# machinery rather than re-deriving it. Three implementations exist on purpose:
#
#   production   R/two_step_floating_catchment.R   vectorised dplyr
#   reference    ref_e2sfca()                      base-R triple loop
#   matrix       ref_e2sfca_matrix()               linear algebra
#
# They are derived differently -- accumulation, explicit iteration, and matrix
# products -- so a shared misconception is far less likely than with two. Any
# two agreeing while the third dissents localises the error immediately.
#
# The method, from the module header of the engine:
#   Step 1   R_j = S_j / SUM_{i,b} w'_b  f_jbi pop_i
#   Step 2   A_i = SUM_{j,b}      w'a_b  f_jbi R_j
#   w'_b = W_b - W_{b+1};  w'a_b = W_b^p - W_{b+1}^p;  W beyond last band = 0.
suppressWarnings(suppressMessages(library(testthat)))
source(file.path(rprojroot::find_root(rprojroot::has_file("DESCRIPTION") |
                                        rprojroot::is_git_root),
                 "R", "two_step_floating_catchment.R"))

# --- incremental weights, derived independently of the engine ----------------
ref_incremental <- function(W, power = 1) {
  W <- W[order(as.integer(names(W)))]
  wp <- as.numeric(W)^power
  stats::setNames(wp - c(wp[-1L], 0), names(W))
}

# --- reference 1: explicit accumulation --------------------------------------
ref_e2sfca <- function(overlap, tract_pop, supply, W, step2_power = 1,
                       pop_col = "female_pop", per_capita_scale = 1e5) {
  inc_d <- ref_incremental(W, 1)
  inc_a <- ref_incremental(W, step2_power)
  pop <- stats::setNames(as.numeric(tract_pop[[pop_col]]), as.character(tract_pop$GEOID))
  pop[is.na(pop)] <- 0
  sup <- stats::setNames(as.numeric(supply$supply), as.character(supply$coord_id))

  demand <- stats::setNames(rep(0, length(sup)), names(sup))
  for (r in seq_len(nrow(overlap))) {
    j <- as.character(overlap$coord_id[r]); b <- as.character(overlap$band[r])
    if (!j %in% names(sup) || !b %in% names(inc_d)) next
    g <- as.character(overlap$GEOID[r])
    p <- if (g %in% names(pop)) pop[[g]] else 0
    demand[[j]] <- demand[[j]] + inc_d[[b]] * overlap$overlap_fraction[r] * p
  }
  ratio <- ifelse(demand > 0, sup / demand, 0); names(ratio) <- names(sup)

  # Enumerate from tract_pop, NOT from overlap: a tract that no provider reaches
  # has access 0 and must still appear. Dropping it would silently shrink the
  # denominator, which is the failure mode that makes a percentage meaningless.
  # Production does the same via left_join(distinct(pop, GEOID), access).
  geoids <- sort(unique(c(as.character(tract_pop$GEOID),
                          as.character(overlap$GEOID))))
  access <- stats::setNames(rep(0, length(geoids)), geoids)
  for (r in seq_len(nrow(overlap))) {
    j <- as.character(overlap$coord_id[r]); b <- as.character(overlap$band[r])
    if (!j %in% names(sup) || !b %in% names(inc_a)) next
    g <- as.character(overlap$GEOID[r])
    access[[g]] <- access[[g]] + inc_a[[b]] * overlap$overlap_fraction[r] * ratio[[j]]
  }
  data.frame(GEOID = names(access), access = as.numeric(access),
             access_scaled = as.numeric(access) * per_capita_scale,
             stringsAsFactors = FALSE)
}

# --- reference 2: matrix algebra ---------------------------------------------
# Builds the weighted provider-by-tract matrix M[j,i] = SUM_b w'_b f_jbi and
# reads both steps off it:  D = M1 %*% pop ,  A = t(M2) %*% (S / D).
# No loop over rows at all, so a row-ordering or accumulation bug in the other
# two implementations cannot be reproduced here.
ref_e2sfca_matrix <- function(overlap, tract_pop, supply, W, step2_power = 1,
                              pop_col = "female_pop", per_capita_scale = 1e5) {
  inc_d <- ref_incremental(W, 1)
  inc_a <- ref_incremental(W, step2_power)
  js <- as.character(supply$coord_id)
  # See the note in ref_e2sfca(): unreached tracts stay, with access 0.
  gs <- sort(unique(c(as.character(tract_pop$GEOID),
                      as.character(overlap$GEOID))))

  o <- overlap[as.character(overlap$coord_id) %in% js &
                 as.character(overlap$band) %in% names(inc_d), , drop = FALSE]
  jj <- match(as.character(o$coord_id), js)
  ii <- match(as.character(o$GEOID), gs)
  bb <- as.character(o$band)

  M1 <- matrix(0, nrow = length(js), ncol = length(gs), dimnames = list(js, gs))
  M2 <- M1
  # tapply-free accumulation via matrix indexing; duplicates must add, so use
  # a sparse-style accumulation through rowsum on a linear index.
  lin <- (ii - 1L) * length(js) + jj
  v1 <- inc_d[bb] * o$overlap_fraction
  v2 <- inc_a[bb] * o$overlap_fraction
  agg1 <- rowsum(as.numeric(v1), group = lin, reorder = TRUE)
  agg2 <- rowsum(as.numeric(v2), group = lin, reorder = TRUE)
  M1[as.integer(rownames(agg1))] <- agg1[, 1]
  M2[as.integer(rownames(agg2))] <- agg2[, 1]

  popv <- stats::setNames(as.numeric(tract_pop[[pop_col]]), as.character(tract_pop$GEOID))
  popv[is.na(popv)] <- 0
  pv <- ifelse(gs %in% names(popv), popv[gs], 0); pv[is.na(pv)] <- 0

  D <- as.numeric(M1 %*% pv)
  S <- as.numeric(supply$supply)
  R <- ifelse(D > 0, S / D, 0)
  A <- as.numeric(t(M2) %*% R)
  data.frame(GEOID = gs, access = A, access_scaled = A * per_capita_scale,
             stringsAsFactors = FALSE)
}

# The canonical four-band cumulative weights, used throughout the scientific suites.
W4 <- E2SFCA_DEFAULT_WEIGHTS

# --- production, normalised for comparison -----------------------------------
prod_access <- function(fx, W = E2SFCA_DEFAULT_WEIGHTS, ...) {
  r <- compute_e2sfca(fx$overlap, fx$tract_pop, fx$supply, weights = W, ...)
  a <- as.data.frame(r$access)
  # Carries both score columns: `access` is the scientific value (NA outside
  # every modelled catchment) and `access_math` the algebraic zero-filled form.
  # Reference implementations in these tests compute the algebraic form, so
  # invariant comparisons use `access_math`; anything asserting what a reader
  # would see uses `access`.
  a[order(a$GEOID), c("GEOID", "access", "access_math", "coverage_status")]
}

# --- randomized fixture ------------------------------------------------------
# Deliberately nasty: zero-supply providers, zero-population tracts, providers
# reaching no tract, partial overlaps, cumulative-band monotonicity.
make_fixture <- function(seed, n_prov = 4, n_tract = 6,
                         bands = c(30, 60, 120, 180)) {
  set.seed(seed)
  coord <- paste0("P", seq_len(n_prov))
  geo   <- sprintf("%011d", seq_len(n_tract))
  rows <- expand.grid(coord_id = coord, GEOID = geo, band = bands,
                      KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  base_f <- stats::runif(n_prov * n_tract)
  base_f[sample.int(length(base_f), size = max(1L, length(base_f) %/% 4L))] <- 0
  key <- paste(rows$coord_id, rows$GEOID); ukey <- unique(key)
  f0 <- stats::setNames(base_f[seq_along(ukey)], ukey)
  band_scale <- stats::setNames(seq_along(bands) / length(bands), as.character(bands))
  rows$overlap_fraction <- pmin(1, f0[key] * band_scale[as.character(rows$band)])
  rows <- rows[rows$overlap_fraction > 0, , drop = FALSE]
  rownames(rows) <- NULL

  pop <- data.frame(GEOID = geo, female_pop = round(stats::runif(n_tract, 0, 5000)),
                    stringsAsFactors = FALSE)
  pop$female_pop[sample.int(n_tract, 1)] <- 0
  sup <- data.frame(coord_id = coord, supply = round(stats::runif(n_prov, 0, 20)),
                    stringsAsFactors = FALSE)
  sup$supply[sample.int(n_prov, 1)] <- 0
  list(overlap = rows, tract_pop = pop, supply = sup)
}

# --- a deterministic two-component system ------------------------------------
# Two mutually unreachable halves. Because no provider in one half touches any
# tract in the other, each half's accessibility is exactly what it would be in
# isolation -- which makes it both a closed-form fixture and a join-leak
# detector.
make_two_component <- function(seed, n_each = 5, prov_each = 3,
                               bands = c(30, 60)) {
  set.seed(seed)
  mk <- function(tag, off) {
    coord <- paste0(tag, "P", seq_len(prov_each))
    geo   <- sprintf("%011d", off + seq_len(n_each))
    rows  <- expand.grid(coord_id = coord, GEOID = geo, band = bands,
                         KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
    f0 <- stats::setNames(stats::runif(prov_each * n_each, 0.05, 1),
                          unique(paste(rows$coord_id, rows$GEOID)))
    bs <- stats::setNames(seq_along(bands) / length(bands), as.character(bands))
    rows$overlap_fraction <- pmin(1, f0[paste(rows$coord_id, rows$GEOID)] *
                                    bs[as.character(rows$band)])
    list(overlap = rows,
         pop = data.frame(GEOID = geo,
                          female_pop = round(stats::runif(n_each, 100, 5000)),
                          stringsAsFactors = FALSE),
         sup = data.frame(coord_id = coord,
                          supply = round(stats::runif(prov_each, 1, 20)),
                          stringsAsFactors = FALSE))
  }
  A <- mk("A", 0); B <- mk("B", 1000)
  list(A = A, B = B,
       combined = list(
         overlap   = rbind(A$overlap, B$overlap),
         tract_pop = rbind(A$pop, B$pop),
         supply    = rbind(A$sup, B$sup)))
}

# Population-weighted mean accessibility over a set of tracts.
pw_mean_access <- function(access_df, pop_df, geoids) {
  a <- access_df$access[match(geoids, access_df$GEOID)]
  p <- pop_df$female_pop[match(geoids, pop_df$GEOID)]
  a[is.na(a)] <- 0; p[is.na(p)] <- 0
  if (sum(p) == 0) return(0)
  sum(a * p) / sum(p)
}

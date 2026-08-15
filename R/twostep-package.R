#' @keywords internal
"_PACKAGE"

# ==============================================================================
# Namespace imports and NSE symbol registration.
# ==============================================================================
# Most of twostep calls dependencies with explicit `pkg::fn()` prefixes, so it
# needs almost no imports. The exception is R/generate_bivariate_choropleth.R,
# which predates the package layout and called dplyr / sf / here functions
# unprefixed, relying on top-level `library()` calls that attached them at load
# time. `R CMD check` reported every one of those as "no visible global function
# definition", because an attach is not an import: the calls resolved only by
# luck of the search path. Importing them here is what actually binds them into
# the package namespace.
#
# ggplot2 is deliberately NOT imported, even though it is now pinned in
# renv.lock. Only the reference-only bivariate-map function uses it, so an
# import would make every consumer of the E2SFCA engine load a plotting stack
# they never call. It stays in Suggests with `ggplot2::fn()` call sites, so that
# function errors only when it is actually invoked without ggplot2, rather than
# breaking package load for everyone. Same treatment as BAMMtools and cowplot,
# which are also Suggests-and-guarded and are not in renv.lock at all.
#' @importFrom dplyr %>% left_join select group_by summarise n arrange
#' @importFrom sf st_drop_geometry
#' @importFrom here here
#' @importFrom stats quantile
NULL

# Column names used in dplyr non-standard evaluation. They are data-frame columns
# resolved at run time, not objects in scope, so R's code analysis reports them as
# undefined globals. Declaring them silences that without weakening the check for
# genuine typos elsewhere.
utils::globalVariables(c(
  # --- two_step_floating_catchment.R -----------------------------------------
  "GEOID", "coord_id", "band", "overlap_fraction", "w_inc", "w_acc",
  "weighted_demand", "wf", "wf_a", "ratio_for_surface", "cum_pop",
  "access_mean_area", "access_mean_population",
  # --- compute_provider_supply / urps ----------------------------------------
  "npi", "analysis_year", "match_source",
  # --- generate_bivariate_choropleth.R ---------------------------------------
  "var1_class", "var2_class", "bivar_class", "color", "x", "y",
  # --- calculate_subspecialty_accessibility.R --------------------------------
  "drive_time_minutes",
  # --- rlang data pronoun, used with .data[[col]] indexing -------------------
  ".data"
))

# The ARCHIVED subspecialty module calls two helpers that are source()d off disk
# at run time from files never vendored into this repo, so they are absent from
# the namespace by construction and the module cannot run as-is -- see its header.
# Registering them keeps `R CMD check` quiet about that KNOWN gap without hiding
# genuine typos in live code.
utils::globalVariables(c("safe_st_union", "calculate_area_weighted_allocation"))

#!/usr/bin/env Rscript

# =============================================================================
# BIVARIATE CHOROPLETH MAP GENERATOR
# =============================================================================
#
# Purpose: Create bivariate choropleth maps showing relationship between
#          two variables (e.g., female population × subspecialist access)
#
# Use Case: Visualize healthcare access disparities across census tracts
#           with population density context
#
# Created: 2025-11-02 (Enhancement #3)
# Author: Tyler Muffly & Claude Code
# =============================================================================

# NOTE (2026-08-15): the top-level library(sf/dplyr/ggplot2/here/tidyr/scales)
# calls that used to sit here were removed. They attached packages at load time,
# which is not the same as importing them -- `R CMD check` flagged every
# unprefixed call below as an undefined global. The needed symbols are now real
# namespace imports, declared in R/twostep-package.R. tidyr and scales are gone
# entirely: nothing in this file used them.

#' @title Create Bivariate Color Palette
#'
#' @description
#' Generates a 3×3 or 4×4 bivariate color palette for choropleth mapping.
#' Uses research-based color schemes from Joshua Stevens and Cynthia Brewer.
#'
#' @param palette Palette name (default: "BlueYellow")
#'   Options: "BlueYellow", "PurpleGreen", "BrownBlue", "PinkBlue"
#' @param n_bins Number of bins per dimension (default: 3)
#'   Options: 3 (3×3 = 9 colors) or 4 (4×4 = 16 colors)
#'
#' @return Matrix of hex colors (n_bins × n_bins)
#'
#' @details
#' Bivariate Color Theory:
#' - X-axis: First variable (e.g., female population)
#' - Y-axis: Second variable (e.g., subspecialist access)
#' - Color saturation increases with both variables
#' - Corner colors represent extreme combinations
#'
#' Palette Sources:
#' - Joshua Stevens (2015): "Bivariate Choropleth Maps: A How-to Guide"
#' - Cynthia Brewer: ColorBrewer 2.0
#'
#' @examples
#' \dontrun{
#' # 3×3 Blue-Yellow palette (default)
#' pal <- create_bivariate_palette()
#'
#' # 4×4 Purple-Green palette
#' pal <- create_bivariate_palette("PurpleGreen", n_bins = 4)
#' }
#'
#' @export
create_bivariate_palette <- function(palette = "BlueYellow", n_bins = 3) {

  # Validate inputs
  if (!palette %in% c("BlueYellow", "PurpleGreen", "BrownBlue", "PinkBlue")) {
    stop("palette must be one of: BlueYellow, PurpleGreen, BrownBlue, PinkBlue")
  }

  if (!n_bins %in% c(3, 4)) {
    stop("n_bins must be 3 or 4")
  }

  # Define color palettes (3×3)
  palettes_3x3 <- list(
    # Blue (low pop) to Yellow (high pop), White (low access) to Dark (high access)
    # Research-based from Joshua Stevens
    BlueYellow = matrix(c(
      "#e8e8e8", "#ace4e4", "#5ac8c8",  # Low access (row 1)
      "#dfb0d6", "#a5add3", "#5698b9",  # Medium access (row 2)
      "#be64ac", "#8c62aa", "#3b4994"   # High access (row 3)
    ), nrow = 3, byrow = TRUE),

    # Purple (low pop) to Green (high pop), based on ColorBrewer diverging
    PurpleGreen = matrix(c(
      "#e8e8e8", "#b8d6be", "#73ae80",  # Low access
      "#b5b5d8", "#90b2b3", "#5a9178",  # Medium access
      "#8c62aa", "#5698b9", "#2a5a5b"   # High access
    ), nrow = 3, byrow = TRUE),

    # Brown (low pop) to Blue (high pop), earth tones
    BrownBlue = matrix(c(
      "#e8e8e8", "#b5c8e2", "#6c83b5",  # Low access
      "#dfc27d", "#c3b5a0", "#9e8876",  # Medium access
      "#bf812d", "#9c7753", "#7f5f3d"   # High access
    ), nrow = 3, byrow = TRUE),

    # Pink (low pop) to Blue (high pop), feminine/accessible palette
    PinkBlue = matrix(c(
      "#e8e8e8", "#c8b2d1", "#a07bb6",  # Low access
      "#f4b5bd", "#c992a7", "#9e7091",  # Medium access
      "#f18d9e", "#c76f82", "#9d5266"   # High access
    ), nrow = 3, byrow = TRUE)
  )

  # Define color palettes (4×4)
  palettes_4x4 <- list(
    BlueYellow = matrix(c(
      "#f3f3f3", "#d5e9f2", "#a0d3e8", "#5ac8c8",  # Very low access
      "#e6d3e1", "#c8b5d0", "#a094bc", "#5698b9",  # Low access
      "#d3a5ca", "#b58cb3", "#93749b", "#3b4994",  # Medium access
      "#be64ac", "#9e4f8f", "#7d3a72", "#5d2855"   # High access
    ), nrow = 4, byrow = TRUE),

    PurpleGreen = matrix(c(
      "#f3f3f3", "#d5e9d5", "#a0d3a0", "#73ae80",
      "#d3d3e6", "#b5b5c8", "#9090a7", "#5a9178",
      "#b5b5d8", "#9090b3", "#6c6c8f", "#2a5a5b",
      "#8c62aa", "#6f4f8f", "#523d72", "#352a55"
    ), nrow = 4, byrow = TRUE),

    BrownBlue = matrix(c(
      "#f3f3f3", "#d5d9e2", "#a0afd1", "#6c83b5",
      "#e6d3b5", "#c8b5a0", "#a7938b", "#7f6f76",
      "#dfc27d", "#c3a666", "#a7874f", "#8b6838",
      "#bf812d", "#a36825", "#874f1d", "#6b3615"
    ), nrow = 4, byrow = TRUE),

    PinkBlue = matrix(c(
      "#f3f3f3", "#dfc8e1", "#c89dce", "#a07bb6",
      "#f9d5dd", "#e0b5c4", "#c895ab", "#9e7091",
      "#f4b5bd", "#db95a4", "#c2758b", "#9d5266",
      "#f18d9e", "#d86d85", "#bf4d6c", "#a62d53"
    ), nrow = 4, byrow = TRUE)
  )

  # Select appropriate palette
  if (n_bins == 3) {
    return(palettes_3x3[[palette]])
  } else {
    return(palettes_4x4[[palette]])
  }
}


#' Classify Values into Bivariate Bins
#'
#' Classifies two continuous variables into discrete bins for bivariate mapping.
#'
#' @param data Data frame or `sf` object containing `var1` and `var2`.
#' @param var1 Column name for first variable (X-axis)
#' @param var2 Column name for second variable (Y-axis)
#' @param n_bins Number of bins per dimension (default: 3)
#' @param method Classification method (default: "quantile")
#'   Options: "quantile" (equal-count), "equal" (equal-interval), "jenks"
#' (natural breaks)
#'
#' @return Data frame with added columns: var1_class, var2_class, bivar_class
#'
#' @details
#' Classification Methods:
#' - **Quantile**: Equal number of observations per bin (recommended for skewed
#' data)
#' - **Equal-interval**: Equal range per bin (good for normal distributions)
#' - **Jenks**: Natural breaks (maximizes between-class variance)
#'
#' Output Classes:
#' - var1_class: 1 (low) to n_bins (high)
#' - var2_class: 1 (low) to n_bins (high)
#' - bivar_class: Concatenated string (e.g., "1-1", "3-3")
#'
#' @examples
#' \dontrun{
#' # Quantile classification (default)
#' data_classified <- classify_bivariate(
#'   data = census_tracts,
#'   var1 = "female_population",
#'   var2 = "subspecialist_access",
#'   n_bins = 3
#' )
#' }
#'
#' @export
classify_bivariate <- function(data, var1, var2, n_bins = 3, method = "quantile") {

  # Validate inputs
  if (!var1 %in% names(data)) stop(sprintf("Column '%s' not found in data", var1))
  if (!var2 %in% names(data)) stop(sprintf("Column '%s' not found in data", var2))
  if (!method %in% c("quantile", "equal", "jenks")) {
    stop("method must be one of: quantile, equal, jenks")
  }
  if (nrow(data) == 0L) {
    stop("classify_bivariate: data has 0 rows \u2014 cannot compute breaks or classify")
  }

  # Extract variables
  x <- data[[var1]]
  y <- data[[var2]]

  # Handle missing values
  x[is.na(x)] <- 0
  y[is.na(y)] <- 0

  # Classify based on method
  if (method == "quantile") {
    # Equal-count bins (quantiles)
    x_breaks <- quantile(x, probs = seq(0, 1, length.out = n_bins + 1), na.rm = TRUE)
    y_breaks <- quantile(y, probs = seq(0, 1, length.out = n_bins + 1), na.rm = TRUE)

  } else if (method == "equal") {
    # Equal-interval bins
    x_breaks <- seq(min(x, na.rm = TRUE), max(x, na.rm = TRUE), length.out = n_bins + 1)
    y_breaks <- seq(min(y, na.rm = TRUE), max(y, na.rm = TRUE), length.out = n_bins + 1)

  } else if (method == "jenks") {
    # Natural breaks (Jenks optimization)
    if (!requireNamespace("BAMMtools", quietly = TRUE)) {
      warning("BAMMtools not installed, falling back to quantile method")
      x_breaks <- quantile(x, probs = seq(0, 1, length.out = n_bins + 1), na.rm = TRUE)
      y_breaks <- quantile(y, probs = seq(0, 1, length.out = n_bins + 1), na.rm = TRUE)
    } else {
      x_breaks <- BAMMtools::getJenksBreaks(x[!is.na(x)], k = n_bins + 1)
      y_breaks <- BAMMtools::getJenksBreaks(y[!is.na(y)], k = n_bins + 1)
    }
  }

  # Ensure unique breaks (avoid duplicate cut points)
  x_breaks <- unique(x_breaks)
  y_breaks <- unique(y_breaks)

  # Classify into bins
  data$var1_class <- cut(x, breaks = x_breaks, labels = FALSE, include.lowest = TRUE)
  data$var2_class <- cut(y, breaks = y_breaks, labels = FALSE, include.lowest = TRUE)

  # Handle NAs (assign to lowest class)
  data$var1_class[is.na(data$var1_class)] <- 1
  data$var2_class[is.na(data$var2_class)] <- 1

  # Create combined bivariate class
  data$bivar_class <- paste0(data$var1_class, "-", data$var2_class)

  # Store break points as attributes (for legend)
  attr(data, "var1_breaks") <- x_breaks
  attr(data, "var2_breaks") <- y_breaks
  attr(data, "var1_name") <- var1
  attr(data, "var2_name") <- var2

  return(data)
}


#' Generate Bivariate Choropleth Map
#'
#' Creates a bivariate choropleth map showing the relationship between
#' two variables (e.g., female population and subspecialist access).
#'
#' @param data `sf` object with polygon geometry plus `var1` and `var2`.
#' @param var1 Column name for first variable (X-axis, e.g.,
#'   "female_population")
#' @param var2 Column name for second variable (Y-axis, e.g.,
#'   "subspecialist_access")
#' @param var1_label Label for first variable (for legend)
#' @param var2_label Label for second variable (for legend)
#' @param palette Color palette name (default: "BlueYellow")
#' @param n_bins Number of bins per dimension (default: 3)
#' @param method Classification method (default: "quantile")
#' @param title Map title
#' @param subtitle Map subtitle (optional)
#' @param output_filename Output filename (without extension)
#' @param output_dir Directory the TIFF, PNG and classified data are written to
#'   (default `here("manuscript", "figures")`). Created if absent.
#' @param width Width in inches (default: 12)
#' @param height Height in inches (default: 8)
#' @param dpi Resolution (default: 300)
#'
#' @return List with map object, classified data, and file paths
#'
#' @details
#' Bivariate Choropleth Maps:
#' - Show relationship between TWO variables simultaneously
#' - Each census tract colored by combination of both variables
#' - Legend is 2D grid (not 1D color bar)
#'
#' Use Cases:
#' - Female population × subspecialist access (healthcare equity)
#' - Poverty rate × healthcare coverage (socioeconomic disparities)
#' - Minority percentage × travel time (geographic access barriers)
#'
#' Best Practices:
#' - Use 3×3 bins (9 colors) for clarity (4×4 = too many categories)
#' - Quantile method recommended (equal counts per bin)
#' - Choose palettes carefully (avoid red-green for colorblind accessibility)
#'
#' @examples
#' \dontrun{
#' # Female population × subspecialist access
#' result <- generate_bivariate_choropleth(
#'   data = census_tracts,
#'   var1 = "female_population_total",
#'   var2 = "percent_with_access_30min",
#'   var1_label = "Female Population",
#'   var2_label = "Subspecialist Access (%)",
#'   title = "Female Population and FPMRS Access by Census Tract",
#'   output_filename = "bivariate_female_pop_access"
#' )
#' }
#'
#' @export
generate_bivariate_choropleth <- function(data,
                                          var1,
                                          var2,
                                          var1_label = var1,
                                          var2_label = var2,
                                          palette = "BlueYellow",
                                          n_bins = 3,
                                          method = "quantile",
                                          title = "Bivariate Choropleth Map",
                                          subtitle = NULL,
                                          output_filename = "bivariate_choropleth",
                                          output_dir = here("manuscript", "figures"),
                                          width = 12,
                                          height = 8,
                                          dpi = 300) {

  cat("\n")
  cat(strrep("=", 80), "\n")
  cat("BIVARIATE CHOROPLETH MAP GENERATION\n")
  cat(strrep("=", 80), "\n\n")

  # Step 1: Validate inputs
  cat("Step 1: Validating inputs...\n")

  if (!inherits(data, "sf")) {
    stop("data must be an sf object with polygon geometries")
  }

  if (nrow(data) == 0) {
    stop("data is empty")
  }

  if (!var1 %in% names(data)) {
    stop(sprintf("Column '%s' not found in data", var1))
  }

  if (!var2 %in% names(data)) {
    stop(sprintf("Column '%s' not found in data", var2))
  }

  cat(sprintf("  \u2713 Data: %s polygons\n",
              format(nrow(data), big.mark = ",", trim = TRUE)))
  cat(sprintf("  \u2713 Variable 1: %s\n", var1))
  cat(sprintf("  \u2713 Variable 2: %s\n", var2))
  cat(sprintf("  \u2713 Bins: %d\u00d7%d = %d categories\n", n_bins, n_bins, n_bins^2))
  cat(sprintf("  \u2713 Method: %s\n\n", method))

  # Step 2: Create bivariate color palette
  cat("Step 2: Creating bivariate color palette...\n")

  color_matrix <- create_bivariate_palette(palette = palette, n_bins = n_bins)
  cat(sprintf("  \u2713 Palette: %s (%d\u00d7%d)\n\n", palette, n_bins, n_bins))

  # Step 3: Classify data into bins
  cat("Step 3: Classifying data into bivariate bins...\n")

  data_classified <- classify_bivariate(
    data = data,
    var1 = var1,
    var2 = var2,
    n_bins = n_bins,
    method = method
  )

  # Extract break points for legend
  var1_breaks <- attr(data_classified, "var1_breaks")
  var2_breaks <- attr(data_classified, "var2_breaks")

  cat(sprintf("  \u2713 Variable 1 breaks: %s\n",
              paste(round(var1_breaks, 2), collapse = ", ")))
  cat(sprintf("  \u2713 Variable 2 breaks: %s\n\n",
              paste(round(var2_breaks, 2), collapse = ", ")))

  # Step 4: Assign colors to each bivariate class
  cat("Step 4: Assigning colors...\n")

  # Create color mapping
  color_map <- data.frame(
    var1_class = rep(1:n_bins, each = n_bins),
    var2_class = rep(1:n_bins, times = n_bins),
    color = as.vector(t(color_matrix))  # Transpose for correct orientation
  )
  color_map$bivar_class <- paste0(color_map$var1_class, "-", color_map$var2_class)

  # Join colors to data
  data_classified <- data_classified %>%
    left_join(color_map %>% select(bivar_class, color), by = "bivar_class")

  cat(sprintf("  \u2713 Colors assigned to %d categories\n\n", nrow(color_map)))

  # Step 5: Create map
  cat("Step 5: Creating bivariate choropleth map...\n")

  # Load US states for context
  states <- NULL
  if (file.exists(here("data", "processed", "us_states.rds"))) {
    states <- readRDS(here("data", "processed", "us_states.rds"))
  }

  # Create base map
  p <- ggplot2::ggplot() +
    ggplot2::geom_sf(data = data_classified, ggplot2::aes(fill = color), color = NA, size = 0) +
    ggplot2::scale_fill_identity() +
    ggplot2::theme_minimal() +
    ggplot2::theme(
      panel.grid = ggplot2::element_blank(),
      axis.text = ggplot2::element_blank(),
      axis.title = ggplot2::element_blank(),
      legend.position = "none",  # Custom legend below
      plot.title = ggplot2::element_text(size = 16, face = "bold", hjust = 0.5),
      plot.subtitle = ggplot2::element_text(size = 12, hjust = 0.5, margin = ggplot2::margin(b = 10))
    ) +
    ggplot2::labs(
      title = title,
      subtitle = subtitle
    )

  # Add state borders if available
  if (!is.null(states)) {
    p <- p + ggplot2::geom_sf(data = states, fill = NA, color = "gray30", size = 0.3)
  }

  cat("  \u2713 Map created\n\n")

  # Step 6: Create bivariate legend
  cat("Step 6: Creating bivariate legend...\n")

  # Legend data (3×3 or 4×4 grid)
  legend_data <- expand.grid(
    x = 1:n_bins,
    y = 1:n_bins
  )
  legend_data$color <- as.vector(t(color_matrix))

  # Create legend plot
  legend_plot <- ggplot2::ggplot(legend_data, ggplot2::aes(x = x, y = y, fill = color)) +
    ggplot2::geom_tile(color = "white", size = 1) +
    ggplot2::scale_fill_identity() +
    ggplot2::labs(
      x = sprintf("\u2190 %s \u2192", var1_label),
      y = sprintf("\u2190 %s \u2192", var2_label)
    ) +
    ggplot2::theme_void() +
    ggplot2::theme(
      axis.title.x = ggplot2::element_text(size = 10, margin = ggplot2::margin(t = 5)),
      axis.title.y = ggplot2::element_text(size = 10, margin = ggplot2::margin(r = 5), angle = 90),
      plot.margin = ggplot2::margin(10, 10, 10, 10)
    ) +
    ggplot2::coord_fixed()

  cat("  \u2713 Legend created\n\n")

  # Step 7: Combine map and legend
  cat("Step 7: Combining map and legend...\n")

  if (requireNamespace("cowplot", quietly = TRUE)) {
    # Use cowplot for layout
    combined_plot <- cowplot::ggdraw() +
      cowplot::draw_plot(p, x = 0, y = 0, width = 0.85, height = 1) +
      cowplot::draw_plot(legend_plot, x = 0.70, y = 0.05, width = 0.25, height = 0.25)

    cat("  \u2713 Map and legend combined with cowplot\n\n")
  } else {
    # Fallback: use patchwork or just map
    warning("cowplot not installed, legend will be separate")
    combined_plot <- p
  }

  # Step 8: Save outputs
  cat("Step 8: Saving outputs...\n")

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }

  # Save TIFF (print quality)
  tiff_path <- here(output_dir, paste0(output_filename, ".tiff"))
  ggplot2::ggsave(
    filename = tiff_path,
    plot = combined_plot,
    width = width,
    height = height,
    dpi = dpi,
    compression = "lzw"
  )

  cat(sprintf("  \u2713 TIFF saved: %s (%.1f MB)\n",
              basename(tiff_path),
              file.size(tiff_path) / (1024^2)))

  # Save PNG (preview)
  png_path <- here(output_dir, paste0(output_filename, ".png"))
  ggplot2::ggsave(
    filename = png_path,
    plot = combined_plot,
    width = width,
    height = height,
    dpi = 150
  )

  cat(sprintf("  \u2713 PNG saved: %s (%.1f MB)\n",
              basename(png_path),
              file.size(png_path) / (1024^2)))

  # Save classified data (for analysis)
  data_path <- here(output_dir, paste0(output_filename, "_data.rds"))
  saveRDS(data_classified, data_path)

  cat(sprintf("  \u2713 Classified data saved: %s\n\n", basename(data_path)))

  # Step 9: Summary statistics
  cat("Step 9: Summary statistics...\n\n")

  # Count tracts per bivariate class
  class_summary <- data_classified %>%
    st_drop_geometry() %>%
    group_by(var1_class, var2_class, bivar_class) %>%
    summarise(n_tracts = n(), .groups = "drop") %>%
    arrange(var1_class, var2_class)

  cat("Distribution of census tracts by bivariate class:\n")
  print(class_summary, n = Inf)

  # Summary
  cat("\n")
  cat(strrep("=", 80), "\n")
  cat("BIVARIATE CHOROPLETH COMPLETE\n")
  cat(strrep("=", 80), "\n\n")

  cat("Files created:\n")
  cat(sprintf("  \u2713 %s (TIFF, print quality)\n", basename(tiff_path)))
  cat(sprintf("  \u2713 %s (PNG, preview)\n", basename(png_path)))
  cat(sprintf("  \u2713 %s (Classified data)\n\n", basename(data_path)))

  cat("Interpretation:\n")
  cat(sprintf("  - Lower-left (1-1): Low %s, Low %s\n", var1_label, var2_label))
  cat(sprintf("  - Upper-right (3-3): High %s, High %s\n", var1_label, var2_label))
  cat(sprintf("  - Upper-left (1-3): Low %s, High %s\n", var1_label, var2_label))
  cat(sprintf("  - Lower-right (3-1): High %s, Low %s\n\n", var1_label, var2_label))

  # Return results
  invisible(list(
    map = combined_plot,
    map_only = p,
    legend = legend_plot,
    data = data_classified,
    color_matrix = color_matrix,
    class_summary = class_summary,
    files = list(
      tiff = tiff_path,
      png = png_path,
      data = data_path
    ),
    parameters = list(
      var1 = var1,
      var2 = var2,
      var1_breaks = var1_breaks,
      var2_breaks = var2_breaks,
      palette = palette,
      n_bins = n_bins,
      method = method
    )
  ))
}

# ==============================================================================
# twostep E2SFCA Access Explorer -- Shiny app (app.R)
#
# A SEPARATE app from the isochrones drive-time coverage maps. twostep measures
# ACCESS (supply-to-demand, per capita, by whom); isochrones measures reachability.
# Run:
#   Rscript -e 'shiny::runApp("inst/shiny/access_explorer")'
#   # or, once twostep is installed:  twostep::run_access_explorer()
#
# Tabs:
#   * Disparities -- 2023 access % by race/ethnicity and by drive-time band, from
#     the vendored data/step_4_access_by_group.csv (always runnable).
#   * Access map  -- bivariate access x minority-share tract choropleth, reusing
#     scripts/manuscript_catalog/build_bivariate_leaflet_multisubspec.R logic.
#     Lights up when the tract layer is staged; otherwise shows how to stage it.
# ==============================================================================

suppressWarnings(suppressMessages({
  library(shiny)
  library(leaflet)
}))

source(file.path("helpers.R"), local = TRUE)

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

.ROOT <- ax_root()
.DAT  <- tryCatch(ax_load_disparity(.ROOT), error = function(e) NULL)
.TD   <- tryCatch(ax_load_temporal(.ROOT), error = function(e) NULL)
.SSOT <- tryCatch(ax_load_ssot(.ROOT), error = function(e) list(denominator_category = "total_female"))
.SUBS_CHOICES <- stats::setNames(unname(AX_SUBS), sprintf("%s (%s)", unname(AX_SUBS), names(AX_SUBS)))
.BAND_CHOICES <- stats::setNames(as.integer(names(AX_BANDS)), unname(AX_BANDS))

ui <- fluidPage(
  tags$head(tags$style(HTML("
    body { font-family: system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif; }
    .app-title { font-size: 1.5rem; font-weight: 700; letter-spacing: -0.02em; margin: 6px 0 0; }
    .app-sub { color: #566672; margin-bottom: 8px; }
    .note { background: #eef2f4; border: 1px solid #dde4e8; border-radius: 8px;
            padding: 12px 14px; color: #3a4a54; font-size: .9rem; }
    .gate { background: #fff4e6; border: 1px solid #f0c48a; color: #8a4b0a;
            border-radius: 10px; padding: 16px 18px; }
    code { color: #0a5d58; }
  "))),
  div(class = "app-title", "twostep · E2SFCA Access Explorer"),
  div(class = "app-sub",
      "Supply-to-demand accessibility to OB/GYN subspecialists. Separate from the isochrones coverage maps; reads twostep's frozen artifacts."),

  sidebarLayout(
    sidebarPanel(
      width = 3,
      selectInput("subspec", "Subspecialty", choices = .SUBS_CHOICES,
                  selected = unname(AX_SUBS[["URPS"]])),
      radioButtons("band", "Drive-time band", choices = .BAND_CHOICES,
                   selected = .SSOT$primary_band_sec %||% 3600L),
      tags$hr(),
      div(class = "note",
          tags$b("Provenance."), " Supply counts: ", tags$code("mufflyaccess::urps_count()"),
          ". Demand denominators: twostep ACS. Reachability geometry: isochrones. ",
          "This view is the vendored 2023 cross-section.")
    ),
    mainPanel(
      width = 9,
      tabsetPanel(
        id = "tab",
        tabPanel(
          "Disparities",
          br(),
          fluidRow(
            column(7, plotOutput("disparity", height = "380px")),
            column(5, plotOutput("bandcurve", height = "380px"))
          ),
          br(),
          downloadButton("dl_disp", "Download CSV", class = "btn-sm"),
          br(), br(),
          tableOutput("tbl")
        ),
        tabPanel(
          "Sensitivity",
          br(),
          div(class = "note",
              "Robustness of the access ranking to the distance-decay assumption. ",
              "Composite access recomputed under three Gaussian schemes (from ",
              tags$code("parameter_stability_access.R"), "; base = the E2SFCA default). ",
              "If the subspecialty ordering barely moves, the finding does not hinge on the decay choice."),
          br(),
          plotOutput("sensitivity", height = "440px")
        ),
        tabPanel(
          "Temporal (2013-2023)",
          br(),
          fluidRow(
            column(6, radioButtons("strat", "Stratify by",
                                   choices = c("Race/ethnicity" = "race", "Rurality" = "rurality"),
                                   selected = "race", inline = TRUE)),
            column(6, radioButtons("metric", "Metric",
                                   choices = c("Mean access" = "mean_access", "% zero access" = "pct_zero"),
                                   selected = "mean_access", inline = TRUE))
          ),
          uiOutput("temporal_ui")
        ),
        tabPanel(
          "Scenarios",
          br(),
          uiOutput("scenario_ui")
        ),
        tabPanel(
          "Access map",
          br(),
          uiOutput("map_ui")
        ),
        tabPanel(
          "Provenance",
          br(),
          uiOutput("prov_ui")
        )
      )
    )
  )
)

server <- function(input, output, session) {

  have_data <- reactive({ !is.null(.DAT) })

  output$disparity <- renderPlot({
    validate(need(have_data(), "data/step_4_access_by_group.csv not found."))
    p <- ax_plot_disparity(.DAT, input$subspec, as.integer(input$band))
    validate(need(!is.null(p), "No rows for this subspecialty / band."))
    p
  })

  output$bandcurve <- renderPlot({
    validate(need(have_data(), "data/step_4_access_by_group.csv not found."))
    p <- ax_plot_band_curve(.DAT, input$subspec, .SSOT$denominator_category)
    validate(need(!is.null(p), "No band data for this subspecialty."))
    p
  })

  output$tbl <- renderTable({
    validate(need(have_data(), ""))
    .DAT[.DAT$subspecialty == input$subspec &
         .DAT$range == as.integer(input$band) &
         .DAT$category %in% names(AX_CATS),
         c("category", "count", "total", "percent", "percent_moe")] |>
      transform(group = AX_CATS[category]) |>
      (\(x) x[, c("group", "count", "total", "percent", "percent_moe")])()
  }, digits = 1, striped = TRUE, spacing = "xs")

  output$sensitivity <- renderPlot({
    validate(need(have_data(), "data/step_4_access_by_group.csv not found."))
    p <- ax_plot_sensitivity(.DAT, highlight_label = input$subspec)
    validate(need(!is.null(p), "Not enough band coverage to compute the decay sensitivity."))
    p
  })

  output$temporal_ui <- renderUI({
    if (is.null(.TD)) {
      div(class = "gate",
          tags$b("Temporal view needs the all-years access artifact."),
          tags$p(HTML("Expected: <code>artifacts/2sfca/figures/allsubspec_allyears_stratified_LONG.csv</code> (subspec x year 2013-2023 x stratum). Stage it to enable this tab; the other tabs work without it.")))
    } else {
      tagList(plotOutput("temporal", height = "460px"),
              br(), downloadButton("dl_temp", "Download CSV", class = "btn-sm"))
    }
  })

  output$temporal <- renderPlot({
    validate(need(!is.null(.TD), "all-years artifact not found."))
    p <- ax_plot_temporal(.TD, input$subspec, input$strat, input$metric)
    validate(need(!is.null(p), "No all-years rows for this subspecialty / stratum."))
    p
  })

  output$map_ui <- renderUI({
    ins <- ax_map_inputs_present(.ROOT)
    if (isTRUE(ins$ok)) {
      leafletOutput("map", height = "560px")
    } else {
      div(class = "gate",
          tags$b("Access map needs the staged tract layer."),
          tags$p("The bivariate access map reuses the manuscript leaflet builder and requires the large tract inputs, which are not staged in this checkout:"),
          tags$ul(
            tags$li(HTML(sprintf("tract geometry in <code>%s/</code>", gsub(paste0("^", .ROOT, "/?"), "", ins$geo_dir)))),
            tags$li(HTML(sprintf("access-by-tract parquet in <code>%s/</code>", gsub(paste0("^", .ROOT, "/?"), "", ins$pq_dir))))
          ),
          tags$p("The Disparities tab works without them. Stage the tract layer (see ",
                 tags$code("scripts/manuscript_catalog/_staging_guard.R"),
                 ") to enable the map."))
    }
  })

  output$map <- renderLeaflet({
    m <- ax_build_map(input$subspec, as.integer(input$band), .ROOT)
    validate(need(!is.null(m), "Could not build the map from the staged tract layer."))
    m
  })

  # ---- CSV downloads (downloadable results, per the NurseCast pattern) --------
  disp_slice <- reactive({
    req(have_data())
    .DAT[.DAT$subspecialty == input$subspec & .DAT$range == as.integer(input$band) &
         .DAT$category %in% names(AX_CATS), ]
  })
  output$dl_disp <- downloadHandler(
    filename = function() sprintf("access_disparity_%s_%smin_2023.csv",
                                  AX_LONG_CODE[[input$subspec]], AX_BANDS[as.character(input$band)]),
    content = function(file) utils::write.csv(disp_slice(), file, row.names = FALSE))
  output$dl_temp <- downloadHandler(
    filename = function() sprintf("access_temporal_%s_%s.csv",
                                  AX_LONG_CODE[[input$subspec]], input$strat),
    content = function(file) {
      td <- .TD[.TD$subspec == AX_LONG_CODE[[input$subspec]] & .TD$stratum_type == input$strat, ]
      utils::write.csv(td, file, row.names = FALSE)
    })

  # ---- Scenarios (gated on the precomputed accessibility scenario cube) --------
  output$scenario_ui <- renderUI({
    if (ax_scenario_present(.ROOT)) {
      div(class = "note", "Scenario cube detected. (Slice viewer to be wired to ",
          tags$code("artifacts/2sfca/scenario_cube.*"), ".)")
    } else {
      div(class = "gate",
          tags$b("Scenario planning is precompute-first and needs the scenario cube."),
          tags$p(HTML("Following the NurseCast pattern, the app reads a <b>frozen slice</b> of a precomputed accessibility scenario cube; it never reruns E2SFCA reactively. The cube is not staged in this checkout:")),
          tags$ul(tags$li(tags$code("artifacts/2sfca/scenario_cube.parquet")), tags$li("(or .csv)")),
          tags$p(HTML("Contract (schema, scenarios, change-from-baseline, language rules): <code>docs/accessibility-scenario-cube.md</code>. Supply scenarios come from cliff via mufflyaccess; twostep layers accessibility. Metrics are descriptive (modeled accessibility, change from baseline), never 'shortage' or 'adequacy'.")))
    }
  })

  output$prov_ui <- renderUI({
    pr <- ax_provenance_df(.ROOT)
    yn <- function(x) if (isTRUE(x)) tags$span(style = "color:#2f9e44;font-weight:700;", "✓ present")
                      else tags$span(style = "color:#b5316b;font-weight:700;", "✗ not staged")
    rows <- lapply(seq_len(nrow(pr)), function(i) {
      tags$tr(
        tags$td(style = "vertical-align:top;font-weight:600;white-space:nowrap;", pr$tab[i]),
        tags$td(style = "vertical-align:top;",
                tags$code(pr$source[i]), tags$br(),
                tags$span(style = "color:#566672;font-size:.85em;", pr$grain[i]), tags$br(),
                tags$span(style = "color:#8698a4;font-size:.82em;", "fields: ", pr$fields[i]), tags$br(),
                tags$span(style = "font-size:.88em;", pr$lineage[i])),
        tags$td(style = "vertical-align:top;white-space:nowrap;", yn(pr$present[i]))
      )
    })
    tagList(
      tags$h4("Data provenance, by tab"),
      tags$p(style = "color:#566672;",
             "The app reads frozen artifacts and never recomputes them. “Present” reflects this checkout."),
      tags$table(class = "prov-tbl", style = "width:100%;border-collapse:collapse;",
        tags$thead(tags$tr(
          tags$th(style = "text-align:left;border-bottom:2px solid #dde4e8;padding:6px;", "Tab"),
          tags$th(style = "text-align:left;border-bottom:2px solid #dde4e8;padding:6px;", "Source, grain, fields, lineage"),
          tags$th(style = "text-align:left;border-bottom:2px solid #dde4e8;padding:6px;", "In checkout"))),
        tags$tbody(rows)),
      tags$hr(),
      tags$h4("The one-direction contract"),
      tags$ul(
        tags$li(HTML("<b>Supply</b> (the workforce numerator): <code>mufflyaccess::urps_count()</code> under artifact contract 3.0.0. Never re-derived or hardcoded here.")),
        tags$li(HTML("<b>Demand</b> (population denominators): twostep's own ACS surfaces.")),
        tags$li(HTML("<b>Reachability</b> (travel-time geometry): isochrones release artifacts.")),
        tags$li(HTML("Numerator and denominator must share one geography (<code>assert_matching_geography()</code>)."))
      ),
      tags$p(style = "color:#566672;font-size:.9em;",
             HTML("Shared band / category constants: <code>R/contour_bands.R</code>, <code>R/access_categories.R</code>. E2SFCA engine (SHA-gated): <code>R/two_step_floating_catchment.R</code>; base decay = <code>E2SFCA_DEFAULT_WEIGHTS</code>; CRS EPSG:5070, 500 m grid. Frozen run + checksums: see <code>docs/DATA_PROVENANCE.md</code> and <code>SHA256SUMS.txt</code> (run id pinned by <code>E2SFCA_FROZEN_RUN_ID</code> in <code>scripts/manuscript_e2sfca_values.R</code>). This app measures access only; workforce projection is cliff's (<code>cliff/docs/urps-workforce-projection-spec.md</code>).")),
      tags$p(style = "color:#566672;font-size:.9em;",
             HTML("<b>Verifiable record.</b> Exact sha256 / byte / row counts for the inputs above, plus the environment, are computed (never hand-authored) into <code>PROVENANCE.md</code> (human), <code>provenance.json</code> (machine-readable, for pipelines), and <code>provenance.txt</code> (SHA256SUMS format, verify with <code>shasum -a 256 -c</code>) by <code>generate_provenance.R</code>; rerun it to refresh. Note: <code>shiny</code>, <code>leaflet</code>, <code>ggplot2</code>, and <code>arrow</code> are NOT pinned in <code>renv.lock</code> and must be installed to run this app."))
    )
  })
}

shinyApp(ui, server)

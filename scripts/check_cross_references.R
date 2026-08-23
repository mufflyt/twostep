#!/usr/bin/env Rscript
# ==============================================================================
# check_cross_references.R
# ------------------------------------------------------------------------------
# Parses a manuscript file (Rmd or md) to ensure every Figure and Table 
# referenced in the text is actually defined, and vice versa.
# ==============================================================================

check_cross_references <- function(file_path) {
  if (!file.exists(file_path)) {
    stop("File not found: ", file_path)
  }
  
  lines <- readLines(file_path, warn = FALSE)
  text <- paste(lines, collapse = "\n")
  
  # ----------------------------------------------------------------------------
  # 1. Find Definitions (The actual figures and tables in the document)
  # ----------------------------------------------------------------------------
  # Matches "**Figure 1.**", "**Figure S1.**", "**Figures S1-S7.**"
  # A definition is a bold caption "**Figure 3.**" / "**Figures S1-S7.**" OR a
  # heading "### Figure S1". The token must be a number or S-number: the old
  # pattern accepted any word, so "**Figure provenance.**" was parsed as a
  # figure called "provenance" and reported as defined-but-never-referenced.
  fig_defs_raw <- c(
    regmatches(text, gregexpr("\\*\\*Figures? (S?[0-9]+(?:-S?[0-9]+)?)\\.\\*\\*", text))[[1]],
    regmatches(text, gregexpr("(?m)^#+ +Figures? (S?[0-9]+(?:-S?[0-9]+)?)\\.?[ \t]*$", text, perl = TRUE))[[1]])
  fig_defs_str <- unique(trimws(gsub("^#+ +|\\*\\*|Figures? |\\.$|\\.\\*\\*", "", fig_defs_raw)))
  
  fig_defs <- character()
  for (def in fig_defs_str) {
    if (grepl("-", def)) {
      parts <- strsplit(def, "-")[[1]]
      if (length(parts) == 2 && grepl("^S", parts[1]) && grepl("^S", parts[2])) {
        start_num <- suppressWarnings(as.integer(sub("S", "", parts[1])))
        end_num <- suppressWarnings(as.integer(sub("S", "", parts[2])))
        if (!is.na(start_num) && !is.na(end_num) && end_num >= start_num) {
          fig_defs <- c(fig_defs, paste0("S", start_num:end_num))
        } else {
          fig_defs <- c(fig_defs, def)
        }
      } else {
        fig_defs <- c(fig_defs, def)
      }
    } else {
      fig_defs <- c(fig_defs, def)
    }
  }
  
  # Matches "Table 1. ", "Table S2. " usually inside a caption string
  tab_defs_raw <- regmatches(text, gregexpr("Table (S?[0-9]+)\\.", text))[[1]]
  tab_defs <- unique(gsub("Table |\\.", "", tab_defs_raw))
  
  # ----------------------------------------------------------------------------
  # 2. Find References (Mentions of figures and tables in the text)
  # ----------------------------------------------------------------------------
  extract_refs <- function(pattern, text, exclude_pattern) {
    matches <- regmatches(text, gregexpr(pattern, text, ignore.case = TRUE))[[1]]
    parsed_items <- character()
    for (m in matches) {
      if (grepl(exclude_pattern, m, ignore.case = TRUE)) next
      num_str <- gsub("(?i)(Figure|Table|Figures|Tables)s?\\s+", "", m)
      num_str <- trimws(num_str)
      if (grepl("-", num_str)) {
        parts <- strsplit(num_str, "-")[[1]]
        if (length(parts) == 2) {
          prefix <- if (grepl("S", parts[1])) "S" else ""
          start_n <- as.integer(gsub("[^0-9]", "", parts[1]))
          end_n <- as.integer(gsub("[^0-9]", "", parts[2]))
          if (!is.na(start_n) && !is.na(end_n) && end_n >= start_n) {
            parsed_items <- c(parsed_items, paste0(prefix, start_n:end_n))
            next
          }
        }
      }
      parsed_items <- c(parsed_items, num_str)
    }
    return(unique(parsed_items))
  }
  
  fig_refs <- extract_refs("(?i)Figures?\\s+[0-9S]+(?:-[0-9S]+)?", text, "\\*\\*Figures?")
  tab_refs <- extract_refs("(?i)Tables?\\s+[0-9S]+(?:-[0-9S]+)?", text, "Table [0-9S]+\\.")
  
  # ----------------------------------------------------------------------------
  # 3. Compare and Report
  # ----------------------------------------------------------------------------
  cat("======================================================================\n")
  cat("CROSS-REFERENCE CHECK REPORT\n")
  cat("File:", file_path, "\n")
  cat("======================================================================\n\n")
  
  report_discrepancies <- function(name, defs, refs) {
    missing_defs <- setdiff(refs, defs)
    unused_defs <- setdiff(defs, refs)
    
    cat(sprintf("--- %ss ---\n", toupper(name)))
    cat(sprintf("Found %d definitions and %d distinct references.\n", length(defs), length(refs)))
    
    if (length(missing_defs) == 0 && length(unused_defs) == 0) {
      cat("✅ All good! Every referenced", name, "is defined, and vice versa.\n\n")
    } else {
      if (length(missing_defs) > 0) {
        cat("❌ ERROR: The following", name, "s are referenced in text, but NEVER DEFINED:\n")
        cat("   ", paste(missing_defs, collapse = ", "), "\n")
      }
      if (length(unused_defs) > 0) {
        cat("⚠️ WARNING: The following", name, "s are defined, but NEVER REFERENCED in text:\n")
        cat("   ", paste(unused_defs, collapse = ", "), "\n")
      }
      cat("\n")
    }
    length(missing_defs)
  }
  
  n <- report_discrepancies("Figure", fig_defs, fig_refs) +
       report_discrepancies("Table", tab_defs, tab_refs)
  cat("======================================================================\n")
  invisible(n)
}

# The entry point used to run only when given an argument, so invoking it with
# none silently did nothing and exited 0 -- and the report itself only ever
# cat()ed, so even a dangling reference could not fail CI. Default to the
# manuscript and return a status.
#
# A reference with no definition is FATAL: a reviewer clicking "Figure 4" and
# finding nothing is a defect in the submission. A definition with no reference
# is a WARNING only -- it is a style question, and failing on it would make the
# gate argue about editorial choices.
args <- commandArgs(trailingOnly = TRUE)
targets <- if (length(args) > 0) args else
  Sys.glob(file.path("manuscript", "*.Rmd"))
if (length(targets) == 0) {
  cat("no manuscript sources found; nothing to check\n"); quit(status = 0)
}
dangling <- 0L
for (t in targets) dangling <- dangling + check_cross_references(t)
if (dangling > 0L) {
  cat(sprintf("FAIL: %d dangling cross-reference(s) across %d file(s)\n",
              dangling, length(targets)))
  quit(status = 1)
}
cat(sprintf("cross-references resolve in all %d file(s)\n", length(targets)))

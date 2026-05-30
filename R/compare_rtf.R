#!/usr/bin/env Rscript
# =============================================================================
# compare_rtf.R  --  RTF File Comparison Tool (content-level, not markup)
# =============================================================================
#
# Compares the *rendered content* of two RTF files and reports every
# difference at the cell level. It deliberately ignores cosmetic RTF markup
# (fonts, colours, column widths, spacing) so that two files that render the
# same table are reported as EQUIVALENT even when their raw bytes differ.
#
# Pipeline (three stages, each independently testable):
#   1. parse_rtf()       RTF  -> tall table (row_index, col_index, raw_value)
#   2. normalize_cells() apply per-cell normalisation -> norm_value
#   3. compare_tables()  full outer join on (row_index, col_index) -> classify
#
# This file can be (a) sourced as a library or (b) run from the command line.
# See the CLI section at the bottom, the README, or run with --help.
#
# Author : Lawlor Solutions
# License : MIT
# =============================================================================

# ----------------------------------------------------------------------------
# Dependency loading
# ----------------------------------------------------------------------------
# striprtf and data.table are required for the engine. optparse is required
# only for the command-line interface; diffdf only for the optional secondary
# cross-check. Each is loaded with a clear, actionable error message.

.need_pkg <- function(pkg, why = "") {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop(sprintf(
      "Required R package '%s' is not installed%s.\n  Install all dependencies by running install_packages.R (see README).",
      pkg, if (nzchar(why)) paste0(" (", why, ")") else ""),
      call. = FALSE)
  }
}

# ----------------------------------------------------------------------------
# Stage 1 -- parse
# ----------------------------------------------------------------------------
#' Parse an RTF file into a tall, one-record-per-cell table.
#'
#' Uses striprtf::read_rtf to decode the RTF (code page, \\'XX and \\uN escapes,
#' table structure) into a character vector: one element per non-table
#' paragraph (title / subtitle / footnote) and one element per table row whose
#' cells are separated by an ASCII Unit Separator (U+001F) sentinel.
#'
#' @param path Path to the RTF file.
#' @return data.table with columns row_index (int), col_index (int),
#'   raw_value (chr). Row/column indices are 1-based and positional.
parse_rtf <- function(path) {
  .need_pkg("striprtf")
  .need_pkg("data.table")
  if (!file.exists(path)) {
    stop(sprintf("File not found: '%s'", path), call. = FALSE)
  }
  # Reject non-RTF / empty input with a clear message (no stack dump).
  header <- tryCatch(readChar(path, 5L, useBytes = TRUE), error = function(e) "")
  if (length(header) == 0L || is.na(header)) header <- ""
  if (!grepl("^\\{\\\\rtf", header)) {
    stop(sprintf("Not a valid RTF file (missing '{\\rtf' header): '%s'", path),
         call. = FALSE)
  }

  CELL <- ""  # Unit Separator: an unlikely sentinel between table cells.

  lines <- tryCatch(
    striprtf::read_rtf(path, row_start = "", row_end = "", cell_end = CELL,
                       ignore_tables = FALSE),
    error = function(e)
      stop(sprintf("Failed to parse RTF '%s': %s", path, conditionMessage(e)),
           call. = FALSE)
  )

  # An empty document -> an empty (but well-formed) tall table.
  if (length(lines) == 0L) {
    return(data.table::data.table(
      row_index = integer(0), col_index = integer(0), raw_value = character(0)))
  }

  # Split each line into its cells. strsplit drops the single terminal empty
  # field produced by the trailing cell delimiter, so an N-cell table row
  # yields exactly N cells. A non-table paragraph (no delimiter) yields one
  # cell; an empty paragraph yields one empty cell -- both preserved so that
  # positional row indices stay aligned between the two files. Built with
  # vectorised operations (no per-row allocation) so large files stay fast.
  parts <- strsplit(lines, CELL, fixed = TRUE)
  parts <- lapply(parts, function(p) if (length(p) == 0L) "" else p)
  ncells <- lengths(parts)

  data.table::data.table(
    row_index = rep.int(seq_along(parts), ncells),
    col_index = sequence(ncells),
    raw_value = enc2utf8(unlist(parts, use.names = FALSE))
  )
}

# ----------------------------------------------------------------------------
# Stage 2 -- normalize
# ----------------------------------------------------------------------------
#' Add a normalised value column to a parsed tall table.
#'
#' Normalisation removes only cosmetic text differences; it never alters the
#' special characters (c, >=, deg, micro, Greek, accents) that are real
#' content. Unicode canonical normalisation is intentionally NOT applied
#' (comparison is exact by default).
#'
#' @param dt              Tall table from parse_rtf().
#' @param trim            Strip leading/trailing whitespace per cell (default ON).
#' @param collapse_space  Collapse internal whitespace runs to one space and
#'                        convert non-breaking spaces to normal spaces (default ON).
#' @param casefold        Upper-case for case-insensitive comparison (default OFF).
#' @return The input table with an added character column 'norm_value'.
normalize_cells <- function(dt, trim = TRUE, collapse_space = TRUE,
                            casefold = FALSE) {
  v <- dt$raw_value
  v <- gsub(" ", " ", v, fixed = TRUE)          # NBSP -> normal space
  if (collapse_space) v <- gsub("\\s+", " ", v, perl = TRUE)
  if (trim)           v <- trimws(v)
  if (casefold)       v <- toupper(v)
  dt$norm_value <- v
  dt[]
}

# ----------------------------------------------------------------------------
# Stage 3 -- compare
# ----------------------------------------------------------------------------
#' Compare two normalised tall tables positionally.
#'
#' Performs a full outer join on (row_index, col_index) and classifies every
#' cell. Row-count and column-count mismatches are not special cases -- they
#' fall out naturally as CELL_ONLY_IN_FILEn entries.
#'
#' @param base,comp  Normalised tall tables (must contain norm_value).
#' @param num_tol    Numeric tolerance. 0 (default) = exact string comparison.
#'                   If > 0, two cells that both parse as numbers (ignoring
#'                   thousands ',' and a trailing '%') and differ by <= the
#'                   tolerance are counted as MATCH.
#' @param rel_tol    Interpret num_tol as a fraction of the larger magnitude.
#' @return list(equivalent, n_cells, n_diffs, diffs) where diffs is a
#'   data.table(row_index, col_index, status, value_file1, value_file2).
compare_tables <- function(base, comp, num_tol = 0, rel_tol = FALSE) {
  .need_pkg("data.table")
  row_index <- col_index <- v1 <- v2 <- norm_value <- status <- NULL  # R CMD check

  m <- merge(
    base[, list(row_index, col_index, v1 = norm_value)],
    comp[, list(row_index, col_index, v2 = norm_value)],
    by = c("row_index", "col_index"), all = TRUE
  )

  # Vectorised numeric-equality test (only consulted when num_tol > 0).
  num_equal <- function(a, b) {
    pa <- suppressWarnings(as.numeric(gsub("[%,]", "", a)))
    pb <- suppressWarnings(as.numeric(gsub("[%,]", "", b)))
    ok <- !is.na(pa) & !is.na(pb)
    d  <- abs(pa - pb)
    tol <- if (rel_tol) num_tol * pmax(abs(pa), abs(pb), na.rm = FALSE)
           else rep(num_tol, length(a))
    res <- rep(FALSE, length(a))
    res[ok] <- d[ok] <= tol[ok]
    res
  }

  m[, status := data.table::fcase(
      is.na(v1),                       "CELL_ONLY_IN_FILE2",
      is.na(v2),                       "CELL_ONLY_IN_FILE1",
      v1 == v2,                        "MATCH",
      num_tol > 0 & num_equal(v1, v2), "MATCH",
      default =                        "VALUE_DIFF"
  )]

  diffs <- m[status != "MATCH"][order(row_index, col_index)]
  data.table::setnames(diffs, c("v1", "v2"), c("value_file1", "value_file2"))
  data.table::setcolorder(diffs,
    c("row_index", "col_index", "status", "value_file1", "value_file2"))

  list(
    equivalent = nrow(diffs) == 0L,
    n_cells    = nrow(m),
    n_diffs    = nrow(diffs),
    diffs      = diffs
  )
}

# ----------------------------------------------------------------------------
# Optional secondary cross-check -- diffdf (the pharma-standard comparator)
# ----------------------------------------------------------------------------
#' Run diffdf as an independent corroboration of the primary comparison.
#'
#' The explicit join in compare_tables() is the source of truth; diffdf is a
#' trusted, independent second opinion that reviewers find reassuring. Failures
#' here never abort the run.
#'
#' @return Short character summary, or NULL if diffdf is unavailable/errors.
run_diffdf_check <- function(base, comp, file = NULL) {
  if (!requireNamespace("diffdf", quietly = TRUE)) {
    return("diffdf not installed - secondary check skipped.")
  }
  tryCatch({
    b <- as.data.frame(base[, c("row_index", "col_index", "norm_value")])
    c <- as.data.frame(comp[, c("row_index", "col_index", "norm_value")])
    res <- diffdf::diffdf(b, c, keys = c("row_index", "col_index"),
                          suppress_warnings = TRUE, file = file)
    if (diffdf::diffdf_has_issues(res))
      "diffdf: differences detected (see secondary report)."
    else
      "diffdf: no differences detected."
  }, error = function(e) paste0("diffdf cross-check could not run: ",
                                conditionMessage(e)))
}

# ----------------------------------------------------------------------------
# Reporting
# ----------------------------------------------------------------------------
.clip <- function(x, n = 38L) {
  x <- ifelse(is.na(x), "<absent>", x)
  ifelse(nchar(x) > n, paste0(substr(x, 1, n - 1L), "…"), x)
}

#' Print and optionally write the comparison report.
#'
#' Always prints a console summary (and the detailed difference table when
#' differences exist). Writes a plain-text report and/or CSV when paths given.
#'
#' @param result       Output of compare_tables().
#' @param file1,file2  Paths shown in the report header.
#' @param txt_path     Optional path for a plain-text report.
#' @param csv_path     Optional path for a machine-readable CSV.
#' @param options_str  Human-readable options string for the header.
#' @param console      Print to the console (default TRUE).
#' @return The text report (character vector), invisibly.
write_report <- function(result, file1, file2, txt_path = NULL, csv_path = NULL,
                         options_str = "", console = TRUE) {
  cells_str <- if (is.na(result$n_cells)) "(skipped - files are byte-identical)"
               else format(result$n_cells, big.mark = ",")
  result_str <- if (result$equivalent) "EQUIVALENT"
                else sprintf("%s DIFFERENCE(S) FOUND",
                             format(result$n_diffs, big.mark = ","))

  hdr <- c(
    "============================================================",
    "RTF COMPARISON REPORT",
    "============================================================",
    paste0("File 1:  ", file1),
    paste0("File 2:  ", file2),
    paste0("Options: ", options_str),
    paste0("Cells compared: ", cells_str),
    paste0("Result:  ", result_str),
    "------------------------------------------------------------"
  )

  detail <- character(0)
  if (!result$equivalent && result$n_diffs > 0L) {
    d <- result$diffs
    # Pad by display width (not bytes) so columns line up even with
    # multi-byte characters such as the minus sign or copyright symbol.
    padw <- function(x, n) {
      x <- as.character(x)
      paste0(x, strrep(" ", pmax(0L, n - nchar(x, type = "width"))))
    }
    line <- function(a, b, c, e, f)
      paste(padw(a, 5L), padw(b, 5L), padw(c, 20L), padw(e, 39L), f)
    detail <- c(
      line("ROW", "COL", "STATUS", "FILE 1 VALUE", "FILE 2 VALUE"),
      vapply(seq_len(nrow(d)), function(i) line(
        d$row_index[i], d$col_index[i], d$status[i],
        .clip(d$value_file1[i]), .clip(d$value_file2[i])), character(1))
    )
  }

  txt <- c(hdr, detail, "")
  if (console) cat(txt, sep = "\n")

  if (!is.null(txt_path)) {
    writeLines(enc2utf8(txt), txt_path, useBytes = TRUE)
  }
  if (!is.null(csv_path)) {
    .need_pkg("data.table")
    data.table::fwrite(result$diffs, csv_path)
  }
  invisible(txt)
}

# ----------------------------------------------------------------------------
# Robustness helper -- drop fully-empty trailing rows
# ----------------------------------------------------------------------------
# Some RTF generators emit one or more blank rows at the very end of a table.
# If one file has them and the other does not, a naive positional compare would
# report spurious CELL_ONLY differences. Trimming trailing all-empty rows from
# each file (after normalisation) prevents that. Empty rows in the middle of a
# document are kept (dropping them would misalign positional indices).
.drop_trailing_empty_rows <- function(dt) {
  if (nrow(dt) == 0L) return(dt)
  row_index <- norm_value <- NULL
  emp <- dt[, list(empty = all(norm_value == "")), by = row_index][order(row_index)]
  k <- nrow(emp)
  while (k >= 1L && isTRUE(emp$empty[k])) k <- k - 1L
  if (k == 0L) return(dt[0L])
  dt[row_index <= emp$row_index[k]]
}

# ----------------------------------------------------------------------------
# Top-level wrapper
# ----------------------------------------------------------------------------
#' Compare two RTF files end-to-end: parse + normalize + compare + report.
#'
#' @param file1,file2     Paths to the two RTF files.
#' @param trim,collapse_space,casefold  Normalisation options (see normalize_cells).
#' @param num_tol,rel_tol Numeric-tolerance options (see compare_tables).
#' @param txt_path,csv_path  Optional output paths.
#' @param run_diffdf      Also run the diffdf secondary cross-check (default FALSE).
#' @param diffdf_path     Optional path for the diffdf report file.
#' @param console         Print the report to the console (default TRUE).
#' @return list from compare_tables(), invisibly, plus $byte_identical and
#'   $diffdf_summary.
compare_rtf <- function(file1, file2,
                        trim = TRUE, collapse_space = TRUE, casefold = FALSE,
                        num_tol = 0, rel_tol = FALSE,
                        txt_path = NULL, csv_path = NULL,
                        run_diffdf = FALSE, diffdf_path = NULL,
                        console = TRUE) {
  for (f in c(file1, file2)) {
    if (!file.exists(f)) stop(sprintf("File not found: '%s'", f), call. = FALSE)
  }

  options_str <- sprintf(
    "num_tol=%s, rel_tol=%s, trim=%s, collapse_space=%s, casefold=%s",
    num_tol, rel_tol, trim, collapse_space, casefold)

  # Fast path: byte-identical files are trivially equivalent (no parse needed).
  byte_identical <- FALSE
  same_md5 <- tryCatch(
    unname(tools::md5sum(file1) == tools::md5sum(file2)),
    error = function(e) FALSE)
  if (isTRUE(same_md5)) {
    byte_identical <- TRUE
    result <- list(
      equivalent = TRUE, n_cells = NA_integer_, n_diffs = 0L,
      diffs = data.table::data.table(
        row_index = integer(0), col_index = integer(0), status = character(0),
        value_file1 = character(0), value_file2 = character(0)))
    diffdf_summary <- "(skipped - files are byte-identical)"
  } else {
    b  <- .drop_trailing_empty_rows(
             normalize_cells(parse_rtf(file1), trim, collapse_space, casefold))
    cc <- .drop_trailing_empty_rows(
             normalize_cells(parse_rtf(file2), trim, collapse_space, casefold))
    result <- compare_tables(b, cc, num_tol = num_tol, rel_tol = rel_tol)
    diffdf_summary <- if (run_diffdf) run_diffdf_check(b, cc, file = diffdf_path)
                      else NULL
  }

  write_report(result, file1, file2, txt_path, csv_path, options_str,
               console = console)
  if (console && !is.null(diffdf_summary)) {
    cat("Secondary check: ", diffdf_summary, "\n", sep = "")
  }

  result$byte_identical <- byte_identical
  result$diffdf_summary <- diffdf_summary
  invisible(result)
}

# ============================================================================
# Command-line interface
# ============================================================================
# Runs only when this file is executed directly (Rscript compare_rtf.R ...),
# never when it is sourced by another script (e.g. run_compare.R).

.is_main <- function() {
  cargs <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", cargs[grepl("^--file=", cargs)])
  length(file_arg) > 0L && basename(file_arg[[1]]) == "compare_rtf.R"
}

.main <- function() {
  .need_pkg("optparse", why = "needed for the command-line interface")

  option_list <- list(
    optparse::make_option("--file1", type = "character", default = NULL,
      help = "Path to the FIRST (reference) RTF file. [required]"),
    optparse::make_option("--file2", type = "character", default = NULL,
      help = "Path to the SECOND (comparison) RTF file. [required]"),
    optparse::make_option("--num-tol", type = "double", default = 0,
      help = "Numeric tolerance; 0 = exact comparison. [default %default]"),
    optparse::make_option("--rel-tol", action = "store_true", default = FALSE,
      help = "Interpret --num-tol as relative (fraction of larger magnitude)."),
    optparse::make_option("--no-collapse-space", action = "store_true",
      default = FALSE, help = "Do NOT collapse internal whitespace runs."),
    optparse::make_option("--casefold", action = "store_true", default = FALSE,
      help = "Case-insensitive comparison."),
    optparse::make_option("--report", type = "character", default = NULL,
      help = "Write a plain-text report to this path."),
    optparse::make_option("--csv", type = "character", default = NULL,
      help = "Write differences as CSV to this path."),
    optparse::make_option("--diffdf", action = "store_true", default = FALSE,
      help = "Also run the diffdf secondary cross-check."),
    optparse::make_option("--quiet", action = "store_true", default = FALSE,
      help = "Suppress the console report (still writes files and sets exit code).")
  )

  parser <- optparse::OptionParser(
    usage = "Rscript compare_rtf.R --file1 <a.rtf> --file2 <b.rtf> [options]",
    option_list = option_list,
    description = paste(
      "\nCompare the rendered content of two RTF files.",
      "Exit codes: 0 = equivalent, 1 = differences found, 2 = error.", sep = "\n"))

  opt <- tryCatch(optparse::parse_args(parser),
                  error = function(e) { message(conditionMessage(e)); quit(status = 2L) })

  if (is.null(opt$file1) || is.null(opt$file2)) {
    optparse::print_help(parser)
    message("\nERROR: both --file1 and --file2 are required.")
    quit(status = 2L)
  }

  result <- tryCatch(
    compare_rtf(
      file1 = opt$file1, file2 = opt$file2,
      trim = TRUE, collapse_space = !opt$`no-collapse-space`,
      casefold = opt$casefold,
      num_tol = opt$`num-tol`, rel_tol = opt$`rel-tol`,
      txt_path = opt$report, csv_path = opt$csv,
      run_diffdf = opt$diffdf, diffdf_path = NULL,
      console = !opt$quiet),
    error = function(e) {
      message("ERROR: ", conditionMessage(e))
      quit(status = 2L)
    })

  quit(status = if (isTRUE(result$equivalent)) 0L else 1L)
}

if (.is_main()) .main()

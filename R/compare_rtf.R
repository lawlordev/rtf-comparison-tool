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

# Tool version, stamped into the audit log so a run can be traced to a build.
RTF_TOOL_VERSION <- "1.1.0"

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

.diff_value <- function(x) ifelse(is.na(x), "<absent>", as.character(x))

#' Format a difference table as aligned, fixed-width report lines.
#'
#' Shared by the single-file report (write_report) and the batch report
#' (write_batch_report) so the two stay byte-for-byte consistent. Padding is by
#' display width (not bytes) so columns line up even with multi-byte characters.
#'
#' @param d A diffs data.table (row_index, col_index, status, value_file1/2).
#' @param truncate_values Shorten long values for compact console display.
#' @return Character vector of report lines (empty if there are no differences).
.format_diff_detail <- function(d, truncate_values = FALSE) {
  if (is.null(d) || nrow(d) == 0L) return(character(0))
  padw <- function(x, n) {
    x <- as.character(x)
    paste0(x, strrep(" ", pmax(0L, n - nchar(x, type = "width"))))
  }
  show_value <- if (truncate_values) .clip else .diff_value
  line <- function(a, b, c, e, f)
    paste(padw(a, 5L), padw(b, 5L), padw(c, 20L), padw(e, 39L), f)
  c(
    line("ROW", "COL", "STATUS", "FILE 1 VALUE", "FILE 2 VALUE"),
    vapply(seq_len(nrow(d)), function(i) line(
      d$row_index[i], d$col_index[i], d$status[i],
      show_value(d$value_file1[i]), show_value(d$value_file2[i])), character(1))
  )
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
    detail <- .format_diff_detail(result$diffs)
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
# Batch comparison -- compare every RTF in one folder against the same-named
# file in a second folder.
# ============================================================================
#' Compare every RTF file in one folder against its namesake in another folder.
#'
#' Lists the .rtf files in each folder and pairs them by file name. Every file
#' is reported -- including the ones whose content is EQUIVALENT -- so the run
#' doubles as a QC record. Files present in only one folder are flagged rather
#' than silently skipped, and a parse error on one file never aborts the batch.
#'
#' @param dir1,dir2  The reference folder and the comparison folder.
#' @param trim,collapse_space,casefold,num_tol,rel_tol  Passed to compare_rtf().
#' @param recursive  Also descend into sub-folders (default FALSE).
#' @param progress   Print one line per file as it is compared (default = console).
#' @param console    Print a summary block when finished (default TRUE).
#' @return list(dir1, dir2, summary, results, totals, all_equivalent) where
#'   summary is a data.table(file, status, n_cells, n_diffs, note) with one row
#'   per file and results is a named list of the per-file compare_rtf() outputs
#'   (only for files that were actually compared).
.batch_file_key <- function(path) {
  path <- gsub("\\\\", "/", enc2utf8(path))
  parts <- strsplit(path, "/", fixed = TRUE)[[1]]
  parts <- trimws(parts)
  tolower(paste(parts, collapse = "/"))
}

.batch_file_index <- function(files, folder_label) {
  .need_pkg("data.table")
  keys <- vapply(files, .batch_file_key, character(1), USE.NAMES = FALSE)
  idx <- data.table::data.table(norm_key = keys, file = files)
  dup <- idx[, .N, by = norm_key][N > 1L]
  if (nrow(dup) > 0L) {
    bad <- idx[norm_key %in% dup$norm_key, paste(file, collapse = ", "), by = norm_key]
    stop(sprintf(
      "Ambiguous RTF file names in %s after case/spacing normalization: %s",
      folder_label, paste(bad$V1, collapse = "; ")),
      call. = FALSE)
  }
  out <- idx$file
  names(out) <- idx$norm_key
  out
}

compare_rtf_folder <- function(dir1, dir2,
                               trim = TRUE, collapse_space = TRUE, casefold = FALSE,
                               num_tol = 0, rel_tol = FALSE,
                               recursive = FALSE,
                               progress = console, console = TRUE) {
  .need_pkg("data.table")
  for (d in c(dir1, dir2)) {
    if (!dir.exists(d)) stop(sprintf("Folder not found: '%s'", d), call. = FALSE)
  }

  list_rtf <- function(d) {
    files <- list.files(d, recursive = recursive, full.names = FALSE)
    is_rtf <- grepl("\\.rtf$", trimws(gsub("\\\\", "/", enc2utf8(files))),
                    ignore.case = TRUE)
    files <- files[is_rtf]
    files[!file.info(file.path(d, files))$isdir]
  }
  f1 <- .batch_file_index(list_rtf(dir1), "folder 1")
  f2 <- .batch_file_index(list_rtf(dir2), "folder 2")
  all_keys <- sort(unique(c(names(f1), names(f2))))

  if (length(all_keys) == 0L) {
    stop(sprintf("No .rtf files found in either folder:\n  %s\n  %s", dir1, dir2),
         call. = FALSE)
  }

  rows    <- vector("list", length(all_keys))
  results <- list()

  for (i in seq_along(all_keys)) {
    key <- all_keys[[i]]
    in1 <- key %in% names(f1)
    in2 <- key %in% names(f2)
    file1_name <- if (in1) unname(f1[[key]]) else NA_character_
    file2_name <- if (in2) unname(f2[[key]]) else NA_character_
    display_name <- if (in1) file1_name else file2_name

    if (in1 && !in2) {
      status <- "ONLY_IN_FOLDER1"; ncells <- NA_integer_; ndiffs <- NA_integer_
      note <- "No file of this name in folder 2"
    } else if (!in1 && in2) {
      status <- "ONLY_IN_FOLDER2"; ncells <- NA_integer_; ndiffs <- NA_integer_
      note <- "No file of this name in folder 1"
    } else {
      res <- tryCatch(
        compare_rtf(file.path(dir1, file1_name), file.path(dir2, file2_name),
                    trim = trim, collapse_space = collapse_space, casefold = casefold,
                    num_tol = num_tol, rel_tol = rel_tol, console = FALSE),
        error = function(e) e)
      if (inherits(res, "error")) {
        status <- "ERROR"; ncells <- NA_integer_; ndiffs <- NA_integer_
        note <- conditionMessage(res)
      } else {
        results[[display_name]] <- res
        ncells <- res$n_cells; ndiffs <- res$n_diffs
        status <- if (isTRUE(res$equivalent)) "EQUIVALENT" else "DIFFERENCES"
        note   <- if (!identical(file1_name, file2_name)) {
          sprintf("Matched to '%s' in folder 2 after filename normalization", file2_name)
        } else {
          ""
        }
      }
    }

    rows[[i]] <- data.frame(file = display_name, status = status, n_cells = ncells,
                            n_diffs = ndiffs, note = note, stringsAsFactors = FALSE)
    if (progress) cat(sprintf("  %-44s %s\n", display_name,
                              if (status == "DIFFERENCES")
                                sprintf("%d difference(s)", ndiffs) else status))
  }

  summary <- data.table::rbindlist(rows)
  totals <- list(
    n_files      = nrow(summary),
    n_equivalent = sum(summary$status == "EQUIVALENT"),
    n_differing  = sum(summary$status == "DIFFERENCES"),
    n_only1      = sum(summary$status == "ONLY_IN_FOLDER1"),
    n_only2      = sum(summary$status == "ONLY_IN_FOLDER2"),
    n_errors     = sum(summary$status == "ERROR"),
    total_diffs  = sum(summary$n_diffs, na.rm = TRUE)
  )
  all_equivalent <- totals$n_differing == 0L && totals$n_errors == 0L &&
                    totals$n_only1 == 0L && totals$n_only2 == 0L

  if (console) {
    cat(sprintf(
      "\n%d file(s) compared: %d equivalent, %d differing, %d only in folder 1, %d only in folder 2, %d error(s).\n",
      totals$n_files, totals$n_equivalent, totals$n_differing,
      totals$n_only1, totals$n_only2, totals$n_errors))
  }

  list(dir1 = dir1, dir2 = dir2, summary = summary, results = results,
       totals = totals, all_equivalent = all_equivalent)
}

#' Write the batch comparison report (text and/or CSV).
#'
#' The text report lists EVERY file with its result (equivalent files included),
#' then shows the cell-level differences for each file that differs. The CSV
#' keeps the per-file summary columns and adds one untruncated row per
#' cell-level difference so exported values can be copied in full.
#'
#' @param batch        Output of compare_rtf_folder().
#' @param txt_path,csv_path  Optional output paths.
#' @param options_str  Human-readable options string for the header.
#' @param console      Print the report to the console (default FALSE).
#' @param timestamp    Run time shown in the header (default now).
#' @return The text report (character vector), invisibly.
write_batch_report <- function(batch, txt_path = NULL, csv_path = NULL,
                               options_str = "", console = FALSE,
                               timestamp = Sys.time()) {
  s <- batch$summary
  t <- batch$totals
  overall <- if (isTRUE(batch$all_equivalent)) "ALL FILES EQUIVALENT"
             else "DIFFERENCES / MISMATCHES FOUND"

  hdr <- c(
    "============================================================",
    "RTF BATCH COMPARISON REPORT",
    "============================================================",
    paste0("Folder 1 (reference):  ", batch$dir1),
    paste0("Folder 2 (comparison): ", batch$dir2),
    paste0("Run at:  ", format(timestamp, "%Y-%m-%d %H:%M:%S")),
    paste0("Options: ", options_str),
    sprintf("Files compared: %d  (equivalent: %d, differing: %d, only in folder 1: %d, only in folder 2: %d, errors: %d)",
            t$n_files, t$n_equivalent, t$n_differing, t$n_only1, t$n_only2, t$n_errors),
    paste0("Result:  ", overall),
    "------------------------------------------------------------",
    "PER-FILE RESULTS  (every file is listed, including matches):"
  )

  padw <- function(x, n) {
    x <- as.character(x)
    paste0(x, strrep(" ", pmax(0L, n - nchar(x, type = "width"))))
  }
  result_label <- function(st, nd) data.table::fcase(
    st == "EQUIVALENT",     "EQUIVALENT",
    st == "DIFFERENCES",    sprintf("%s difference(s)", nd),
    st == "ONLY_IN_FOLDER1","ONLY IN FOLDER 1 (no match)",
    st == "ONLY_IN_FOLDER2","ONLY IN FOLDER 2 (no match)",
    st == "ERROR",          "ERROR (could not compare)",
    default =               st)
  fname_w <- max(c(nchar("FILE"), nchar(s$file)))
  table_lines <- c(
    paste0(padw("FILE", fname_w), "  ", "RESULT"),
    vapply(seq_len(nrow(s)), function(i)
      paste0(padw(s$file[i], fname_w), "  ", result_label(s$status[i], s$n_diffs[i])),
      character(1))
  )

  # Detailed cell-level differences for each file that differs.
  detail <- character(0)
  differing <- s$file[s$status == "DIFFERENCES"]
  if (length(differing) > 0L) {
    detail <- c("", "------------------------------------------------------------",
                "DIFFERENCES BY FILE:")
    for (nm in differing) {
      res <- batch$results[[nm]]
      detail <- c(detail, "",
                  sprintf(">>> %s  (%d difference(s))", nm, res$n_diffs),
                  .format_diff_detail(res$diffs))
    }
  }
  # Note any files that could not be compared at all.
  problem <- s[s$status %in% c("ONLY_IN_FOLDER1", "ONLY_IN_FOLDER2", "ERROR"), ]
  if (nrow(problem) > 0L) {
    detail <- c(detail, "", "------------------------------------------------------------",
                "FILES NOT COMPARED:",
                vapply(seq_len(nrow(problem)), function(i)
                  sprintf("  %s  -- %s", problem$file[i], problem$note[i]), character(1)))
  }

  txt <- c(hdr, table_lines, detail, "")
  if (console) cat(txt, sep = "\n")

  if (!is.null(txt_path)) writeLines(enc2utf8(txt), txt_path, useBytes = TRUE)
  if (!is.null(csv_path)) {
    .need_pkg("data.table")
    data.table::fwrite(.batch_csv_rows(batch), csv_path)
  }
  invisible(txt)
}

.batch_csv_rows <- function(batch) {
  .need_pkg("data.table")
  s <- data.table::copy(batch$summary)
  s[, `:=`(
    row_index = NA_integer_,
    col_index = NA_integer_,
    diff_status = NA_character_,
    value_file1 = NA_character_,
    value_file2 = NA_character_
  )]

  out <- vector("list", nrow(batch$summary))
  for (i in seq_len(nrow(batch$summary))) {
    row <- s[i]
    if (identical(row$status, "DIFFERENCES")) {
      d <- data.table::copy(batch$results[[row$file]]$diffs)
      data.table::setnames(d, "status", "diff_status")
      d[, `:=`(file = row$file, status = row$status, n_cells = row$n_cells,
               n_diffs = row$n_diffs, note = row$note)]
      data.table::setcolorder(d, names(row))
      out[[i]] <- d
    } else {
      out[[i]] <- row
    }
  }
  data.table::rbindlist(out, use.names = TRUE)
}

# ============================================================================
# Tool location + audit log -- proof of which comparisons were run, and when.
# ============================================================================
#' Locate the tool's root folder (the one containing R/compare_rtf.R).
#'
#' Walks up from a hint directory (typically the script's folder), then from
#' RTF_TOOL_ROOT, then the working directory. The audit log and archived reports
#' live under this root, which is why the folder must be kept intact.
#'
#' @param hint Optional directory to start searching from.
#' @return Absolute path to the tool root (falls back to getwd() if not found).
rtf_tool_root <- function(hint = NULL) {
  starts <- c(hint, Sys.getenv("RTF_TOOL_ROOT", ""), getwd())
  for (s in starts) {
    if (is.null(s) || !nzchar(s)) next
    d <- normalizePath(s, mustWork = FALSE)
    for (i in 1:10) {
      if (file.exists(file.path(d, "R", "compare_rtf.R"))) return(d)
      parent <- dirname(d)
      if (identical(parent, d)) break
      d <- parent
    }
  }
  normalizePath(getwd(), mustWork = FALSE)
}

#' Path to the append-only audit log (logs/audit_log.csv under the tool root).
audit_log_path <- function(root) file.path(root, "logs", "audit_log.csv")

# The audit log's column order. One row is appended per run (single or batch).
.AUDIT_COLS <- c("timestamp", "run_type", "item1", "item2", "result",
                 "files_compared", "files_equivalent", "files_differing",
                 "files_only_in_1", "files_only_in_2", "files_errored",
                 "total_diffs", "report_saved", "user", "host", "tool_version")

#' Append one record to the audit log, creating the file (with header) if needed.
#'
#' Every run is logged -- including runs that find NO differences -- so the log
#' is a complete, timestamped record of the QC work performed. Writing the log
#' never aborts a comparison: callers should wrap this in tryCatch and carry on.
#'
#' @param root        Tool root (see rtf_tool_root()).
#' @param run_type    "single" or "batch".
#' @param item1,item2 The two files (single) or folders (batch) compared.
#' @param result      Short result string (e.g. "EQUIVALENT", "1 DIFFERENCE(S)").
#' @param files_*     Per-run counts (defaults suit a single-file run).
#' @param total_diffs Total cell-level differences across the run.
#' @param report_saved Path of any report written for this run ("" if none).
#' @param timestamp   Run time (default now).
#' @return The audit log path, invisibly.
append_audit_log <- function(root, run_type, item1, item2, result,
                             files_compared = 1L, files_equivalent = NA_integer_,
                             files_differing = NA_integer_, files_only_in_1 = 0L,
                             files_only_in_2 = 0L, files_errored = 0L,
                             total_diffs = 0L, report_saved = "",
                             timestamp = Sys.time()) {
  .need_pkg("data.table")
  path <- audit_log_path(root)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)

  entry <- data.frame(
    timestamp        = format(timestamp, "%Y-%m-%d %H:%M:%S"),
    run_type         = run_type,
    item1            = item1,
    item2            = item2,
    result           = result,
    files_compared   = files_compared,
    files_equivalent = files_equivalent,
    files_differing  = files_differing,
    files_only_in_1  = files_only_in_1,
    files_only_in_2  = files_only_in_2,
    files_errored    = files_errored,
    total_diffs      = total_diffs,
    report_saved     = report_saved,
    user             = unname(Sys.info()[["user"]]),
    host             = unname(Sys.info()[["nodename"]]),
    tool_version     = RTF_TOOL_VERSION,
    stringsAsFactors = FALSE
  )[, .AUDIT_COLS]

  is_new <- !file.exists(path)
  data.table::fwrite(entry, path, append = !is_new, col.names = is_new)
  invisible(path)
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

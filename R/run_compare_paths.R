#!/usr/bin/env Rscript
# =============================================================================
# run_compare_paths.R  --  compare two RTF files by TYPING/PASTING their paths
# =============================================================================
# No file dialogs. You paste two file paths and press Enter. Windows paths with
# backslashes are fine, and surrounding quotes (from "Copy as path" or drag-and-
# drop) are handled automatically. It compares the files, prints the report,
# saves a timestamped .txt and .csv next to the first file, and offers to do
# another pair.
#
# Three ways to run it (all work without administrator rights):
#   * In the R console / RStudio:   source("run_compare_paths.R")
#   * From a terminal:              Rscript run_compare_paths.R
#   * Double-click:                 windows\2-Compare-RTF-Files.bat
#                                   macos/2-Compare-RTF-Files.command
# =============================================================================

# --- locate and load the comparison engine ----------------------------------
.this_file <- function() {
  ca <- commandArgs(FALSE)
  m <- grep("^--file=", ca, value = TRUE)
  if (length(m)) return(normalizePath(sub("^--file=", "", m[[1]]), mustWork = FALSE))
  if (!is.null(sys.frame(1)$ofile)) return(normalizePath(sys.frame(1)$ofile, mustWork = FALSE))
  getwd()
}
script_dir <- dirname(.this_file())
engine <- file.path(script_dir, "compare_rtf.R")
if (!file.exists(engine)) engine <- file.path(getwd(), "R", "compare_rtf.R")
if (!file.exists(engine)) engine <- file.path(getwd(), "compare_rtf.R")
if (!file.exists(engine)) stop("Cannot find compare_rtf.R (expected in the R/ folder).", call. = FALSE)
source(engine)

# --- read a line of input (works in the R console and under Rscript) ---------
.stdin_con <- if (!interactive()) file("stdin", open = "r") else NULL
ask <- function(msg) {
  if (interactive()) return(readline(msg))
  cat(msg)
  line <- tryCatch(readLines(.stdin_con, n = 1L, warn = FALSE), error = function(e) character(0))
  if (length(line) == 0L) "" else line[[1]]
}

# strip surrounding quotes/whitespace that paste or drag-and-drop can add
clean_path <- function(p) {
  p <- trimws(p)
  p <- sub('^"(.*)"$', "\\1", p)
  p <- sub("^'(.*)'$", "\\1", p)
  trimws(p)
}

say <- function(...) cat(..., "\n", sep = "")

# default comparison options, shown in the report header
OPTS <- "num_tol=0, rel_tol=FALSE, trim=TRUE, collapse_space=TRUE, casefold=FALSE"

# After showing results on screen, OFFER to export -- TXT (full report) and/or
# CSV (the differences table) -- to a location the user types. Nothing is
# written to disk unless requested.
export_flow <- function(res, f1, f2) {
  if (isTRUE(res$equivalent))
    say("\n(No differences. You can still save the report as a QC record if you wish.)")
  choice <- tolower(clean_path(ask(
    "\nExport report?  [t] TXT   [c] CSV   [b] both   [Enter] skip : ")))
  if (!nzchar(choice) || choice == "n") { say("Not exported."); return(invisible()) }
  if (!choice %in% c("t", "c", "b")) { say("Unrecognised choice - not exported."); return(invisible()) }
  if (choice %in% c("t", "b")) save_export(res, f1, f2, "txt")
  if (choice %in% c("c", "b")) save_export(res, f1, f2, "csv")
}

save_export <- function(res, f1, f2, ext) {
  default_name <- sprintf("RTF_comparison_%s_vs_%s_%s.%s",
                          tools::file_path_sans_ext(basename(f1)),
                          tools::file_path_sans_ext(basename(f2)),
                          format(Sys.time(), "%Y%m%d_%H%M%S"), ext)
  dest <- clean_path(ask(sprintf(
    "  Save %s as (type a full path, or a folder; Enter to skip): ", toupper(ext))))
  if (!nzchar(dest)) { say("  (", toupper(ext), " skipped)"); return(invisible()) }
  if (dir.exists(dest)) {
    path <- file.path(dest, default_name)                 # folder given -> default name
  } else {
    if (!grepl(sprintf("\\.%s$", ext), dest, ignore.case = TRUE)) dest <- paste0(dest, ".", ext)
    path <- dest
  }
  parent <- dirname(path)
  if (!dir.exists(parent)) { say("  ERROR: folder does not exist: ", parent); return(invisible()) }
  ok <- tryCatch({
    if (ext == "txt") write_report(res, f1, f2, txt_path = path, options_str = OPTS, console = FALSE)
    else              write_report(res, f1, f2, csv_path = path, console = FALSE)
    TRUE
  }, error = function(e) { say("  ERROR writing file: ", conditionMessage(e)); FALSE })
  if (ok) say("  Saved: ", normalizePath(path, mustWork = FALSE))
}

last_status <- 0L
repeat {
  say("============================================================")
  say("RTF Comparison Tool - compare by path")
  say("============================================================")
  say("Paste or type the full path to each RTF file, then press Enter.")
  say("(Windows backslash paths are fine; surrounding quotes are OK.)")
  say("Leave a path blank to quit.")
  say("")

  f1 <- clean_path(ask("File 1 (reference)  : "))
  if (!nzchar(f1)) { say("\nNo path entered - exiting."); break }
  f2 <- clean_path(ask("File 2 (comparison) : "))
  if (!nzchar(f2)) { say("\nNo path entered - exiting."); break }

  if (!file.exists(f1)) {
    say("\nERROR: file not found:\n  ", f1)
    last_status <- 2L
  } else if (!file.exists(f2)) {
    say("\nERROR: file not found:\n  ", f2)
    last_status <- 2L
  } else {
    say("\nComparing (cosmetic RTF formatting is ignored)...\n")
    res <- tryCatch(compare_rtf(f1, f2, console = FALSE),
                    error = function(e) { say("\nERROR: ", conditionMessage(e)); NULL })
    if (is.null(res)) {
      last_status <- 2L
    } else {
      write_report(res, f1, f2, options_str = OPTS, console = TRUE)   # show results on screen
      last_status <- if (isTRUE(res$equivalent)) 0L else 1L
      export_flow(res, f1, f2)                                        # offer to save (optional)
    }
  }

  again <- tolower(clean_path(ask("\nCompare another pair? (y/N): ")))
  if (!identical(again, "y")) { say("\nDone."); break }
  say("")
}

if (!interactive()) quit(status = last_status)

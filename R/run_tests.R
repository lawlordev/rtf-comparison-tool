#!/usr/bin/env Rscript
# =============================================================================
# run_tests.R  --  run the full automated test suite (testthat)
# =============================================================================
# Exercises every stage of the tool against small hand-built fixtures and the
# large provided clinical files. Exit code 0 = all tests passed, 1 = failures.
# Double-click a launcher in windows/ or macos/, or run: Rscript R/run_tests.R
# =============================================================================

.this_file <- function() {
  ca <- commandArgs(FALSE)
  m <- grep("^--file=", ca, value = TRUE)
  if (length(m)) return(normalizePath(sub("^--file=", "", m[[1]])))
  getwd()
}
script_dir <- dirname(.this_file())   # the R/ folder
root       <- dirname(script_dir)     # repo root (holds tests/, examples/)

if (!requireNamespace("testthat", quietly = TRUE)) {
  stop("Package 'testthat' is not installed. Please run R/install_packages.R first.",
       call. = FALSE)
}

Sys.setenv(RTF_TOOL_ROOT = root)
suppressMessages(library(testthat))
source(file.path(script_dir, "compare_rtf.R"))

cat("============================================================\n")
cat("RTF Comparison Tool - automated test suite\n")
cat("============================================================\n\n")

test_path <- file.path(root, "tests", "testthat")
res <- test_dir(test_path, reporter = "progress", stop_on_failure = FALSE)

df     <- as.data.frame(res)
passed <- sum(df$passed)
failed <- sum(df$failed) + if ("error" %in% names(df)) sum(df$error) else 0L
warns  <- sum(df$warning)

cat("\n============================================================\n")
cat(sprintf("RESULT: %d passed, %d failed, %d warnings (%d test files)\n",
            passed, failed, warns, nrow(df)))
cat("============================================================\n")

quit(status = if (failed > 0L) 1L else 0L)

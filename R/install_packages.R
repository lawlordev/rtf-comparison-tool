#!/usr/bin/env Rscript
# =============================================================================
# install_packages.R  --  one-time setup: install the R packages this tool needs
# =============================================================================
# Safe to run repeatedly: it only installs packages that are missing, then
# prints a clear status line for each. Double-click a launcher in windows/ or
# macos/ to run this, or run:  Rscript install_packages.R
#
# Works WITHOUT administrator rights: if R's main library (e.g.
# C:\Program Files\R\R-4.6.0\library) is read-only, packages are installed into
# your personal library instead. R automatically loads that personal library in
# future sessions, so the tool then finds the packages with no further setup.
# =============================================================================

pkgs <- c("striprtf", "diffdf", "data.table", "testthat", "optparse")
repo <- "https://cloud.r-project.org"

cat("============================================================\n")
cat("RTF Comparison Tool - package setup\n")
cat("============================================================\n")
cat("R version: ", R.version.string, "\n\n", sep = "")

# --- choose a library we can write to (no admin rights needed) ---------------
# Test writability with a real file-create probe (reliable on 64-bit R, which
# has no UAC file virtualisation, and on macOS; file.access() can be wrong on
# both). If R's main library (often under Program Files on Windows) isn't
# writable, fall back to the user's personal library -- R loads that
# automatically in future sessions once it exists, so the tool then finds the
# packages with no extra setup.
can_write <- function(dir) {
  if (!dir.exists(dir)) return(FALSE)
  probe <- file.path(dir, paste0(".rtf_write_test_", Sys.getpid()))
  ok <- suppressWarnings(tryCatch(isTRUE(file.create(probe)), error = function(e) FALSE))
  if (ok) unlink(probe)
  ok
}
main_lib <- .libPaths()[1]
main_ok  <- can_write(main_lib)
if (main_ok) {
  target_lib <- main_lib
} else {
  target_lib <- Sys.getenv("R_LIBS_USER")
  if (!nzchar(target_lib) || identical(target_lib, "NULL")) {
    ver <- paste(R.version$major, sub("\\..*$", "", R.version$minor), sep = ".")
    target_lib <- file.path(path.expand("~"), "R", "win-library", ver)
  }
  dir.create(target_lib, recursive = TRUE, showWarnings = FALSE)
}
if (!is.element(target_lib, .libPaths())) .libPaths(c(target_lib, .libPaths()))

cat("Installing into library:\n  ", target_lib, "\n", sep = "")
if (!main_ok)
  cat("  (R's main library isn't writable, so your personal library is used -\n",
      "   normal on managed PCs; no administrator rights needed.)\n", sep = "")
cat("\n")

installed <- vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)
missing   <- pkgs[!installed]

if (length(missing) == 0L) {
  cat("All required packages are already installed - nothing to do.\n\n")
} else {
  cat("Installing missing packages: ", paste(missing, collapse = ", "), "\n",
      "(this can take a few minutes the first time)\n\n", sep = "")
  install.packages(missing, repos = repo, lib = target_lib)
}

cat("\nFinal package status\n")
cat("--------------------\n")
ok <- vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)
for (p in pkgs) cat(sprintf("  %-12s %s\n", p, if (ok[[p]]) "OK" else "MISSING"))

if (all(ok)) {
  cat("\nSUCCESS - the environment is ready. You can now compare files.\n")
  quit(status = 0L)
} else {
  cat("\nERROR - one or more packages failed to install. Please review the\n",
      "messages above, check your internet connection, and try again.\n", sep = "")
  quit(status = 1L)
}

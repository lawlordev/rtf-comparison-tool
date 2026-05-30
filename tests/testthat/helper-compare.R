# helper-compare.R -- sourced automatically by testthat before any test file.
# Locates the project root, loads the comparison engine, and defines path
# helpers: fx() for the small fixtures, ex() for the large example files.

.rtf_find_root <- function() {
  starts <- c(Sys.getenv("RTF_TOOL_ROOT", ""), getwd())
  for (start in starts) {
    if (!nzchar(start)) next
    d <- normalizePath(start, mustWork = FALSE)
    for (i in 1:8) {
      if (file.exists(file.path(d, "compare_rtf.R"))) return(d)
      parent <- dirname(d)
      if (identical(parent, d)) break
      d <- parent
    }
  }
  stop("helper-compare.R: could not locate compare_rtf.R (project root).")
}

RTF_ROOT <- .rtf_find_root()
if (!exists("compare_rtf", mode = "function")) {
  source(file.path(RTF_ROOT, "compare_rtf.R"))
}

fx <- function(name) file.path(RTF_ROOT, "tests", "testthat", "fixtures", name)
ex <- function(name) file.path(RTF_ROOT, "examples", name)

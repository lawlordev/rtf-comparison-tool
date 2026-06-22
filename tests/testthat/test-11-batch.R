# M11 -- batch comparison of two FOLDERS of RTF files (compare_rtf_folder,
# write_batch_report) and the folder-picker runner (run_compare_folder.R).

# Build a fresh pair of folders under tempdir() and populate them from the
# existing single-file fixtures. Returns the two folder paths.
new_pair <- function(tag) {
  base <- file.path(tempdir(), paste0("batch_", tag, "_", as.integer(runif(1, 1, 1e9))))
  d1 <- file.path(base, "folder1"); d2 <- file.path(base, "folder2")
  dir.create(d1, recursive = TRUE, showWarnings = FALSE)
  dir.create(d2, recursive = TRUE, showWarnings = FALSE)
  list(d1 = d1, d2 = d2)
}
put <- function(dir, name, fixture) file.copy(fx(fixture), file.path(dir, name))
write_one_cell_rtf <- function(path, value) {
  lines <- c(
    "{\\rtf1\\ansi\\ansicpg1252\\deff0",
    "{\\fonttbl{\\f0\\fnil\\fcharset0 Courier New;}}",
    "\\trowd\\trgaph108\\trleft0",
    "\\cellx12000",
    paste0("\\pard\\intbl\\plain\\f0\\fs18 ", value, "\\cell"),
    "\\row",
    "}"
  )
  writeLines(lines, path, useBytes = TRUE)
}

test_that("every file is reported, including ones with NO differences", {
  p <- new_pair("mixed")
  put(p$d1, "same.rtf",  "identical_A.rtf");  put(p$d2, "same.rtf",  "identical_B.rtf")
  put(p$d1, "diff.rtf",  "value_diff_A.rtf"); put(p$d2, "diff.rtf",  "value_diff_B.rtf")
  put(p$d1, "only1.rtf", "identical_A.rtf")                       # missing from folder 2
  put(p$d2, "only2.rtf", "identical_B.rtf")                       # missing from folder 1

  b <- compare_rtf_folder(p$d1, p$d2, console = FALSE, progress = FALSE)

  expect_equal(nrow(b$summary), 4L)
  st <- setNames(b$summary$status, b$summary$file)
  expect_equal(st[["same.rtf"]],  "EQUIVALENT")          # the no-difference file IS listed
  expect_equal(st[["diff.rtf"]],  "DIFFERENCES")
  expect_equal(st[["only1.rtf"]], "ONLY_IN_FOLDER1")
  expect_equal(st[["only2.rtf"]], "ONLY_IN_FOLDER2")
  expect_equal(b$summary$n_diffs[b$summary$file == "diff.rtf"], 1L)
  expect_false(b$all_equivalent)
})

test_that("totals are correct and add up", {
  p <- new_pair("totals")
  put(p$d1, "same.rtf",  "identical_A.rtf");  put(p$d2, "same.rtf",  "identical_B.rtf")
  put(p$d1, "diff.rtf",  "value_diff_A.rtf"); put(p$d2, "diff.rtf",  "value_diff_B.rtf")
  put(p$d1, "only1.rtf", "identical_A.rtf")

  b <- compare_rtf_folder(p$d1, p$d2, console = FALSE, progress = FALSE)
  t <- b$totals
  expect_equal(t$n_files, 3L)
  expect_equal(t$n_equivalent, 1L)
  expect_equal(t$n_differing, 1L)
  expect_equal(t$n_only1, 1L)
  expect_equal(t$n_only2, 0L)
  expect_equal(t$total_diffs, 1L)
})

test_that("all-matching folders report all_equivalent = TRUE", {
  p <- new_pair("allmatch")
  put(p$d1, "a.rtf", "identical_A.rtf"); put(p$d2, "a.rtf", "identical_B.rtf")
  put(p$d1, "b.rtf", "identical_A.rtf"); put(p$d2, "b.rtf", "identical_B.rtf")

  b <- compare_rtf_folder(p$d1, p$d2, console = FALSE, progress = FALSE)
  expect_true(b$all_equivalent)
  expect_equal(b$totals$n_equivalent, 2L)
  expect_true(all(b$summary$status == "EQUIVALENT"))
})

test_that("batch pairing recognizes filenames with case and edge-space differences", {
  p <- new_pair("normalized_names")
  put(p$d1, " Patient Listing.RTF ", "identical_A.rtf")
  put(p$d2, "patient listing.rtf", "identical_B.rtf")

  b <- compare_rtf_folder(p$d1, p$d2, console = FALSE, progress = FALSE)

  expect_true(b$all_equivalent)
  expect_equal(nrow(b$summary), 1L)
  expect_equal(b$summary$status, "EQUIVALENT")
  expect_match(b$summary$note, "filename normalization")
  expect_equal(b$totals$n_only1 + b$totals$n_only2, 0L)
})

test_that("an unreadable file becomes an ERROR row without aborting the batch", {
  p <- new_pair("err")
  put(p$d1, "ok.rtf",  "identical_A.rtf"); put(p$d2, "ok.rtf",  "identical_B.rtf")
  # The two bad files must differ in bytes, or the byte-identical fast path would
  # call them EQUIVALENT without ever parsing (and so never hit the RTF check).
  writeLines("this is not an RTF file", file.path(p$d1, "bad.rtf"))
  writeLines("this is a different non-RTF file", file.path(p$d2, "bad.rtf"))

  b <- compare_rtf_folder(p$d1, p$d2, console = FALSE, progress = FALSE)
  expect_equal(nrow(b$summary), 2L)
  expect_equal(b$summary$status[b$summary$file == "bad.rtf"], "ERROR")
  expect_equal(b$summary$status[b$summary$file == "ok.rtf"], "EQUIVALENT")  # batch carried on
  expect_equal(b$totals$n_errors, 1L)
})

test_that("compare_rtf_folder errors on a missing folder and on empty folders", {
  p <- new_pair("empty")
  expect_error(compare_rtf_folder(file.path(p$d1, "nope"), p$d2, console = FALSE),
               "Folder not found")
  expect_error(compare_rtf_folder(p$d1, p$d2, console = FALSE), "No .rtf files")
})

test_that("write_batch_report lists every file (incl. equivalent) in TXT and CSV", {
  p <- new_pair("report")
  put(p$d1, "same.rtf", "identical_A.rtf");  put(p$d2, "same.rtf", "identical_B.rtf")
  put(p$d1, "diff.rtf", "value_diff_A.rtf"); put(p$d2, "diff.rtf", "value_diff_B.rtf")
  b <- compare_rtf_folder(p$d1, p$d2, console = FALSE, progress = FALSE)

  txt <- tempfile(fileext = ".txt"); csv <- tempfile(fileext = ".csv")
  on.exit(unlink(c(txt, csv)), add = TRUE)
  write_batch_report(b, txt_path = txt, csv_path = csv, console = FALSE)

  lines <- readLines(txt)
  expect_true(any(grepl("RTF BATCH COMPARISON REPORT", lines)))
  expect_true(any(grepl("^same\\.rtf\\s+EQUIVALENT", lines)))        # match is listed
  expect_true(any(grepl("diff\\.rtf", lines) & grepl("difference", lines, ignore.case = TRUE)))
  expect_true(any(grepl("VALUE_DIFF", lines)))                       # detail block present

  d <- data.table::fread(csv)
  expect_equal(sort(d$file), c("diff.rtf", "same.rtf"))              # both rows, match included
  expect_equal(names(d), c("file", "status", "n_cells", "n_diffs", "note",
                           "row_index", "col_index", "diff_status",
                           "value_file1", "value_file2"))
  expect_equal(d$diff_status[d$file == "diff.rtf"], "VALUE_DIFF")
  expect_true(is.na(d$value_file1[d$file == "same.rtf"]))
})

test_that("the folder runner writes an audit log + archived report end-to-end", {
  # Run run_compare_folder.R from an isolated copy of the tool so its logs/
  # folder lands in a temp root (not the real repo).
  rscript <- file.path(R.home("bin"), "Rscript")
  troot <- file.path(tempdir(), paste0("toolroot_", as.integer(runif(1, 1, 1e9))))
  dir.create(file.path(troot, "R"), recursive = TRUE, showWarnings = FALSE)
  file.copy(file.path(RTF_ROOT, "R", "compare_rtf.R"),        file.path(troot, "R"))
  file.copy(file.path(RTF_ROOT, "R", "run_compare_folder.R"), file.path(troot, "R"))

  p <- new_pair("runner")
  put(p$d1, "same.rtf", "identical_A.rtf");  put(p$d2, "same.rtf", "identical_B.rtf")
  put(p$d1, "diff.rtf", "value_diff_A.rtf"); put(p$d2, "diff.rtf", "value_diff_B.rtf")

  runner <- file.path(troot, "R", "run_compare_folder.R")
  out <- suppressWarnings(system2(rscript, c(runner, p$d1, p$d2),
                                  stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status"); if (is.null(st)) st <- 0L
  expect_equal(as.integer(st), 1L)                                  # differences -> exit 1

  log <- file.path(troot, "logs", "audit_log.csv")
  expect_true(file.exists(log))
  a <- data.table::fread(log)
  expect_equal(nrow(a), 1L)
  expect_equal(a$run_type, "batch")
  expect_equal(a$files_compared, 2L)
  expect_equal(a$files_equivalent, 1L)
  expect_equal(a$files_differing, 1L)

  reports <- list.files(file.path(troot, "logs", "reports"), pattern = "\\.txt$")
  expect_true(length(reports) >= 1L)
})

test_that("batch runner exports full difference values without ellipsis end-to-end", {
  rscript <- file.path(R.home("bin"), "Rscript")
  troot <- file.path(tempdir(), paste0("toolroot_long_", as.integer(runif(1, 1, 1e9))))
  dir.create(file.path(troot, "R"), recursive = TRUE, showWarnings = FALSE)
  file.copy(file.path(RTF_ROOT, "R", "compare_rtf.R"),        file.path(troot, "R"))
  file.copy(file.path(RTF_ROOT, "R", "run_compare_folder.R"), file.path(troot, "R"))

  p <- new_pair("runner_long")
  long_a <- paste(rep("alpha-full-row-value", 12L), collapse = " ")
  long_b <- paste(rep("beta-full-row-value", 12L), collapse = " ")
  write_one_cell_rtf(file.path(p$d1, "Long Difference.RTF"), long_a)
  write_one_cell_rtf(file.path(p$d2, "long difference.rtf"), long_b)

  runner <- file.path(troot, "R", "run_compare_folder.R")
  out <- suppressWarnings(system2(rscript, c(runner, p$d1, p$d2),
                                  stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status"); if (is.null(st)) st <- 0L
  expect_equal(as.integer(st), 1L)

  report_dir <- file.path(troot, "logs", "reports")
  txt <- file.path(report_dir, list.files(report_dir, pattern = "\\.txt$", full.names = FALSE)[[1]])
  csv <- file.path(report_dir, list.files(report_dir, pattern = "\\.csv$", full.names = FALSE)[[1]])
  text <- paste(readLines(txt, warn = FALSE), collapse = "\n")
  d <- data.table::fread(csv)

  expect_match(text, long_a, fixed = TRUE)
  expect_match(text, long_b, fixed = TRUE)
  expect_false(grepl(intToUtf8(8230L), text, fixed = TRUE))
  expect_equal(d$value_file1[d$diff_status == "VALUE_DIFF"], long_a)
  expect_equal(d$value_file2[d$diff_status == "VALUE_DIFF"], long_b)
})

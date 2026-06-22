# M5 -- report writing, CSV output, the CLI and its exit codes.

rscript <- file.path(R.home("bin"), "Rscript")
engine  <- file.path(RTF_ROOT, "R", "compare_rtf.R")

run_cli <- function(args) {
  out <- suppressWarnings(system2(rscript, c(engine, args),
                                  stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status"); if (is.null(st)) st <- 0L
  list(status = as.integer(st), out = out)
}

test_that("write_report writes a readable text report", {
  r <- compare_rtf(fx("value_diff_A.rtf"), fx("value_diff_B.rtf"), console = FALSE)
  txt <- tempfile(fileext = ".txt"); on.exit(unlink(txt))
  write_report(r, "a.rtf", "b.rtf", txt_path = txt, console = FALSE)
  lines <- readLines(txt)
  expect_true(any(grepl("RTF COMPARISON REPORT", lines)))
  expect_true(any(grepl("DIFFERENCE", lines)))
  expect_true(any(grepl("VALUE_DIFF", lines)))
})

test_that("write_report exports full values without ellipsis in TXT and CSV", {
  long_a <- paste(rep("alpha-full-content", 12L), collapse = " ")
  long_b <- paste(rep("beta-full-content", 12L), collapse = " ")
  r <- list(
    equivalent = FALSE,
    n_cells = 1L,
    n_diffs = 1L,
    diffs = data.table::data.table(
      row_index = 1L,
      col_index = 1L,
      status = "VALUE_DIFF",
      value_file1 = long_a,
      value_file2 = long_b
    )
  )

  txt <- tempfile(fileext = ".txt")
  csv <- tempfile(fileext = ".csv")
  on.exit(unlink(c(txt, csv)), add = TRUE)
  write_report(r, "a.rtf", "b.rtf", txt_path = txt, csv_path = csv, console = FALSE)

  text <- paste(readLines(txt, warn = FALSE), collapse = "\n")
  d <- data.table::fread(csv)
  expect_match(text, long_a, fixed = TRUE)
  expect_match(text, long_b, fixed = TRUE)
  expect_false(grepl(intToUtf8(8230L), text, fixed = TRUE))
  expect_equal(d$value_file1, long_a)
  expect_equal(d$value_file2, long_b)
})

test_that("CLI exit code is 0 when files are equivalent", {
  r <- run_cli(c("--file1", fx("identical_A.rtf"), "--file2", fx("identical_B.rtf")))
  expect_equal(r$status, 0L)
})

test_that("CLI exit code is 1 when differences are found", {
  r <- run_cli(c("--file1", fx("value_diff_A.rtf"), "--file2", fx("value_diff_B.rtf")))
  expect_equal(r$status, 1L)
})

test_that("CLI exit code is 2 when a file is missing", {
  r <- run_cli(c("--file1", fx("identical_A.rtf"), "--file2", fx("missing.rtf")))
  expect_equal(r$status, 2L)
})

test_that("CLI exit code is 2 when required arguments are missing", {
  r <- run_cli(c("--file1", fx("identical_A.rtf")))
  expect_equal(r$status, 2L)
})

test_that("CLI writes a CSV that matches the diff table", {
  csv <- tempfile(fileext = ".csv"); on.exit(unlink(csv))
  r <- run_cli(c("--file1", fx("value_diff_A.rtf"), "--file2", fx("value_diff_B.rtf"),
                 "--csv", csv))
  expect_equal(r$status, 1L)
  expect_true(file.exists(csv))
  d <- data.table::fread(csv)
  expect_equal(names(d), c("row_index", "col_index", "status", "value_file1", "value_file2"))
  expect_equal(nrow(d), 1L)
  expect_equal(d$status, "VALUE_DIFF")
})

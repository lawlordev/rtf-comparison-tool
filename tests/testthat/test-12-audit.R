# M12 -- the audit log (append_audit_log, audit_log_path) and tool-root finder.
# The audit log is the proof-of-work record: EVERY run is logged, including the
# runs that find no differences.

new_root <- function() {
  r <- file.path(tempdir(), paste0("auditroot_", as.integer(runif(1, 1, 1e9))))
  dir.create(r, recursive = TRUE, showWarnings = FALSE)
  r
}

test_that("the first append creates logs/audit_log.csv with a header + one row", {
  root <- new_root()
  path <- append_audit_log(root, "single", "a.rtf", "b.rtf", "EQUIVALENT",
                           files_equivalent = 1L, files_differing = 0L)
  expect_equal(normalizePath(path), normalizePath(audit_log_path(root)))
  expect_true(file.exists(path))
  expect_true(file.exists(file.path(root, "logs")))   # folder created under the root

  a <- data.table::fread(path)
  expect_equal(nrow(a), 1L)
  expect_equal(names(a), c("timestamp", "run_type", "item1", "item2", "result",
                           "files_compared", "files_equivalent", "files_differing",
                           "files_only_in_1", "files_only_in_2", "files_errored",
                           "total_diffs", "report_saved", "user", "host", "tool_version"))
})

test_that("a no-difference (EQUIVALENT) run is recorded -- the key requirement", {
  root <- new_root()
  append_audit_log(root, "single", "a.rtf", "b.rtf", "EQUIVALENT",
                   files_equivalent = 1L, files_differing = 0L, total_diffs = 0L)
  a <- data.table::fread(audit_log_path(root))
  expect_equal(a$result, "EQUIVALENT")
  expect_equal(a$files_differing, 0L)
  expect_equal(a$total_diffs, 0L)
})

test_that("appends accumulate -- header written once, one row per run", {
  root <- new_root()
  append_audit_log(root, "single", "a.rtf", "b.rtf", "EQUIVALENT")
  append_audit_log(root, "single", "c.rtf", "d.rtf", "2 DIFFERENCE(S)",
                   files_equivalent = 0L, files_differing = 1L, total_diffs = 2L)
  append_audit_log(root, "batch", "folderA", "folderB", "ALL EQUIVALENT",
                   files_compared = 5L, files_equivalent = 5L, files_differing = 0L)

  a <- data.table::fread(audit_log_path(root))
  expect_equal(nrow(a), 3L)
  expect_equal(a$run_type, c("single", "single", "batch"))
  expect_equal(a$total_diffs, c(0L, 2L, 0L))
  # header appears once: the raw file has rows + 1 line.
  expect_equal(length(readLines(audit_log_path(root))), 4L)
})

test_that("paths containing commas are preserved (CSV quoting)", {
  root <- new_root()
  tricky <- "/Users/me/QC, final/report.txt"
  append_audit_log(root, "batch", "/d1, ref", "/d2, comp", "ALL EQUIVALENT",
                   report_saved = tricky)
  a <- data.table::fread(audit_log_path(root))
  expect_equal(a$item1, "/d1, ref")
  expect_equal(a$report_saved, tricky)
})

test_that("rtf_tool_root finds the repo root from a nested folder", {
  expect_equal(normalizePath(rtf_tool_root(file.path(RTF_ROOT, "tests", "testthat"))),
               normalizePath(RTF_ROOT))
  expect_equal(normalizePath(rtf_tool_root(RTF_ROOT)), normalizePath(RTF_ROOT))
})

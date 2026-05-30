# M3 -- Stage 3 core (exact, positional): the five cell statuses.

test_that("identical content with different markup is EQUIVALENT", {
  r <- compare_rtf(fx("identical_A.rtf"), fx("identical_B.rtf"), console = FALSE)
  expect_true(r$equivalent)
  expect_equal(r$n_diffs, 0L)
})

test_that("a single changed cell yields exactly one VALUE_DIFF", {
  r <- compare_rtf(fx("value_diff_A.rtf"), fx("value_diff_B.rtf"), console = FALSE)
  expect_equal(r$n_diffs, 1L)
  expect_equal(r$diffs$status, "VALUE_DIFF")
  expect_equal(r$diffs$value_file1, "54.2")
  expect_equal(r$diffs$value_file2, "54.8")
})

test_that("an extra trailing row appears as CELL_ONLY_IN_FILE2", {
  r <- compare_rtf(fx("extra_row_A.rtf"), fx("extra_row_B.rtf"), console = FALSE)
  expect_equal(r$n_diffs, 3L)
  expect_true(all(r$diffs$status == "CELL_ONLY_IN_FILE2"))
  expect_true(all(is.na(r$diffs$value_file1)))
})

test_that("an extra trailing cell appears as CELL_ONLY_IN_FILE1", {
  r <- compare_rtf(fx("extra_col_A.rtf"), fx("extra_col_B.rtf"), console = FALSE)
  expect_equal(r$n_diffs, 1L)
  expect_equal(r$diffs$status, "CELL_ONLY_IN_FILE1")
  expect_equal(r$diffs$value_file1, "Completed")
  expect_true(is.na(r$diffs$value_file2))
})

test_that("whitespace-only differences are EQUIVALENT under defaults", {
  r <- compare_rtf(fx("whitespace_A.rtf"), fx("whitespace_B.rtf"), console = FALSE)
  expect_true(r$equivalent)
})

test_that("the same special characters in two encodings are EQUIVALENT", {
  r <- compare_rtf(fx("special_chars_A.rtf"), fx("special_chars_B.rtf"), console = FALSE)
  expect_true(r$equivalent)
})

test_that("a genuine special-character difference is detected", {
  r <- compare_rtf(fx("special_chars_A.rtf"), fx("special_chars_diff_B.rtf"), console = FALSE)
  expect_equal(r$n_diffs, 1L)
  expect_equal(r$diffs$status, "VALUE_DIFF")
})

test_that("CRLF and LF line endings compare as EQUIVALENT", {
  r <- compare_rtf(fx("crlf_A.rtf"), fx("lf_A.rtf"), console = FALSE)
  expect_true(r$equivalent)
})

test_that("an empty cell vs a value is a VALUE_DIFF", {
  r <- compare_rtf(fx("empty_cell_A.rtf"), fx("empty_cell_B.rtf"), console = FALSE)
  expect_equal(r$n_diffs, 1L)
  expect_equal(r$diffs$status, "VALUE_DIFF")
  expect_equal(r$diffs$value_file2, "y")
})

test_that("differences are sorted by row then column", {
  r <- compare_rtf(fx("extra_row_A.rtf"), fx("extra_row_B.rtf"), console = FALSE)
  expect_equal(r$diffs$col_index, sort(r$diffs$col_index))
})

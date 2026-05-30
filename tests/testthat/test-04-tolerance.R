# M4 -- numeric tolerance hook (default exact; tolerance opt-in).

one <- function(a) normalize_cells(data.table::data.table(
  row_index = 1L, col_index = 1L, raw_value = a))
cmp <- function(a, b, ...) compare_tables(one(a), one(b), ...)

test_that("exact comparison (num_tol = 0) flags numeric strings that differ", {
  expect_equal(cmp("12.4", "12.6")$n_diffs, 1L)
})

test_that("numbers within an absolute tolerance MATCH", {
  expect_equal(cmp("12.4", "12.6", num_tol = 0.3)$n_diffs, 0L)
  expect_equal(cmp("12.4", "12.6", num_tol = 0.1)$n_diffs, 1L)
})

test_that("percentages and thousands separators are parsed for tolerance", {
  expect_equal(cmp("1,234", "1235", num_tol = 1)$n_diffs, 0L)
  expect_equal(cmp("12.4%", "12.6%", num_tol = 0.3)$n_diffs, 0L)
})

test_that("relative tolerance is a fraction of the larger magnitude", {
  expect_equal(cmp("100", "101", num_tol = 0.02, rel_tol = TRUE)$n_diffs, 0L)  # 1% < 2%
  expect_equal(cmp("100", "105", num_tol = 0.02, rel_tol = TRUE)$n_diffs, 1L)  # 5% > 2%
})

test_that("non-numeric cells are never matched by tolerance", {
  expect_equal(cmp("Yes", "No", num_tol = 100)$n_diffs, 1L)
})

test_that("the default exact setting leaves the clinical 7-diff result unchanged", {
  skip_if_not(file.exists(ex("clinical_table_base.rtf")))
  r <- compare_rtf(ex("clinical_table_base.rtf"), ex("clinical_table_changed.rtf"),
                   console = FALSE)
  expect_equal(r$n_diffs, 7L)
})

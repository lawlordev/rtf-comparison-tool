# M6 -- edge cases & robustness: fast path, bad input, trailing empty rows.

test_that("byte-identical files take the fast path (no parse needed)", {
  r <- compare_rtf(fx("identical_A.rtf"), fx("identical_A.rtf"), console = FALSE)
  expect_true(r$equivalent)
  expect_true(isTRUE(r$byte_identical))
  expect_true(is.na(r$n_cells))
})

test_that("non-RTF input produces a clear error (no stack dump)", {
  bad <- tempfile(fileext = ".txt"); on.exit(unlink(bad))
  writeLines("This is plain text, not an RTF file.", bad)
  expect_error(compare_rtf(bad, fx("identical_A.rtf"), console = FALSE), "Not a valid RTF")
})

test_that("empty input produces a clear error", {
  empty <- tempfile(fileext = ".rtf"); on.exit(unlink(empty))
  file.create(empty)
  expect_error(compare_rtf(empty, fx("identical_A.rtf"), console = FALSE), "Not a valid RTF")
})

test_that("a fully-empty trailing row does not create spurious diffs", {
  r <- compare_rtf(fx("trailing_empty_A.rtf"), fx("trailing_empty_B.rtf"), console = FALSE)
  expect_true(r$equivalent)
  expect_equal(r$n_diffs, 0L)
})

test_that("trailing empty rows are dropped but mid-document empty rows are kept", {
  dt <- data.table::data.table(
    row_index = c(1L, 2L, 2L, 3L, 3L, 4L, 5L),
    col_index = c(1L, 1L, 2L, 1L, 2L, 1L, 1L),
    raw_value = c("Title", "", "", "a", "b", "", ""),
    norm_value = c("Title", "", "", "a", "b", "", ""))
  out <- .drop_trailing_empty_rows(dt)
  # rows 4 and 5 are trailing-empty -> dropped; row 2 (empty, mid-doc) -> kept
  expect_equal(max(out$row_index), 3L)
  expect_true(2L %in% out$row_index)
})

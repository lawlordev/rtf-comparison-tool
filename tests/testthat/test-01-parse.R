# M1 -- Stage 1 parser: confirm read_rtf layout and the tall-table schema.

test_that("parse_rtf returns the documented tall-table schema", {
  dt <- parse_rtf(fx("identical_A.rtf"))
  expect_s3_class(dt, "data.table")
  expect_identical(names(dt), c("row_index", "col_index", "raw_value"))
  expect_type(dt$row_index, "integer")
  expect_type(dt$col_index, "integer")
  expect_type(dt$raw_value, "character")
})

test_that("paragraphs and table rows are laid out positionally", {
  dt <- parse_rtf(fx("identical_A.rtf"))
  expect_equal(max(dt$row_index), 3L)
  expect_equal(dt[row_index == 1L]$raw_value, "Demographics Summary")
  expect_equal(dt[row_index == 2L]$raw_value, c("Treatment", "N", "Mean Age"))
  expect_equal(dt[row_index == 3L]$raw_value, c("Placebo", "210", "54.2"))
})

test_that("an N-cell table row yields exactly N cells (no spurious trailing cell)", {
  dt <- parse_rtf(fx("identical_A.rtf"))
  expect_equal(nrow(dt[row_index == 2L]), 3L)
  expect_equal(nrow(dt[row_index == 3L]), 3L)
})

test_that("the large clinical file decodes to the expected structure", {
  skip_if_not(file.exists(ex("clinical_table_base.rtf")))
  dt <- parse_rtf(ex("clinical_table_base.rtf"))
  ncols <- dt[, list(n = max(col_index)), by = row_index]$n
  expect_setequal(unique(ncols), c(1L, 6L))   # single-cell paragraphs + 6-col table rows
  expect_equal(sum(ncols == 6L), 532L)         # 532 table rows
})

test_that("special characters survive decoding (both escape forms)", {
  skip_if_not(file.exists(ex("clinical_table_base.rtf")))
  v <- parse_rtf(ex("clinical_table_base.rtf"))$raw_value
  expect_true(any(grepl("≥", v)))  # >=  (\uN? escape)
  expect_true(any(grepl("−", v)))  # minus sign (\uN?)
  expect_true(any(grepl("©", v)))  # copyright (\'XX)
  expect_true(any(grepl("°", v)))  # degree (\'XX)
  expect_true(any(grepl("µ", v)))  # micro (\'XX)
  expect_true(any(grepl("α", v)))  # alpha (\uN?)
  expect_true(any(grepl("ü", v)))  # u-umlaut (\'XX)
})

test_that("parse_rtf errors clearly on missing or non-RTF input", {
  expect_error(parse_rtf(fx("does_not_exist.rtf")), "File not found")
  bad <- tempfile(fileext = ".txt"); on.exit(unlink(bad))
  writeLines("plain text, not rtf", bad)
  expect_error(parse_rtf(bad), "Not a valid RTF")
})

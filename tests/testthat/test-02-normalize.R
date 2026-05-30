# M2 -- Stage 2 normalize: whitespace, NBSP, casefold, special-char preservation.

mkdt <- function(vals) data.table::data.table(
  row_index = seq_along(vals), col_index = 1L, raw_value = vals)

NBSP <- intToUtf8(0x00A0)  # non-breaking space

test_that("leading/trailing whitespace is trimmed and internal runs collapsed", {
  dt <- normalize_cells(mkdt(c("  a  b  ", "x\t\ty", " single ")))
  expect_equal(dt$norm_value, c("a b", "x y", "single"))
})

test_that("non-breaking spaces become normal spaces", {
  dt <- normalize_cells(mkdt(paste0("a", NBSP, NBSP, "b")))
  expect_equal(dt$norm_value, "a b")
})

test_that("casefold is OFF by default and ON when requested", {
  expect_equal(normalize_cells(mkdt("AbC"))$norm_value, "AbC")
  expect_equal(normalize_cells(mkdt("AbC"), casefold = TRUE)$norm_value, "ABC")
})

test_that("collapse_space can be disabled while still trimming", {
  dt <- normalize_cells(mkdt("  a   b  "), collapse_space = FALSE)
  expect_equal(dt$norm_value, "a   b")
})

test_that("special characters are content and are never altered", {
  s <- paste0("Caf", intToUtf8(0xE9), " ", intToUtf8(0xA9), " ",
              intToUtf8(0xB0), "C ", intToUtf8(0xB5), "mol/L ",
              intToUtf8(0x2265), " ", intToUtf8(0x2212), " ",
              intToUtf8(0x03B1), " ", intToUtf8(0x03B2))
  expect_equal(normalize_cells(mkdt(s))$norm_value, s)
})

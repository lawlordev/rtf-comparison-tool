# Generator -- the R test-data generator honours the documented contract.

test_that("generated base vs reformatted is EQUIVALENT and base vs changed is 7 diffs", {
  source(file.path(RTF_ROOT, "generate_test_data.R"), local = TRUE)
  d <- file.path(tempdir(), "gen_contract"); dir.create(d, showWarnings = FALSE)
  files <- generate_test_data(d, n_filler = 12L, verbose = FALSE)
  expect_true(all(file.exists(files)))

  r1 <- compare_rtf(files["base"], files["reformatted"], console = FALSE)
  r2 <- compare_rtf(files["base"], files["changed"],     console = FALSE)
  expect_true(r1$equivalent)
  expect_equal(r2$n_diffs, 7L)
  expect_true(all(r2$diffs$status == "VALUE_DIFF"))
})

test_that("generated files contain the required special characters and footnotes", {
  source(file.path(RTF_ROOT, "generate_test_data.R"), local = TRUE)
  d <- file.path(tempdir(), "gen_chars"); dir.create(d, showWarnings = FALSE)
  files <- generate_test_data(d, n_filler = 6L, verbose = FALSE)
  v <- parse_rtf(files["base"])$raw_value
  expect_true(any(grepl(intToUtf8(0x2265), v)))  # >=
  expect_true(any(grepl(intToUtf8(0x2212), v)))  # minus sign
  expect_true(any(grepl(intToUtf8(0x00A9), v)))  # copyright
  expect_true(any(grepl(intToUtf8(0x00B0), v)))  # degree
  expect_true(any(grepl(intToUtf8(0x00B5), v)))  # micro
  expect_true(any(grepl(intToUtf8(0x03B1), v)))  # alpha
  expect_true(any(grepl(intToUtf8(0x03B2), v)))  # beta
})

test_that("the generator is deterministic for a fixed seed", {
  source(file.path(RTF_ROOT, "generate_test_data.R"), local = TRUE)
  d1 <- file.path(tempdir(), "gen_det1"); dir.create(d1, showWarnings = FALSE)
  d2 <- file.path(tempdir(), "gen_det2"); dir.create(d2, showWarnings = FALSE)
  f1 <- generate_test_data(d1, n_filler = 8L, seed = 123L, verbose = FALSE)
  f2 <- generate_test_data(d2, n_filler = 8L, seed = 123L, verbose = FALSE)
  expect_identical(readLines(f1["base"]), readLines(f2["base"]))
})

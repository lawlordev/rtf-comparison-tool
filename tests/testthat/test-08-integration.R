# Integration -- the provided clinical files (the acceptance criteria).

test_that("base vs reformatted is EQUIVALENT (content compared, not markup)", {
  skip_if_not(file.exists(ex("clinical_table_base.rtf")))
  r <- compare_rtf(ex("clinical_table_base.rtf"),
                   ex("clinical_table_reformatted.rtf"), console = FALSE)
  expect_true(r$equivalent)
  expect_equal(r$n_diffs, 0L)
  expect_equal(r$n_cells, 3202L)
})

test_that("base vs changed yields exactly the 7 documented VALUE_DIFFs", {
  skip_if_not(file.exists(ex("clinical_table_base.rtf")))
  r <- compare_rtf(ex("clinical_table_base.rtf"),
                   ex("clinical_table_changed.rtf"), console = FALSE)
  expect_equal(r$n_diffs, 7L)
  expect_true(all(r$diffs$status == "VALUE_DIFF"))

  pairs <- paste(r$diffs$value_file1, "=>", r$diffs$value_file2)
  expect_true(any(grepl("^Safety Population => Safety Population \\(Final\\)$", pairs)))   # subtitle
  expect_true(any(grepl("45 \\(21.4%\\) => 46 \\(21.9%\\)", pairs)))                       # Headache/Placebo
  expect_true(any(grepl("52 \\(24.5%\\) => 53 \\(25.0%\\)", pairs)))                       # Headache/Drug 20
  expect_true(any(grepl("31 \\(4.9%\\) => 32 \\(5.1%\\)", pairs)))                         # Nausea/Total
  expect_true(any(grepl("^Fatigue => Fatigues$", pairs)))                                  # PT label
  expect_true(any(grepl("Sponsor Pharmaceuticals.*=>.*Sponsor Pharma", pairs)))            # footnote
  expect_true(any(grepl("1.2 to 3.4", r$diffs$value_file1) &
                   grepl("1.0 to 3.6", r$diffs$value_file2)))                              # CI (minus sign)
})

test_that("two of the seven edits are in non-table text (titles/footnotes)", {
  skip_if_not(file.exists(ex("clinical_table_base.rtf")))
  r <- compare_rtf(ex("clinical_table_base.rtf"),
                   ex("clinical_table_changed.rtf"), console = FALSE)
  single_cell_diffs <- r$diffs[col_index == 1L & !grepl("^Fatigue", value_file1)]
  expect_true(nrow(single_cell_diffs) >= 2L)  # subtitle + footnote
})

test_that("the diffdf secondary cross-check agrees with the primary result", {
  skip_if_not(file.exists(ex("clinical_table_base.rtf")))
  skip_if_not_installed("diffdf")
  r <- compare_rtf(ex("clinical_table_base.rtf"),
                   ex("clinical_table_reformatted.rtf"), console = FALSE, run_diffdf = TRUE)
  expect_match(r$diffdf_summary, "no differences")
})

# Real-world tests -- run against real TLF RTF outputs you place in
# tests/real_world/ (those files are NOT distributed with this repo; see that
# folder's README). For each table "stem" provide <stem>_base.rtf plus a
# _reformatted.rtf (same content, formatting only -> must be EQUIVALENT) and/or
# a _changed.rtf (a few values edited -> must differ). Tests skip automatically
# when the files are absent, so the suite passes with or without them.

rw <- function(name) file.path(RTF_ROOT, "tests", "real_world", name)

expect_reformatted_equivalent <- function(stem) {
  base <- rw(paste0(stem, "_base.rtf")); ref <- rw(paste0(stem, "_reformatted.rtf"))
  skip_if_not(file.exists(base) && file.exists(ref))
  r <- compare_rtf(base, ref, console = FALSE)
  expect_true(r$equivalent)
  expect_equal(r$n_diffs, 0L)
}

expect_changed_differs <- function(stem) {
  base <- rw(paste0(stem, "_base.rtf")); chg <- rw(paste0(stem, "_changed.rtf"))
  skip_if_not(file.exists(base) && file.exists(chg))
  r <- compare_rtf(base, chg, console = FALSE)
  expect_false(r$equivalent)
  expect_gt(r$n_diffs, 0L)
  expect_true(all(r$diffs$status == "VALUE_DIFF"))   # in-place edits, no structural diffs
}

test_that("cox_hr: a cosmetically reformatted copy is EQUIVALENT", {
  expect_reformatted_equivalent("cox_hr")
})
test_that("cox_hr: a copy with edited values differs (value diffs only)", {
  expect_changed_differs("cox_hr")
})
test_that("exp_adj: a cosmetically reformatted copy is EQUIVALENT", {
  expect_reformatted_equivalent("exp_adj")
})
test_that("exp_adj: a copy with edited values differs (value diffs only)", {
  expect_changed_differs("exp_adj")
})

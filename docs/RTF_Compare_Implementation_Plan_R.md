# RTF File Comparison Tool — Implementation Plan (R, v2)

**Document purpose:** Build specification for an AI coding assistant to implement a tool that
compares two RTF files and reports their differences, in **R**. Written to be unambiguous and
self-contained. Follow it literally. Where a real decision is needed, this document makes it and
states the default; do not deviate without being asked.

**Final deliverable:** A working R comparison program **plus a complete automated test suite**,
built incrementally and test-first.

**What changed from v1:** This project is now **R-only**. The SAS version is **out of scope for
now** (see §11) — the client agreed R is the better choice while testing. The architecture stays
language-agnostic so SAS can be added later. All previously-open requirements are now **confirmed
by the client** (§1). CLI install steps are included (§5). Ready-made test files are provided (§9).

---

## 0. How to use this document

1. Build in the **milestone order in §9**. For each milestone, write its tests *before or alongside*
   the code, and get them green before moving on.
2. The implementation is three stages (§4): **parse → normalize → compare/report**. Keep them as
   separate functions so each can be unit-tested in isolation.
3. All behavioral decisions are fixed in **§1 (Confirmed requirements)**. Treat them as
   non-negotiable defaults.
4. Ready-made integration test files are described in **§9** and shipped alongside this plan
   (`clinical_table_base.rtf`, `clinical_table_reformatted.rtf`, `clinical_table_changed.rtf`, and
   their `TEST_FILES_README.md`). Use them; you do not need to invent large fixtures.

---

## 1. Confirmed requirements (from the client — fixed)

| Topic | Decision |
|---|---|
| **Language** | **R** (only). SAS deferred / out of scope for now. |
| **Platform** | Files are produced on **Windows**; encoding is **Windows-1252** (`\ansicpg1252`). |
| **Special characters present** | Accents, ≥ (greater-than-or-equal), © (copyright), Greek letters (e.g. α, β), degree sign (°), micro sign (µ), en dash, minus sign. The tool must decode and compare these correctly. |
| **What counts as a difference** | **Exact** comparison for now. Build it so a numeric **tolerance can be enabled later**, but the default is exact (`num_tol = 0`). |
| **Titles / subtitles / footnotes** | **Must be compared** — differences in non-table text are reported. (`include_nontable = ON`.) |
| **Row matching** | **Positional** — the two files are in the same row order. (No key-based matching needed for v1.) |
| **Pagination / header rows** | Files contain repeated column-header rows. **Treat them as normal rows** (no special-casing). |
| **Sample data** | No real files available; **synthetic test files are provided** (see §9). |

---

## 2. Objective

Given the paths of two RTF files, produce a report that:

- States clearly whether the two files are **equivalent in content** (yes/no).
- If not, **lists every difference** with its location (table row, column) and the value from each file.
- Treats the content as **tabular data of arbitrary shape** — any number of columns (commonly ~6,
  but never assume a fixed count), any number of rows, cell values of any type (text, integers,
  decimals, percentages, dates, symbols, blanks).
- **Ignores cosmetic RTF formatting** (fonts, colors, spacing markup) that does not change the
  displayed content.
- Runs efficiently on large files.

This is the clinical "compare two TLF outputs for QC" task; design for it but keep the tool general.

---

## 3. Why you must NOT diff the raw RTF

RTF is markup. Two RTF files that render to the **identical table** can have completely different
bytes (font tables, control-word order, color tables, escape encodings). A raw line/byte `diff`
produces thousands of meaningless differences. **This is the most common way to get this task wrong.**

Correct approach: **extract the displayed cell content from each file, normalize it, and compare the
normalized content** at the cell level (e.g., "Row 14, Col 3: file 1 = `12.4%`, file 2 = `12.5%`").
The provided `clinical_table_base.rtf` vs `clinical_table_reformatted.rtf` test (same content,
different markup → must be EQUIVALENT) exists specifically to prove you did this right.

---

## 4. Architecture (three stages)

```
  file1 ─┐
  file2 ─┤  STAGE 1 PARSE     RTF ──► ordered rows ──► ordered cells
         │                    output: tall table (row_index, col_index, raw_value)
         │  STAGE 2 NORMALIZE apply rules per cell ──► norm_value
         └► STAGE 3 COMPARE   full outer join the two tall tables on (row_index, col_index),
                              classify each cell, aggregate, emit report + exit code
```

**Tall table schema** (one record per cell):

| column | type | meaning |
|---|---|---|
| `row_index` | integer | 1-based row number (sequential as encountered, table rows and non-table paragraphs alike) |
| `col_index` | integer | 1-based cell number within the row (non-table paragraphs have a single cell, `col_index = 1`) |
| `raw_value` | string | extracted cell text before normalization |
| `norm_value` | string | cell text after Stage 2 |

**Cell classification (Stage 3):**

| Situation | Status |
|---|---|
| In both, normalized values equal | `MATCH` |
| In both, differ, but both parse as numbers equal within tolerance (only when `num_tol > 0`) | `MATCH` |
| In both, differ | `VALUE_DIFF` |
| Only in file 1 | `CELL_ONLY_IN_FILE1` |
| Only in file 2 | `CELL_ONLY_IN_FILE2` |

Row-count or column-count mismatches are **not** special cases — they fall out as
`CELL_ONLY_IN_FILEn` entries. This is why the tall/positional model is "catch-all": it works for any
table shape with no assumption about column count.

---

## 5. Environment and setup

### 5.1 Install R from the command line

You (developer) are on **macOS**; the client runs **Windows**. Both need R; R behaves identically on
both. Install R first, then the packages.

**macOS (Homebrew — official CRAN binary):**
```bash
# If you don't have Homebrew yet:
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install R (official R Project binary cask; lets you install pre-built CRAN packages):
brew install --cask r

# Verify:
R --version
Rscript --version
```
(`brew install r` — the formula — also works but compiles packages from source, which is slower;
prefer the `--cask`.)

**Windows (winget — ships with Windows 10/11):**
```powershell
winget install -e --id RProject.R
# Verify (open a new terminal first):
R --version
Rscript --version
```
Alternative via Chocolatey: `choco install r.project`. Rtools is **not** required for this project —
the packages below have pre-built binaries on CRAN, so no compiler toolchain is needed.

### 5.2 Install the R packages (non-interactive, CLI)

```bash
Rscript -e 'install.packages(c("striprtf","diffdf","data.table","testthat","optparse"), repos="https://cloud.r-project.org")'
```
- `striprtf` — RTF → text parser. Detects `\ansicpgNNNN` (incl. 1252) and converts to UTF-8; decodes
  `\'XX` and `\uN` escapes. Exposes table row/cell delimiters (used below).
- `diffdf` — detailed data.frame comparison (the pharma-standard R analog of SAS `PROC COMPARE`;
  supports keys, numeric tolerance, and writing results to a text file). Used as a secondary check.
- `data.table` — fast keyed joins for large data.
- `testthat` — test framework.
- `optparse` — command-line argument parsing.

> Set `repos=` explicitly as shown — without it, `Rscript` package installs fail in non-interactive mode.

### 5.3 File-handling rules

- Accept the two file paths as arguments; never hardcode them.
- Tolerate both Windows (CRLF) and Unix (LF) line endings; normalize internally.
- Encoding: rely on `striprtf` to read `\ansicpg1252` and return UTF-8. Do all comparison in UTF-8.
- Because comparison is **exact**, do **not** apply Unicode canonical normalization (NFC/NFKC) by
  default. (Consequence: a precomposed `é` vs decomposed `e`+combining-accent, or micro sign `µ`
  U+00B5 vs Greek mu `μ` U+03BC, are treated as different — which is correct for exact comparison.
  A `--unicode-normalize` option may be added later.)

---

## 6. Implementation specification (R)

### 6.1 Program structure

`compare_rtf.R` exposing these functions plus a thin CLI:

```r
parse_rtf(path)                                  # Stage 1 -> data.table(row_index, col_index, raw_value)
normalize_cells(dt, trim=TRUE, collapse_space=TRUE, casefold=FALSE)   # Stage 2 -> adds norm_value
compare_tables(base, comp, num_tol=0, rel_tol=FALSE)                  # Stage 3 -> list(...)
write_report(result, file1, file2, txt_path=NULL, csv_path=NULL)      # §7
compare_rtf(file1, file2, ...)                   # top-level wrapper: parse+normalize+compare+report
```

### 6.2 Stage 1 — parse (uses `striprtf::read_rtf`)

`read_rtf` parses the RTF (code page, escapes, unicode, tables) and exposes delimiters for table
structure. Use an unlikely sentinel cell delimiter — ASCII Unit Separator `\u001F`:

```r
parse_rtf <- function(path) {
  lines <- striprtf::read_rtf(
    path,
    row_start = "",        # no per-row prefix
    row_end   = "",        # no per-row suffix
    cell_end  = "\u001F"   # delimiter between cells of a table row
  )
  # `lines`: character vector. Each element is either a non-table paragraph (title/footnote)
  # or a table row whose cells are separated by \u001F.
  rows <- lapply(seq_along(lines), function(i) {
    cells <- strsplit(lines[[i]], "\u001F", fixed = TRUE)[[1]]
    if (length(cells) == 0L) cells <- ""          # preserve empty rows/paragraphs
    data.table::data.table(row_index = i,
                           col_index = seq_along(cells),
                           raw_value = cells)
  })
  data.table::rbindlist(rows)
}
```

Notes:
- Any number of columns falls out automatically (split each row into however many cells it has) —
  satisfies "catch-all" and "don't assume 6 columns."
- Titles/footnotes come back as single-cell rows → captured automatically (this is the confirmed
  `include_nontable = ON` behavior). Differences in them are therefore reported.
- Repeated column-header rows (pagination) come back as ordinary rows → treated as normal rows, as
  the client confirmed. No special handling.
- **Milestone-1 task:** confirm exactly how `read_rtf` lays out the provided files (delimiter
  placement can vary by RTF source). Add a tiny post-processing tweak only if the parsed structure
  doesn't match the expectations in §9. Pin this down with tests before building Stage 3.

### 6.3 Stage 2 — normalize

```r
normalize_cells <- function(dt, trim = TRUE, collapse_space = TRUE, casefold = FALSE) {
  v <- dt$raw_value
  v <- gsub("\u00A0", " ", v, fixed = TRUE)        # non-breaking space -> normal space
  if (collapse_space) v <- gsub("\\s+", " ", v, perl = TRUE)
  if (trim)           v <- trimws(v)
  if (casefold)       v <- toupper(v)
  dt$norm_value <- v
  dt
}
```
Defaults (per §1): `trim` ON, `collapse_space` ON, `casefold` OFF. Do **not** strip or alter the
special characters (©, ≥, °, µ, Greek, accents) — they are content.

### 6.4 Stage 3 — compare

Primary comparison is an explicit keyed full outer join with `data.table` (fast on large data):

```r
compare_tables <- function(base, comp, num_tol = 0, rel_tol = FALSE) {
  m <- merge(
    base[, .(row_index, col_index, v1 = norm_value)],
    comp[, .(row_index, col_index, v2 = norm_value)],
    by = c("row_index", "col_index"), all = TRUE
  )

  num_equal <- function(a, b) {
    pa <- suppressWarnings(as.numeric(gsub("[%,]", "", a)))
    pb <- suppressWarnings(as.numeric(gsub("[%,]", "", b)))
    ok <- !is.na(pa) & !is.na(pb)
    d  <- abs(pa - pb)
    tol <- if (rel_tol) num_tol * pmax(abs(pa), abs(pb)) else rep(num_tol, length(a))
    res <- rep(FALSE, length(a)); res[ok] <- d[ok] <= tol[ok]; res
  }

  m[, status := data.table::fcase(
      is.na(v1),                        "CELL_ONLY_IN_FILE2",
      is.na(v2),                        "CELL_ONLY_IN_FILE1",
      v1 == v2,                         "MATCH",
      num_tol > 0 & num_equal(v1, v2),  "MATCH",
      default =                         "VALUE_DIFF"
  )]

  diffs <- m[status != "MATCH"][order(row_index, col_index)]
  list(equivalent = nrow(diffs) == 0L,
       n_cells    = nrow(m),
       n_diffs    = nrow(diffs),
       diffs      = diffs)
}
```

**Secondary corroboration (recommended, optional):** also run
`diffdf::diffdf(base_df, comp_df, keys = c("row_index","col_index"), file = "diffdf_report.txt")`
and surface its summary. `diffdf` is the trusted pharma data-comparison tool; including its output is
reassuring to reviewers. Treat the explicit join above as the source of truth for normalization and
tolerance; `diffdf` is an independent cross-check.

### 6.5 CLI

Using `optparse`, runnable on Mac or Windows:
```
Rscript compare_rtf.R --file1 a.rtf --file2 b.rtf \
        [--num-tol 0] [--rel-tol] [--no-collapse-space] [--casefold] \
        [--report out.txt] [--csv diffs.csv]
```

### 6.6 Performance

- Use `data.table` (not base `merge` on data.frames) for the join; vectorize normalization (shown
  above) — never loop per cell.
- **Fast path:** if the two files are byte-identical (`tools::md5sum`), return "no differences"
  without parsing.
- `striprtf` reads the whole file into memory, which is fine for normal clinical RTF. For
  pathologically large files, read/parse via a text connection in chunks — but also see §11 on why
  RTF is the wrong target for genuinely huge data.

---

## 7. Report format and exit codes

### 7.1 Console / log summary (always)
```
RTF COMPARISON REPORT
File 1: <path1>
File 2: <path2>
Options: num_tol=<...>, collapse_space=<...>, casefold=<...>
Cells compared: <N>
Result: EQUIVALENT            # or: 7 DIFFERENCE(S) FOUND
```

### 7.2 Detailed differences (when any exist), sorted by row then col
```
ROW  COL  STATUS               FILE 1 VALUE            FILE 2 VALUE
3    1    VALUE_DIFF           Safety Population       Safety Population (Final)
57   2    VALUE_DIFF           45 (21.4%)              46 (21.9%)
...
```

### 7.3 Machine-readable
When `--csv` is given, write CSV with columns `row_index, col_index, status, value_file1, value_file2`.

### 7.4 Exit codes (for pipeline use)
- `0` — equivalent (zero differences)
- `1` — one or more differences found
- `2` — error (file not found, parse failure, bad arguments)

(R: `quit(status = ...)`.)

---

## 8. Options and defaults

| Option | Default | Effect |
|---|---|---|
| `trim` | ON | Strip leading/trailing whitespace per cell. |
| `collapse_space` | ON | Collapse internal whitespace runs to one space; NBSP→space. |
| `casefold` | OFF | Case-insensitive comparison. |
| `num_tol` | 0 (exact) | Numeric tolerance; if >0, cells that both parse as numbers (ignoring `,` and trailing `%`) and differ by ≤ tolerance count as MATCH. Confirmed default exact; build the hook now, leave off. |
| `rel_tol` | OFF | Interpret `num_tol` as relative (fraction of the larger magnitude). |
| `include_nontable` | ON (fixed) | Titles/subtitles/footnotes compared as single-cell rows. Client-confirmed; effectively always on for v1. |
| **(deferred) `key_column`** | — | Match rows by a key column instead of position. **Not in v1** (client confirmed positional). Note the hook for the future. |
| **(deferred) `ignore_repeated_headers`** | — | **Not in v1** — client confirmed repeated header rows are treated as normal rows. |

---

## 9. Test plan and milestones (test-first; this defines "done")

Use **`testthat`**. Each milestone: write fixtures + expected results, then implement until green.

### 9.1 Provided integration fixtures (shipped with this plan)

- `clinical_table_base.rtf`, `clinical_table_reformatted.rtf`, `clinical_table_changed.rtf` (~4,800
  lines each) and `TEST_FILES_README.md`. Expected results (full detail in the README):
  - **base vs reformatted → EQUIVALENT** (same content, different markup). *The key correctness test.*
  - **base vs changed → exactly 7 `VALUE_DIFF`** at the documented cells (incl. one subtitle and one
    footnote, proving non-table comparison). All edits are in place, so no structural diffs.
- These also exercise: Windows-1252 decoding via `\'XX` (©, °, µ, –, é, ü) and Unicode escapes via
  `\uN?` (≥, −, α, β); repeated header rows treated as normal rows; titles/footnotes compared.

### 9.2 Small unit fixtures to create (tiny hand-built RTF, a few rows / ~3–6 cols)

Build these under `tests/fixtures/` for precise unit testing:

1. `identical_A/B` — same content, different markup → EQUIVALENT (small mirror of the big test).
2. `value_diff_A/B` — one cell differs → exactly 1 `VALUE_DIFF`.
3. `extra_row_A/B` — B has one extra trailing row → its cells are `CELL_ONLY_IN_FILE2`.
4. `extra_col_A/B` — one row in A has an extra trailing cell → `CELL_ONLY_IN_FILE1`.
5. `whitespace_A/B` — differ only by leading/trailing and doubled internal spaces → EQUIVALENT (defaults).
6. `special_chars_A/B` — same special characters encoded two valid ways (`\'XX` vs `\uN`) → EQUIVALENT (proves decoding). Also a variant where a special-char cell genuinely differs → `VALUE_DIFF`.
7. `crlf_A` (CRLF) vs `lf_A` (LF), same content → EQUIVALENT (newline tolerance).
8. `empty_cell_A/B` — blank cell vs a value → 1 `VALUE_DIFF`.

### 9.3 Milestones

- **M0 — Setup.** Install R (§5.1) and packages (§5.2). Smoke test: `Rscript -e 'library(striprtf); library(diffdf); library(data.table)'` runs without error.
- **M1 — Stage 1 parser.** Implement `parse_rtf`. Tests: assert the parsed tall table for the small fixtures matches expected `(row_index, col_index, raw_value)`; and that `clinical_table_base.rtf` parses into the expected number of rows with the header row and the special-character cells present. Pin down `read_rtf`'s exact delimiter behavior here.
- **M2 — Stage 2 normalize.** Implement `normalize_cells`. Test whitespace, NBSP, casefold-off, and that special characters survive unchanged.
- **M3 — Stage 3 core (exact).** Implement `compare_tables` with positional matching and the five statuses. Tests: small fixtures 1–5, 6(diff), 7, 8; **and the two big integration expectations** (base/reformatted EQUIVALENT; base/changed → the 7 documented `VALUE_DIFF`s).
- **M4 — Numeric tolerance hook.** Add `num_tol`/`rel_tol`. Tests: e.g. `12.4` vs `12.6` → DIFF at tol 0.1, MATCH at tol 0.3; confirm default (0) leaves the 7-diff result unchanged.
- **M5 — Report + exit codes + CLI.** Implement `write_report`, exit statuses, and the CLI wrapper. Tests: EQUIVALENT→exit 0, differences→exit 1, missing file→exit 2; CSV matches the diff table; run the CLI end-to-end on the three provided files.
- **M6 — Edge cases & robustness.** Byte-identical fast path; graceful error on non-RTF / empty / malformed input (exit 2, clear message, no stack dump); drop fully-empty trailing rows so they don't create spurious diffs.
- **M7 — Performance check.** Confirm the three ~4,800-line files compare quickly; generate a larger synthetic file (e.g. 100k+ rows) and confirm reasonable time and bounded memory, and that the `data.table` keyed join is used.

### 9.4 Extra edge cases to cover in tests

- Merged/spanned cells can shift column alignment → assert the tool does not crash and reports the
  resulting mismatches sensibly (document as a limitation, §11).
- Trailing empty row emitted by some generators → must not create spurious diffs.
- A title/footnote change must be detected (already covered by base-vs-changed edits #1 and #7).

---

## 10. Deliverables and acceptance criteria

**Deliverables:**
1. `compare_rtf.R` — runnable from the command line with two file-path arguments.
2. The full `testthat` suite (small fixtures + the provided integration files).
3. A short `README`: prerequisites, install steps (§5), how to run (example command), exit-code
   meanings, options/defaults (§8), and documented limitations (§11).

**Acceptance criteria (done when):**
- M0–M7 tests pass.
- **base vs reformatted → EQUIVALENT** (content compared, not markup).
- **base vs changed → exactly the 7 documented `VALUE_DIFF`s**, with correct `(row, col)` and both
  files' values.
- Exit codes behave per §7.4.
- The large-file test completes without exhausting memory.

---

## 11. Known limitations (state these in the README)

- **SAS version is out of scope for now.** The architecture (§4) is language-agnostic; a SAS port
  would reuse the same tall-table model and `PROC COMPARE` as the comparison engine, but would
  require writing a custom RTF parser (SAS has no built-in RTF reader). Defer until requested.
- **Merged/spanned cells** can misalign positional column indices; v1 reports the resulting
  mismatches rather than resolving the span.
- **Embedded images, drawing objects, deeply nested tables** are out of scope (text is extracted; objects are ignored).
- **Unicode canonical normalization is intentionally NOT applied** (exact comparison). Visually
  similar but distinct code points are reported as differences; add `--unicode-normalize` later if needed.
- **Genuinely huge files (multi-GB):** the tool streams where possible and uses a keyed join, but
  RTF is not a sensible container for enormous datasets. If that situation is ever real, compare the
  **source data** that generated the RTF, not the rendered RTF, and raise it with the client.
- **Word-authored RTF** uses more varied markup than SAS-generated RTF; `striprtf` handles many cases
  but unusual inputs may need parser hardening. The provided test files mimic SAS-style output.

---

## 12. Residual items to confirm later (not blocking)

1. **Obtain real (de-identified) files eventually** — one "should match" pair and one "known
   differences" pair — and add them to the test suite. They are worth more than synthetic data for
   validating the parser against the client's actual RTF generator.
2. **Confirm the client's RTF generator** (SAS ODS? a specific reporting tool?) once real files
   exist, in case its markup needs a parser tweak.
3. **Tolerance policy**, if/when they move off exact comparison (absolute vs relative; how
   percentages and rounding should be treated).

# Test RTF Files — README

Three synthetic clinical-style RTF files for testing the comparison tool. They imitate a real
"Summary of Treatment-Emergent Adverse Events" table: centered titles/subtitles, a 6-column
table with a repeated column-header row every 25 data rows (pagination), and footnotes.
Each file is ~4,800 lines.

| File | Purpose |
|---|---|
| `clinical_table_base.rtf` | The reference table. |
| `clinical_table_reformatted.rtf` | **Identical visible content**, **different cosmetic RTF markup** (different font sizes, bold header cells, different column widths and row spacing, extra whitespace). |
| `clinical_table_changed.rtf` | `base` with **7 in-place content edits** and nothing else changed. |

## Encoding

All three declare Windows-1252 (`\ansicpg1252`). The files themselves are pure ASCII; non-ASCII
characters are written as RTF escapes, deliberately exercising **both** decode paths your parser
must handle:

- **`\'XX`** (cp1252 byte) for: © `\'a9`, ° `\'b0`, µ `\'b5`, – en-dash `\'96`, é `\'e9`, ü `\'fc`.
- **`\uN?`** (Unicode escape, `?` is the single fallback char per the RTF `\uc1` default) for
  characters not in cp1252: ≥ `\u8805?`, − minus sign `\u8722?`, α `\u945?`, β `\u946?`.

So the table and footnotes contain things like "Subjects with ≥1 TEAE", "Temperature °C",
"(µmol/L)", a CI range using the minus sign, an α-level footnote, a β-blocker footnote, and a
sponsor/reviewer footnote with ©, é and ü. Use these to confirm decoding and exact comparison
of special characters.

## Expected comparison results (these define the integration tests)

**`base` vs `reformatted` → EQUIVALENT (0 differences).**
This is the most important test: it proves the tool compares *content*, not RTF markup. The two
files differ on ~9,580 raw lines of markup but render the same table.

**`base` vs `changed` → exactly 7 differences, all `VALUE_DIFF`.**
All edits are in place (no rows or columns added or removed), so positional alignment is preserved
and each edit produces exactly one `VALUE_DIFF`. Two of the edits are in non-table text (a subtitle
and a footnote), so they are only detected because `include_nontable` is ON (the client-confirmed
default).

| # | Logical location | File 1 (base) value | File 2 (changed) value |
|---|---|---|---|
| 1 | Subtitle line | `Safety Population` | `Safety Population (Final)` |
| 2 | Nervous system disorders › Headache, Placebo column | `45 (21.4%)` | `46 (21.9%)` |
| 3 | Nervous system disorders › Headache, Drug 20 mg column | `52 (24.5%)` | `53 (25.0%)` |
| 4 | Gastrointestinal disorders › Nausea, Total column | `31 (4.9%)` | `32 (5.1%)` |
| 5 | Nervous system disorders › Dizziness, Risk Difference column | `(−1.2 to 3.4)` | `(−1.0 to 3.6)` |
| 6 | General disorders › Fatigue, Preferred-Term label (column 1) | `Fatigue` | `Fatigues` |
| 7 | Footnote (sponsor line) | `…©2026 Sponsor Pharmaceuticals…` | `…©2026 Sponsor Pharma…` |

Notes:
- The **absolute** `(row_index, col_index)` of each difference depends on how the parser indexes
  paragraphs vs table rows; determine them by parsing `base` once. They must map 1:1 to these 7 edits.
- Edits #2–#4 are exact-string differences; with the default exact comparison (`num_tol = 0`) they
  are differences. If you later enable a tolerance, note that `45→46` etc. would still differ unless
  the tolerance is ≥ 1, so these remain useful tolerance test cases.
- Edit #5 differs only in digits; whatever your parser does with the `\u8722?` minus sign, it does
  identically on both sides, so the *difference* is in the numbers, not the symbol.

## Regenerating / adjusting

These three files are the **canonical integration fixtures** and are kept as-is.

To make your **own** equivalent test files (same contract: base↔reformatted EQUIVALENT,
base↔changed = 7 differences) without needing Python, use the bundled R generator
`generate_test_data.R` — double-click `4-Generate-Test-Data` in `windows/` or `macos/`, or
run `Rscript R/generate_test_data.R --out <folder> --rows <n>`. Raise `--rows` to make larger
files (e.g. for the performance check); the seven edits are applied in place so each produces
exactly one `VALUE_DIFF`. Adding or removing a row mid-table will (correctly) cascade into many
positional differences for every following row.

The original synthetic data was produced by a `gen_rtf.py` script; the R generator shipped here
reproduces the same *contract* (not byte-for-byte identical output).

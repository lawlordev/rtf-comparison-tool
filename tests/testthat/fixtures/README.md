# Unit-test fixtures

Tiny hand-built RTF files used by the automated test suite. Each pair isolates one
behaviour. They are deliberately small so the expected result is obvious and
auditable. Expected results below are under the default options (exact comparison,
whitespace trimmed/collapsed, case preserved).

| Fixture(s) | What it isolates | Expected result |
|---|---|---|
| `identical_A` / `identical_B` | Same content, very different markup (fonts, sizes, bold, widths) | EQUIVALENT (0 diffs) |
| `value_diff_A` / `value_diff_B` | One cell value differs (`54.2` → `54.8`) | 1 `VALUE_DIFF` |
| `extra_row_A` / `extra_row_B` | File B has one extra trailing table row | 3 `CELL_ONLY_IN_FILE2` |
| `extra_col_A` / `extra_col_B` | File A row has one extra trailing cell | 1 `CELL_ONLY_IN_FILE1` |
| `whitespace_A` / `whitespace_B` | Differ only by leading/trailing & doubled spaces | EQUIVALENT |
| `special_chars_A` / `special_chars_B` | Same characters via `\'XX` vs `\uN?` escapes | EQUIVALENT |
| `special_chars_A` / `special_chars_diff_B` | One special-char cell genuinely differs (`é` → `e`) | 1 `VALUE_DIFF` |
| `crlf_A` / `lf_A` | Same content, CRLF vs LF line endings | EQUIVALENT |
| `empty_cell_A` / `empty_cell_B` | A blank cell vs a value | 1 `VALUE_DIFF` |
| `trailing_empty_A` / `trailing_empty_B` | One file has an extra all-blank trailing row | EQUIVALENT (trailing blanks trimmed) |

The large clinical integration fixtures live in `../../../examples/`.

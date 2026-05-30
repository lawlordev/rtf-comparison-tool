# Changelog

## 1.0.0 — 2026-05-29

Initial release.

- Content-level RTF comparison engine (`compare_rtf.R`): parse → normalize → compare,
  with cell-level classification (`VALUE_DIFF`, `CELL_ONLY_IN_FILE1/2`), a `data.table`
  keyed join, numeric-tolerance hooks (absolute and relative; default exact), an optional
  `diffdf` secondary cross-check, and a byte-identical fast path.
- Command-line interface with exit codes (0 equivalent, 1 differences, 2 error). Results
  always print; reports are written only when you pass `--report` / `--csv`.
- Interactive runners — console-driven, with no auto-save: they show the result, then
  offer to export TXT/CSV to a location you choose:
    - `run_compare_paths.R` — paste two file paths (default; handles Windows backslash and
      quoted paths; loops for repeated comparisons).
    - `run_compare.R` — native file-picker dialogs (the `2b` alternative).
- Double-click launchers for Windows (`.bat`) and macOS (`.command`) that need no admin
  rights, plus plain-text `START HERE` guides for each OS.
- One-time package installer (`install_packages.R`) that needs no admin rights — it
  installs into your personal R library if the main library (e.g. under Program Files) is
  read-only — and a pure-R synthetic test-data generator (`generate_test_data.R`).
- Automated `testthat` suite (119 checks): parsing, normalization, all difference types,
  tolerance, report/CLI/exit codes, edge cases, a large-file performance check, the
  integration expectations, the generator contract, and real-world clinical files.
- Validated: provided files base ↔ reformatted EQUIVALENT and base ↔ changed = exactly 7
  differences; plus real-world TLF outputs in `tests/real_world/`.

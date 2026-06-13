# Changelog

## 1.1.0 — 2026-06-12

Batch folder comparison and an audit trail.

- **Batch folder comparison** (`compare_rtf_folder()` + `run_compare_folder.R`, launchers
  `2c-Compare-Folders`): pick a reference folder and a comparison folder; every `.rtf` is
  compared against the same-named file in the other folder. Produces **one report that lists
  every file — including the ones with no differences** — with cell-level detail for the files
  that differ, and flags files present in only one folder (`ONLY_IN_FOLDER1/2`) or that fail to
  parse (`ERROR`) instead of skipping them. The full report is auto-archived to `logs/reports/`
  (`.txt` + `.csv`) and a Save dialog offers an extra copy.
- **Audit log** (`append_audit_log()` → `logs/audit_log.csv`, launchers `5-View-Audit-Log`):
  every run — single-file *and* batch, **including no-difference runs** — appends one
  timestamped row (who, when, what was compared, the result and counts, and the saved report
  path) so the work performed is provable. All three interactive runners now log; the
  comparison engine itself stays pure (it never writes the log).
- **Keep-the-folder-intact** guidance added prominently to `README.md`, both `START HERE`
  files, and a new `logs/README.txt`, since the tool now writes its audit trail to `logs/`
  next to `R/`.
- Test suite grown to **171 checks** (added `test-11-batch.R`, `test-12-audit.R`), covering the
  batch engine/report, the audit-log schema and append behaviour, and an end-to-end run of the
  folder runner.

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

# Real-world tests

Drop your **own** real TLF RTF outputs in this folder to exercise the tool against
production-style files. These files are **not distributed** with the repository — add your
own (and keep any confidential data out of public copies of the repo; `*.rtf` here is
git-ignored for that reason).

For each table you want to test, provide a "stem" with up to three files:

| File | Purpose | Expected result vs base |
|---|---|---|
| `<stem>_base.rtf` | the reference output | — |
| `<stem>_reformatted.rtf` | **same content**, only cosmetic formatting changed | **EQUIVALENT** (0 differences) |
| `<stem>_changed.rtf` | a copy with a few cell values edited in place | one or more `VALUE_DIFF`s |

`../testthat/test-10-real-world.R` checks the stems `cox_hr` and `exp_adj` and **skips
automatically** when the files are absent. Add your own stems (or edit that test) to cover
your outputs.

**Quick way to make a trio from any base file:**

- *reformatted*: copy the file and change a layout-only control word — e.g. `\paperw` (page
  width) or `\margl` (margin). The rendered content is unchanged, so it must compare EQUIVALENT.
- *changed*: copy the file and edit a few cell values **in place** (don't add/remove rows or
  cells), so each edit produces exactly one clean `VALUE_DIFF`.

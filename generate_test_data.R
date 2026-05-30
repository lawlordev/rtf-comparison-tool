#!/usr/bin/env Rscript
# =============================================================================
# generate_test_data.R  --  create synthetic clinical RTF files for testing
# =============================================================================
# Produces three RTF files that mimic a "Summary of Treatment-Emergent Adverse
# Events" table, entirely in R (no Python needed):
#
#   <prefix>_base.rtf         the reference table
#   <prefix>_reformatted.rtf  identical visible content, different cosmetic
#                             RTF markup  -> must compare EQUIVALENT to base
#   <prefix>_changed.rtf      base with exactly 7 in-place content edits
#                             -> must compare to base as 7 VALUE_DIFFs
#
# Deterministic (fixed seed). Exercises Windows-1252 (\'XX) and Unicode (\uN?)
# escapes, repeated pagination header rows, titles/subtitles and footnotes.
#
# Usage (point-and-click): double-click a launcher in windows/ or macos/.
# Usage (command line):
#   Rscript generate_test_data.R [--out DIR] [--rows N] [--seed S] [--quiet]
#     --out   output directory               (default: examples/generated)
#     --rows  extra filler PT rows to add     (default: 60; use e.g. 100000
#             to create a large file for the performance test)
#     --seed  random seed                     (default: 20260529)
# =============================================================================

# ---- character constants (real Unicode; encoded to RTF escapes on render) ---
GE    <- "≥"  # >=
MINUS <- "−"  # minus sign
DEG   <- "°"  # degree
MICRO <- "µ"  # micro
ENDSH <- "–"  # en dash
ALPHA <- "α"; BETA <- "β"
COPYR <- "©"; EACUTE <- "é"; UUML <- "ü"

# ---- RTF text escaping ------------------------------------------------------
# Plain ASCII passes through (with { } \ escaped). Latin-1 characters and the
# cp1252 en dash become \'XX byte escapes; everything else becomes \uN? with a
# single '?' fallback character (matching the RTF \uc1 default).
rtf_escape <- function(s) {
  if (!nzchar(s)) return("")
  cps <- utf8ToInt(s)
  pieces <- vapply(cps, function(cp) {
    if (cp == 0x5C) return("\\\\")
    if (cp == 0x7B) return("\\{")
    if (cp == 0x7D) return("\\}")
    if (cp < 0x80)  return(intToUtf8(cp))
    if (cp == 0x2013) return("\\'96")           # en dash -> cp1252 byte 0x96
    if (cp >= 0xA0 && cp <= 0xFF) return(sprintf("\\'%02x", cp))
    sprintf("\\u%d?", cp)
  }, character(1))
  paste(pieces, collapse = "")
}

# ---- value formatters -------------------------------------------------------
np <- function(n, N) sprintf("%d (%.1f%%)", n, 100 * n / N)
fmtnum <- function(x) sub("^-", MINUS, sprintf("%.1f", x))
ci <- function(lo, hi) sprintf("(%s to %s)", fmtnum(lo), fmtnum(hi))

bump_np <- function(cell, N) {
  n <- as.integer(sub("^\\s*(\\d+).*$", "\\1", cell))
  np(n + 1L, N)
}
bump_ci <- function(cell) {
  nums <- regmatches(cell, gregexpr("[−-]?[0-9.]+", cell))[[1]]
  nums <- as.numeric(gsub(MINUS, "-", nums))
  ci(nums[1] + 0.2, nums[2] + 0.2)
}

# ---- growable element collector (keeps generation O(n) for large files) -----
make_collector <- function(n = 1024L) {
  e <- new.env(parent = emptyenv()); e$buf <- vector("list", n); e$i <- 0L
  list(
    add = function(el) {
      e$i <- e$i + 1L
      if (e$i > length(e$buf)) length(e$buf) <- 2L * length(e$buf)
      e$buf[[e$i]] <- el
    },
    get = function() e$buf[seq_len(e$i)]
  )
}

# ---- clinical content model -------------------------------------------------
HEADER_CELLS <- c(
  "System Organ Class / Preferred Term",
  "Placebo (N=210) n (%)", "Drug 10 mg (N=208) n (%)",
  "Drug 20 mg (N=212) n (%)", "Total (N=630) n (%)",
  "Risk Difference vs Placebo (95% CI)")

SOCS <- list(
  list(soc = "Nervous system disorders",
       pts = c("Headache", "Dizziness", "Somnolence", "Tremor", "Paraesthesia")),
  list(soc = "Gastrointestinal disorders",
       pts = c("Nausea", "Diarrhoea", "Vomiting", "Constipation", "Dyspepsia")),
  list(soc = "General disorders and administration site conditions",
       pts = c("Fatigue", paste0("Pyrexia (Temperature ", DEG, "C increased)"),
               "Asthenia", "Oedema peripheral")),
  list(soc = "Musculoskeletal and connective tissue disorders",
       pts = c("Arthralgia", "Back pain", "Myalgia", "Pain in extremity")),
  list(soc = "Skin and subcutaneous tissue disorders",
       pts = c("Rash", "Pruritus", "Hyperhidrosis")),
  list(soc = "Investigations",
       pts = c(paste0("Alanine aminotransferase increased (", MICRO, "mol/L)"),
               "Blood creatinine increased", "Weight decreased")),
  list(soc = "Psychiatric disorders",
       pts = c("Insomnia", "Anxiety", "Depression")),
  list(soc = "Respiratory, thoracic and mediastinal disorders",
       pts = c("Cough", "Dyspnoea", "Nasal congestion")),
  list(soc = "Cardiac disorders", pts = c("Palpitations", "Tachycardia")),
  list(soc = "Infections and infestations",
       pts = c("Nasopharyngitis", "Upper respiratory tract infection",
               "Urinary tract infection")))

build_model <- function(n_filler = 60L, seed = 20260529L) {
  set.seed(seed)
  co <- make_collector(1024L + as.integer(n_filler) * 2L)
  add <- co$add
  data_count <- 0L

  emit_header <- function() add(list(kind = "header", cells = HEADER_CELLS))
  add_data <- function(label, tag = NULL) {
    if (data_count > 0L && data_count %% 25L == 0L) emit_header()  # pagination
    p  <- sample(0:60, 1); d1 <- sample(0:60, 1); d2 <- sample(0:60, 1)
    tot <- p + d1 + d2
    lo <- round(stats::runif(1, -2, 1), 1)
    hi <- round(lo + stats::runif(1, 1, 5), 1)
    cells <- c(label, np(p, 210), np(d1, 208), np(d2, 212), np(tot, 630), ci(lo, hi))
    el <- list(kind = "row", cells = cells)
    if (!is.null(tag)) el$tag <- tag
    add(el)
    data_count <<- data_count + 1L
  }

  add(list(kind = "title",    text = "Table 14.3.1.2"))
  add(list(kind = "title",    text = paste0("Summary of Treatment-Emergent Adverse ",
                                            "Events by System Organ Class and Preferred Term")))
  add(list(kind = "subtitle", text = "Safety Population", tag = "subtitle"))
  add(list(kind = "spacer"))

  emit_header()
  add_data(paste0("Subjects with ", GE, "1 TEAE"))
  add_data(paste0("Subjects with ", GE, "1 serious TEAE"))

  for (s in SOCS) {
    add_data(s$soc)
    for (pt in s$pts) add_data(paste0("    ", pt), tag = pt)
  }
  for (k in seq_len(as.integer(n_filler)))
    add_data(sprintf("    Preferred term %d.%d", 50L + (k %/% 10L), k %% 10L))

  add(list(kind = "emptyrow"))
  add(list(kind = "footspacer"))
  add(list(kind = "footnote", text = "Note: Subjects are counted once within each System Organ Class and Preferred Term."))
  add(list(kind = "footnote", text = "TEAE = treatment-emergent adverse event; CI = confidence interval; n = number of subjects with the event."))
  add(list(kind = "footnote", text = paste0("Risk differences use the Miettinen", ENDSH,
                                            "Nurminen method at ", ALPHA, "-level = 0.05.")))
  add(list(kind = "footnote", text = paste0("Population includes subjects who received ", GE,
                                            "1 dose of study drug; ", BETA,
                                            "-blocker use was balanced across arms.")))
  add(list(kind = "footnote",
           text = paste0("Generated by Lawlor Solutions. ", COPYR,
                         "2026 Sponsor Pharmaceuticals. Sites: Montr", EACUTE, "al, Z", UUML, "rich."),
           tag = "sponsor"))
  co$get()
}

# ---- apply the 7 in-place edits (base -> changed) ---------------------------
apply_edits <- function(model) {
  m <- model
  idx <- function(tag) which(vapply(m, function(el)
    !is.null(el$tag) && el$tag == tag, logical(1)))[1]
  edits <- list()
  rec <- function(desc, old, new) edits[[length(edits) + 1L]] <<-
    data.frame(edit = desc, old = old, new = new, stringsAsFactors = FALSE)

  i <- idx("subtitle")
  old <- m[[i]]$text; m[[i]]$text <- paste0(old, " (Final)")
  rec("Subtitle", old, m[[i]]$text)

  i <- idx("Headache")
  old <- m[[i]]$cells[2]; m[[i]]$cells[2] <- bump_np(old, 210); rec("Headache / Placebo (col 2)", old, m[[i]]$cells[2])
  old <- m[[i]]$cells[4]; m[[i]]$cells[4] <- bump_np(old, 212); rec("Headache / Drug 20 mg (col 4)", old, m[[i]]$cells[4])

  i <- idx("Nausea")
  old <- m[[i]]$cells[5]; m[[i]]$cells[5] <- bump_np(old, 630); rec("Nausea / Total (col 5)", old, m[[i]]$cells[5])

  i <- idx("Dizziness")
  old <- m[[i]]$cells[6]; m[[i]]$cells[6] <- bump_ci(old); rec("Dizziness / Risk Difference (col 6)", old, m[[i]]$cells[6])

  i <- idx("Fatigue")
  old <- m[[i]]$cells[1]; m[[i]]$cells[1] <- paste0(old, "s"); rec("Fatigue label (col 1)", old, m[[i]]$cells[1])

  i <- idx("sponsor")
  old <- m[[i]]$text; m[[i]]$text <- sub("Sponsor Pharmaceuticals", "Sponsor Pharma", old)
  rec("Sponsor footnote", "...Sponsor Pharmaceuticals...", "...Sponsor Pharma...")

  list(model = m, edits = do.call(rbind, edits))
}

# ---- renderers --------------------------------------------------------------
STYLE_BASE <- list(title_fs = 24, header_fs = 18, data_fs = 18, footnote_fs = 16,
                   trgaph = 108, cellx = c(2880, 4320, 5760, 7200, 8640, 10080),
                   header_bold = FALSE, spacer_sa = 120, footer_sa = 60)
STYLE_REFORMATTED <- list(title_fs = 26, header_fs = 20, data_fs = 20, footnote_fs = 16,
                          trgaph = 144, cellx = c(3000, 4500, 6000, 7500, 9000, 10500),
                          header_bold = TRUE, spacer_sa = 160, footer_sa = 80)

render_element <- function(el, style) {
  cellx_str <- paste0(sprintf("\\cellx%d", style$cellx), collapse = "")
  emit_row <- function(cells, fs, font, bold) {
    cellrtf <- vapply(cells, function(cv) {
      content <- rtf_escape(cv)
      if (bold && nzchar(content)) content <- sprintf("{\\b %s}", content)
      sprintf("\\pard\\intbl\\plain\\%s\\fs%d %s\\cell", font, fs, content)
    }, character(1), USE.NAMES = FALSE)
    c(sprintf("\\trowd\\trgaph%d\\trleft0", style$trgaph), cellx_str, cellrtf, "\\row")
  }
  switch(el$kind,
    title     = sprintf("\\pard\\plain\\f1\\fs%d\\qc %s\\par", style$title_fs, rtf_escape(el$text)),
    subtitle  = sprintf("\\pard\\plain\\f1\\fs%d\\qc %s\\par", style$title_fs, rtf_escape(el$text)),
    spacer    = sprintf("\\pard\\plain\\sa%d\\par", style$spacer_sa),
    footspacer= sprintf("\\pard\\plain\\sa%d\\par", style$footer_sa),
    footnote  = sprintf("\\pard\\plain\\f1\\fs%d %s\\par", style$footnote_fs, rtf_escape(el$text)),
    header    = emit_row(el$cells, style$header_fs, "f1", style$header_bold),
    row       = emit_row(el$cells, style$data_fs, "f0", FALSE),
    emptyrow  = emit_row(rep("", 6), style$data_fs, "f0", FALSE))
}

render_rtf <- function(model, style) {
  chunks <- vector("list", length(model) + 2L)
  chunks[[1]] <- c(
    "{\\rtf1\\ansi\\ansicpg1252\\deff0",
    "{\\fonttbl{\\f0\\fnil\\fcharset0 Courier New;}{\\f1\\fswiss\\fcharset0 Arial;}}",
    "\\paperw12240\\paperh15840\\margl1080\\margr1080\\margt1080\\margb1080\\landscape")
  for (k in seq_along(model)) chunks[[k + 1L]] <- render_element(model[[k]], style)
  chunks[[length(chunks)]] <- "}"
  unlist(chunks, use.names = FALSE)
}

# ---- top-level generate -----------------------------------------------------
generate_test_data <- function(out_dir, n_filler = 60L, seed = 20260529L,
                               prefix = "clinical_table", verbose = TRUE) {
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  model <- build_model(n_filler = n_filler, seed = seed)
  ed    <- apply_edits(model)

  files <- c(
    base        = file.path(out_dir, paste0(prefix, "_base.rtf")),
    reformatted = file.path(out_dir, paste0(prefix, "_reformatted.rtf")),
    changed     = file.path(out_dir, paste0(prefix, "_changed.rtf")))
  writeLines(render_rtf(model,    STYLE_BASE),        files["base"])
  writeLines(render_rtf(model,    STYLE_REFORMATTED), files["reformatted"])
  writeLines(render_rtf(ed$model, STYLE_BASE),        files["changed"])

  if (verbose) {
    n_rows <- sum(vapply(model, function(e) e$kind %in% c("row", "header", "emptyrow"), logical(1)))
    cat(sprintf("Generated 3 files in: %s\n", normalizePath(out_dir)))
    for (nm in names(files)) cat(sprintf("  %-12s %s\n", nm, basename(files[nm])))
    cat(sprintf("\nTable rows per file: %d   (filler PT rows: %d)\n", n_rows, n_filler))
    cat("\nThe 7 edits applied in '_changed.rtf' (base -> changed):\n")
    print(ed$edits, row.names = FALSE, right = FALSE)
    cat("\nExpected comparison results:\n")
    cat("  base vs reformatted -> EQUIVALENT (0 differences)\n")
    cat("  base vs changed     -> 7 VALUE_DIFF differences\n")
  }
  invisible(files)
}

# ============================================================================
# CLI / point-and-click entry point
# ============================================================================
.is_main <- function() {
  ca <- commandArgs(FALSE)
  fa <- sub("^--file=", "", ca[grepl("^--file=", ca)])
  length(fa) > 0L && basename(fa[[1]]) == "generate_test_data.R"
}

if (.is_main()) {
  args <- commandArgs(trailingOnly = TRUE)
  getarg <- function(flag, default) {
    i <- which(args == flag)
    if (length(i) && i < length(args)) args[i + 1L] else default
  }
  quiet <- "--quiet" %in% args

  script_dir <- dirname(sub("^--file=", "",
                            commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))][1]))
  default_out <- file.path(script_dir, "examples", "generated")

  out_dir  <- getarg("--out", NA_character_)
  n_filler <- as.integer(getarg("--rows", "60"))
  seed     <- as.integer(getarg("--seed", "20260529"))

  # If no --out given and not quiet, offer an interactive folder picker.
  if (is.na(out_dir) && !quiet) {
    have_tcltk <- requireNamespace("tcltk", quietly = TRUE) &&
      isTRUE(tryCatch({ tcltk::tclvalue(tcltk::tclVar("ok")); TRUE }, error = function(e) FALSE))
    if (have_tcltk) {
      cat("Choose the output folder for the generated test files...\n")
      d <- tryCatch(as.character(tcltk::tkchooseDirectory(
        title = "Choose output folder for generated RTF test files")),
        error = function(e) "")
      if (length(d) && nzchar(d)) out_dir <- d
    }
  }
  if (is.na(out_dir)) out_dir <- default_out

  cat("============================================================\n")
  cat("RTF Comparison Tool - test-data generator\n")
  cat("============================================================\n")
  files <- generate_test_data(out_dir, n_filler = n_filler, seed = seed, verbose = !quiet)

  # Self-verify against the engine when available (reassuring sanity check).
  engine <- file.path(script_dir, "compare_rtf.R")
  if (file.exists(engine)) {
    source(engine)
    r1 <- compare_rtf(files["base"], files["reformatted"], console = FALSE)
    r2 <- compare_rtf(files["base"], files["changed"], console = FALSE)
    cat("\nSelf-check:\n")
    cat(sprintf("  base vs reformatted: %s (%d diffs)  [expected EQUIVALENT]\n",
                if (r1$equivalent) "EQUIVALENT" else "DIFFERENCES", r1$n_diffs))
    cat(sprintf("  base vs changed:     %s (%d diffs)  [expected 7 diffs]\n",
                if (r2$equivalent) "EQUIVALENT" else "DIFFERENCES", r2$n_diffs))
    ok <- r1$equivalent && !r2$equivalent && r2$n_diffs == 7L
    cat(sprintf("  -> %s\n", if (ok) "PASS" else "UNEXPECTED - please review"))
  }
  cat("\nDone.\n")
}

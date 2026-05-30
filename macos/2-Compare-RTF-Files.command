#!/bin/bash
# ============================================================================
#  Compare two RTF files by PATH (macOS)
#  Double-click this file, then paste/type the two file paths when prompted.
#  A report is saved next to the first file.
#  (Prefer clicking files instead? Use 2b-Compare-Using-File-Picker.command.)
# ============================================================================
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
RSCRIPT=""
for c in "$(command -v Rscript)" /usr/local/bin/Rscript /opt/homebrew/bin/Rscript \
         /Library/Frameworks/R.framework/Resources/bin/Rscript; do
  if [ -n "$c" ] && [ -x "$c" ]; then RSCRIPT="$c"; break; fi
done
if [ -z "$RSCRIPT" ]; then
  echo "Could not find R. Install it from https://cran.r-project.org and try again."
  read -n 1 -s -r -p "Press any key to close..."; echo; exit 2
fi
"$RSCRIPT" "$ROOT/R/run_compare_paths.R"
echo
read -n 1 -s -r -p "Press any key to close..."; echo

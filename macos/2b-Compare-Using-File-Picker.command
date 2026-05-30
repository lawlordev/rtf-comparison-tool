#!/bin/bash
# ============================================================================
#  Compare two RTF files using FILE-PICKER dialogs (macOS)
#  Alternative to 2-Compare-RTF-Files.command for those who prefer clicking
#  files instead of pasting paths. Two dialogs appear; pick the two files.
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
"$RSCRIPT" "$ROOT/run_compare.R"
echo
read -n 1 -s -r -p "Press any key to close..."; echo

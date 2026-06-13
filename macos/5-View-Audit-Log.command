#!/bin/bash
# ============================================================================
#  View the AUDIT LOG (macOS)
#  Opens logs/audit_log.csv -- the timestamped record of every comparison run
#  (including runs that found no differences). Open it in Excel/Numbers to see,
#  sort, or print proof of which files/folders were checked and when.
# ============================================================================
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
LOG="$ROOT/logs/audit_log.csv"
if [ ! -f "$LOG" ]; then
  echo "No audit log yet: $LOG"
  echo "It is created automatically the first time you run a comparison."
  read -n 1 -s -r -p "Press any key to close..."; echo; exit 0
fi
echo "Opening audit log: $LOG"
open "$LOG"

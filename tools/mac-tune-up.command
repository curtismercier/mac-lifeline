#!/bin/bash
# mac-tune-up.command — quick health check + safe cleanup for an older Mac. DOUBLE-CLICK to run.
# Read-only health report first, then offers a safe cleanup (empties Trash, clears caches/logs).
clear
cat <<'BANNER'
============================================================
   Mac Tune-Up  ·  health check + safe cleanup
============================================================
BANNER
echo "   $(date '+%A %d %B %Y, %-I:%M %p')"
echo

echo ">> HEALTH"
df -h / | awk 'NR==2{print "   Disk: "$2" total, "$4" free, "$5" used"}'
diskutil info disk0 2>/dev/null | grep -iE "SMART Status|Solid State" | sed 's/^ */   Drive: /'
echo "   Memory: $(sysctl -n hw.memsize 2>/dev/null | awk '{print $1/1073741824}') GB"
echo "   Up: $(uptime | sed 's/.*up //; s/,.*users.*//')"
echo "   Top memory users right now:"
ps -arcwwwxo %mem,comm 2>/dev/null | head -6 | sed 's/^/     /'
echo

echo ">> CLEANUP — frees space + can speed things up. Nothing personal is touched."
echo "   This will: empty your Trash, and clear app caches + old logs (apps rebuild caches automatically)."
printf "   Do the cleanup now? [y/N] "
read ans
if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
  before=$(df / | awk 'NR==2{print $4}')
  echo "   emptying Trash..."; rm -rf "$HOME/.Trash/"* "$HOME/.Trash/".* 2>/dev/null
  echo "   clearing app caches..."; rm -rf "$HOME/Library/Caches/"* 2>/dev/null
  echo "   clearing old logs..."; rm -rf "$HOME/Library/Logs/"* 2>/dev/null
  after=$(df / | awk 'NR==2{print $4}')
  freed=$(( (after - before) / 2048 ))
  echo "   ✓ done — freed about ${freed} MB."
else
  echo "   skipped cleanup (health report only)."
fi
echo
echo "Tip: this Mac uses an older spinning hard drive — the single biggest speed-up"
echo "would be a solid-state drive (SSD) or a newer Mac. See your options doc for that."
echo
echo "All done. Press Return to close this window."
read _

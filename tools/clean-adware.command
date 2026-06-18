#!/bin/bash
# clean-adware.command — thorough Mac adware / junk-software remover.
#
# DOUBLE-CLICK to run (it opens in Terminal), or from a shell:
#     bash clean-adware.command [--dry-run]
#
# Safe by design: it SCANS first, shows you EXACTLY what it found, and removes
# nothing until you type "yes". It only matches KNOWN adware names — it never
# guesses. Re-runnable any time.
#
#   -n, --dry-run   Show what WOULD be removed, then exit. Never deletes, never prompts.
#   -h, --help      Show this help.
#
# Covers MacKeeper, Adload / "Search Manager", Genieo, Bundlore, Pirrit, and other
# common Mac adware families — across ALL user accounts and the system folders.
# Add a new family to the PAT list below (one-line change).

DRY=0
for a in "$@"; do
  case "$a" in
    -n|--dry-run) DRY=1 ;;
    -h|--help)
      awk 'NR==1{next} /^#/{sub(/^# ?/,"");print;next} {exit}' "$0"
      exit 0 ;;
    *) echo "unknown option: $a (try --help)" >&2; exit 2 ;;
  esac
done

clear
cat <<'BANNER'
============================================================
   Mac Adware Cleaner
   Removes known junk software. Safe — adware only.
============================================================
BANNER
echo "   $(date '+%A %d %B %Y, %-I:%M %p')"
[ "$DRY" = 1 ] && echo "   DRY RUN — nothing will be removed."
echo

# --- known-adware name patterns (case-insensitive). Add new ones here. ---
PAT='mackeeper|search.?manager|updater_mcy|\.mcy\.|com\.updater\..*mcy|genieo|bundlore|pirrit|installmac|spaceship|advancedmaccleaner|searchmine|pcvark|mac.?auto.?fixer|mediadownloader|cleanup.?mymac'

echo "You'll be asked for your Mac password once, so I can check every account."
sudo -v || { echo "Need your password to check every account — try again."; echo "Press Return to close."; read -r _; exit 1; }
echo

# ---- pass 1: COLLECT every match (no deletion) into HITS[] ----
HITS=()
collect() {  # $1 = directory to scan for adware-named items
  local d="$1" f; [ -d "$d" ] || return
  while IFS= read -r f; do
    [ -n "$f" ] && HITS+=("$d/$f")
  done < <(sudo ls -1A "$d" 2>/dev/null | grep -iE "$PAT")
}

scan_all() {
  HITS=()
  local home sub sysd app
  for home in /Users/* /var/root; do
    [ -d "$home/Library" ] || continue
    case "$(basename "$home")" in Shared|.localized) continue ;; esac
    for sub in "LaunchAgents" "Application Support" "Preferences" "Caches" "Containers" \
               "Saved Application State" "Cookies" "HTTPStorages" "Safari/Extensions"; do
      collect "$home/Library/$sub"
    done
  done
  for sysd in "/Library/LaunchAgents" "/Library/LaunchDaemons" "/Library/Application Support" "/Library/Caches"; do
    collect "$sysd"
  done
  for app in /Applications/*.app; do
    [ -e "$app" ] || continue
    echo "$app" | grep -iqE "$PAT" && HITS+=("$app")
  done
}

echo ">> Scanning all user accounts + system folders..."
scan_all
echo "   done"
echo

# ---- report what was found ----
if [ "${#HITS[@]}" -eq 0 ]; then
  echo "   ✓ CLEAN — no known adware found on any account."
  echo
  [ "$DRY" = 1 ] || { echo "Nothing to remove. Press Return to close."; read -r _; }
  exit 0
fi

echo ">> Found ${#HITS[@]} item(s) matching known adware:"
for p in "${HITS[@]}"; do echo "   • $p"; done
echo

if [ "$DRY" = 1 ]; then
  echo "DRY RUN — nothing was removed."
  echo "Re-run without --dry-run to remove the items listed above."
  exit 0
fi

# ---- confirm, then remove ----
printf "Remove these %s item(s)? Type 'yes' to confirm: " "${#HITS[@]}"
read -r ans
case "$ans" in
  yes|YES|Yes) ;;
  *) echo "Cancelled — nothing removed."; echo "Press Return to close."; read -r _; exit 0 ;;
esac
echo

echo ">> Stopping any running junk..."
pkill -i mackeeper 2>/dev/null; sudo pkill -i mackeeper 2>/dev/null
echo "   done"

echo ">> Removing..."
for p in "${HITS[@]}"; do
  echo "   removing: $p"
  sudo rm -rf "$p" 2>/dev/null
done
echo "   done"
echo

# ---- verify ----
echo ">> Verifying..."
scan_all
if [ "${#HITS[@]}" -eq 0 ]; then
  echo "   ✓ CLEAN — no known adware found on any account."
else
  echo "   ⚠ ${#HITS[@]} item(s) remain — send this list to your tech:"
  for p in "${HITS[@]}"; do echo "      $p"; done
fi
echo
echo "Recommended: restart the Mac to clear anything still in memory."
echo "All done. Press Return to close this window."
read -r _

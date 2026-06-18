#!/bin/bash
# clean-adware.command — thorough Mac adware / junk-software remover.
# DOUBLE-CLICK to run (it opens in Terminal). Safe: it only removes files whose names
# match KNOWN adware, and it prints every single thing it deletes. Re-runnable anytime.
#
# Covers everything we found on this Mac (MacKeeper, the "Search Manager" Safari add-on,
# the mcy/Adload "updater") plus other common Mac adware families — across ALL user
# accounts and the system folders.

clear
cat <<'BANNER'
============================================================
   Mac Adware Cleaner
   Removes known junk software. Safe — adware only.
============================================================
BANNER
echo "   $(date '+%A %d %B %Y, %-I:%M %p')"
echo

# --- known-adware name patterns (case-insensitive). Add new ones here. ---
PAT='mackeeper|search.?manager|updater_mcy|\.mcy\.|com\.updater\..*mcy|genieo|bundlore|pirrit|installmac|spaceship|advancedmaccleaner|searchmine|pcvark|mac.?auto.?fixer|mediadownloader|cleanup.?mymac'

echo "You'll be asked for your Mac password once, so I can check every account."
sudo -v || { echo "Need your password to do a full clean — try again."; echo "Press Return to close."; read _; exit 1; }
echo

echo ">> Stopping any running junk..."
pkill -i mackeeper 2>/dev/null; sudo pkill -i mackeeper 2>/dev/null
echo "   done"
echo

scan() {  # $1 = directory to scan for adware-named items
  local d="$1"; [ -d "$d" ] || return
  ls -1A "$d" 2>/dev/null | grep -iE "$PAT" | while IFS= read -r f; do
    echo "   removing: $d/$f"
    sudo rm -rf "$d/$f" 2>/dev/null
  done
}

echo ">> Scanning all user accounts + system folders..."
for home in /Users/* /var/root; do
  [ -d "$home/Library" ] || continue
  case "$(basename "$home")" in Shared|.localized) continue;; esac
  for sub in "LaunchAgents" "Application Support" "Preferences" "Caches" "Containers" \
             "Saved Application State" "Cookies" "HTTPStorages" "Safari/Extensions"; do
    scan "$home/Library/$sub"
  done
done
for sysd in "/Library/LaunchAgents" "/Library/LaunchDaemons" "/Library/Application Support" "/Library/Caches"; do
  scan "$sysd"
done
echo "   done"
echo

echo ">> Checking /Applications..."
for app in /Applications/*.app; do
  if echo "$app" | grep -iqE "$PAT"; then echo "   removing: $app"; sudo rm -rf "$app"; fi
done
echo "   done"
echo

echo ">> Verifying..."
LEFT=""
for home in /Users/*; do
  [ -d "$home/Library" ] || continue
  for sub in "LaunchAgents" "Application Support" "Preferences" "Caches" "Containers" "Safari/Extensions"; do
    h=$(ls -1A "$home/Library/$sub" 2>/dev/null | grep -iE "$PAT")
    [ -n "$h" ] && LEFT="$LEFT\n   $home/Library/$sub:\n$(echo "$h" | sed 's/^/      /')"
  done
done
if [ -z "$LEFT" ]; then
  echo "   ✓ CLEAN — no known adware found on any account."
else
  echo "   ⚠ Some items remain — send this to your tech:"; printf "$LEFT\n"
fi
echo
echo "Recommended: restart the Mac to clear anything still in memory."
echo "All done. Press Return to close this window."
read _

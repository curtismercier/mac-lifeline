#!/bin/bash
# uninstall.command — cleanly remove the mac-lifeline reverse tunnel from THIS Mac.
#
# DOUBLE-CLICK to run (it opens in Terminal), or from a shell:
#     bash uninstall.command [--label com.example.mactunnel]
#
# Reverses what tunnel/mac-setup.sh installed: stops + unloads the launchd daemon,
# removes its plist, key directory, and log. Does NOT touch your ~/.ssh/authorized_keys
# (so it can't lock you out by surprise) — it tells you how, if you want that too.

# ===================== must match the LABEL used in mac-setup.sh =====================
LABEL="com.example.mactunnel"
# ====================================================================================
case "${1:-}" in
  --label) LABEL="${2:?--label needs a value}" ;;
  -h|--help) awk 'NR==1{next} /^#/{sub(/^# ?/,"");print;next} {exit}' "$0"; exit 0 ;;
  "") ;;
  *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

ETC="/usr/local/etc/${LABEL}"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
LOG="/var/log/${LABEL}.log"

clear
cat <<BANNER
============================================================
   mac-lifeline — Remove Remote Support
============================================================
   Tunnel label: ${LABEL}
BANNER
echo

if [ ! -f "$PLIST" ] && [ ! -d "$ETC" ]; then
  echo "Nothing to remove for label '${LABEL}'."
  echo "If you used a different launchd label, re-run with:  --label <your.label>"
  echo "Press Return to close."; read -r _; exit 0
fi

echo "This will stop and remove the remote-support tunnel:"
[ -f "$PLIST" ] && echo "   • daemon   $PLIST"
[ -d "$ETC" ]   && echo "   • keys     $ETC"
[ -f "$LOG" ]   && echo "   • log      $LOG"
echo
printf "Remove it? Type 'yes' to confirm: "
read -r ans
case "$ans" in yes|YES|Yes) ;; *) echo "Cancelled."; echo "Press Return to close."; read -r _; exit 0 ;; esac
echo

echo "You'll be asked for your Mac password once."
sudo -v || { echo "Need your password to remove a system daemon — try again."; read -r _; exit 1; }
echo

echo ">> Stopping + unloading the daemon..."
sudo launchctl unload -w "$PLIST" 2>/dev/null
# belt-and-suspenders: kill any lingering ssh started from this label's key
sudo pkill -f "$ETC/id_tunnel" 2>/dev/null
echo "   done"

echo ">> Removing files..."
sudo rm -f  "$PLIST" && echo "   removed $PLIST"
sudo rm -rf "$ETC"   && echo "   removed $ETC"
sudo rm -f  "$LOG"   && echo "   removed $LOG"
echo "   done"
echo

echo "✓ Remote support has been removed from this Mac."
echo
echo "Note: your admin account's ~/.ssh/authorized_keys was left untouched."
echo "If a control key was installed and you want it gone too, edit that file by hand."
echo
echo "Press Return to close this window."
read -r _

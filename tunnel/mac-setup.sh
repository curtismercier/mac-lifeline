#!/bin/bash
# mac-lifeline — reverse-SSH tunnel installer for the OLD MAC. Built-in ssh + launchd only (works on 10.13+).
# Asks for your Mac password once. Configure via env vars (works with curl | bash) OR by editing the
# defaults below (works with a local clone). Env vars win.
#
#   Pipe it straight onto the Mac — nothing to clone, nothing to edit:
#     curl -fsSL https://raw.githubusercontent.com/curtismercier/mac-lifeline/master/tunnel/mac-setup.sh \
#       | VPS_HOST=1.2.3.4 LABEL=com.you.mactunnel bash
#
#   …or clone the repo, edit the defaults below, and run:  bash mac-setup.sh
set -u

# ===================== CONFIG (env vars override these defaults) =====================
VPS_HOST="${VPS_HOST:-YOUR_VPS_IP_OR_HOST}"   # where the container listens (public-reachable from the Mac)
VPS_PORT="${VPS_PORT:-47222}"                 # public port on the VPS  ->  container :22
TUN_USER="${TUN_USER:-tunnel}"                # the locked-down user inside the container
REVERSE_PORT="${REVERSE_PORT:-9922}"          # container-internal port -> this Mac's :22 (match sshd permitlisten)
CONTROL_PUBKEY="${CONTROL_PUBKEY:-}"          # OPTIONAL: your control pubkey to install on this Mac's admin account
LABEL="${LABEL:-com.example.mactunnel}"       # launchd label — unique per deployment (reverse-DNS style)
# =====================================================================================

if [ -z "$VPS_HOST" ] || [ "$VPS_HOST" = "YOUR_VPS_IP_OR_HOST" ]; then
  echo "ERROR: set VPS_HOST to your VPS IP/hostname before running. For example:" >&2
  echo "  curl -fsSL <raw-url>/tunnel/mac-setup.sh | VPS_HOST=1.2.3.4 LABEL=com.you.mactunnel bash" >&2
  exit 1
fi

ETC="/usr/local/etc/${LABEL}"; KEY="$ETC/id_tunnel"; PLIST="/Library/LaunchDaemons/${LABEL}.plist"

echo "Installing reverse tunnel  ->  ${VPS_HOST}:${VPS_PORT}"
sudo mkdir -p "$ETC"
sudo test -f "$KEY" || sudo ssh-keygen -t ed25519 -N "" -f "$KEY" -C "mac-lifeline-tunnel" -q
sudo chmod 600 "$KEY"; sudo chmod 644 "$KEY.pub"

sudo tee "$PLIST" >/dev/null <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key><array>
    <string>/usr/bin/ssh</string><string>-N</string>
    <string>-i</string><string>${KEY}</string>
    <string>-o</string><string>IdentitiesOnly=yes</string>
    <string>-o</string><string>StrictHostKeyChecking=no</string>
    <string>-o</string><string>UserKnownHostsFile=/dev/null</string>
    <string>-o</string><string>ServerAliveInterval=30</string>
    <string>-o</string><string>ServerAliveCountMax=3</string>
    <string>-o</string><string>ExitOnForwardFailure=yes</string>
    <string>-R</string><string>127.0.0.1:${REVERSE_PORT}:localhost:22</string>
    <string>-p</string><string>${VPS_PORT}</string>
    <string>${TUN_USER}@${VPS_HOST}</string>
  </array>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/><key>ThrottleInterval</key><integer>15</integer>
  <key>StandardOutPath</key><string>/var/log/${LABEL}.log</string>
  <key>StandardErrorPath</key><string>/var/log/${LABEL}.log</string>
</dict></plist>
PLIST
sudo chown root:wheel "$PLIST"; sudo chmod 644 "$PLIST"
sudo launchctl unload "$PLIST" 2>/dev/null; sudo launchctl load -w "$PLIST"

if [ -n "$CONTROL_PUBKEY" ]; then
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"; touch "$HOME/.ssh/authorized_keys"; chmod 600 "$HOME/.ssh/authorized_keys"
  grep -qF "$CONTROL_PUBKEY" "$HOME/.ssh/authorized_keys" || echo "$CONTROL_PUBKEY" >> "$HOME/.ssh/authorized_keys"
  echo "control key installed for $(whoami)"
fi

echo
echo "Put THIS public key in the container's authorized_keys (env TUNNEL_PUBKEY), then (re)start it:"
echo
sudo cat "$KEY.pub"
echo
echo "Connect:  ssh -J you@${VPS_HOST} -p ${REVERSE_PORT} <admin>@127.0.0.1"

echo
echo "------------------------------------------------------------"
echo "ONE LAST THING - the Mac must accept the incoming SSH for this to work:"
if (exec 3<>/dev/tcp/127.0.0.1/22) 2>/dev/null; then
  echo "  [ OK ] Remote Login (SSH) is ON - good, you'll be able to connect."
else
  echo "  [ !! ] Remote Login (SSH) looks OFF - the tunnel will connect, but you"
  echo "         can't log in until you turn it on:"
  echo "           System Settings > General > Sharing > Remote Login  (allow your admin user)"
  echo "           ...or:  sudo systemsetup -setremotelogin on"
fi
echo
echo "  For an always-available line, also set on this Mac:"
echo "   - keep it awake       Energy Saver: computer sleep = Never (display may still sleep)"
echo "   - power-cut recovery  Energy Saver: 'Start up automatically after a power failure'"
echo "   - macOS 10.15+        grant Full Disk Access to sshd for full remote admin"
echo "   - FileVault on?       unattended reboots won't reconnect until someone unlocks at the Mac"
echo "------------------------------------------------------------"

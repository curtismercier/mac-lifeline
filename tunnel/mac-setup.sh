#!/bin/bash
# mac-lifeline — reverse-SSH tunnel installer for the OLD MAC. Built-in ssh + launchd only (works on 10.13+).
# 1) edit the CONFIG block below.  2) run:  bash mac-setup.sh   (asks for your Mac password once).
set -u

# ===================== CONFIG — edit these =====================
VPS_HOST="YOUR_VPS_IP_OR_HOST"     # where the container listens (must be public-reachable from the Mac)
VPS_PORT="47222"                   # public port on the VPS  ->  container :22
TUN_USER="tunnel"                  # the locked-down user inside the container
REVERSE_PORT="9922"                # container-internal port -> this Mac's :22 (must match sshd permitlisten)
CONTROL_PUBKEY=""                  # OPTIONAL: your control pubkey to install on this Mac's admin account
LABEL="com.example.mactunnel"      # launchd label — rename per deployment (reverse-DNS style)
# ===============================================================

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

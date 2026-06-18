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
# --- remote-onboarding modes (set by the hosted installer; see docs/REMOTE-ONBOARDING.md) ---
TUNNEL_PRIVKEY="${TUNNEL_PRIVKEY:-}"          # LEVEL 2: tech-supplied, pre-authorized key -> client sends nothing
ENROLL_URL="${ENROLL_URL:-}"                  # LEVEL 3: POST our pubkey here to self-enroll -> client sends nothing
ENROLL_TOKEN="${ENROLL_TOKEN:-}"              # LEVEL 3: one-time bearer token for ENROLL_URL
# =====================================================================================

if [ -z "$VPS_HOST" ] || [ "$VPS_HOST" = "YOUR_VPS_IP_OR_HOST" ]; then
  echo "ERROR: set VPS_HOST to your VPS IP/hostname before running. For example:" >&2
  echo "  curl -fsSL <raw-url>/tunnel/mac-setup.sh | VPS_HOST=1.2.3.4 LABEL=com.you.mactunnel bash" >&2
  exit 1
fi

ETC="/usr/local/etc/${LABEL}"; KEY="$ETC/id_tunnel"; PLIST="/Library/LaunchDaemons/${LABEL}.plist"

echo
echo "You'll be asked for your Mac password once."
echo "Heads up: it won't show anything as you type - that's normal Mac security. Type it and press Return."
sudo -v || { echo "Need your password to set this up - please run it again."; exit 1; }

echo "Installing reverse tunnel  ->  ${VPS_HOST}:${VPS_PORT}"
sudo mkdir -p "$ETC"
if [ -n "$TUNNEL_PRIVKEY" ]; then
  # LEVEL 2: install the tech's pre-authorized key as-is (client sends nothing back).
  printf '%s\n' "$TUNNEL_PRIVKEY" | sudo tee "$KEY" >/dev/null
  sudo chmod 600 "$KEY"
  sudo sh -c "ssh-keygen -y -f '$KEY' > '$KEY.pub'" 2>/dev/null
else
  sudo test -f "$KEY" || sudo ssh-keygen -t ed25519 -N "" -f "$KEY" -C "mac-lifeline-tunnel" -q
fi
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

PUB="$(sudo cat "$KEY.pub")"

# --- make sure the Mac will ACCEPT the incoming SSH (Remote Login is off by default) ---
if (exec 3<>/dev/tcp/127.0.0.1/22) 2>/dev/null; then
  RLOGIN=on
else
  sudo systemsetup -f -setremotelogin on >/dev/null 2>&1 || true   # works pre-10.15; needs FDA on 10.15+
  sleep 1
  if (exec 3<>/dev/tcp/127.0.0.1/22) 2>/dev/null; then
    RLOGIN=on; echo "Turned on Remote Login for you."
  else
    RLOGIN=off
    open "x-apple.systempreferences:com.apple.preferences.sharing?Services_RemoteLogin" 2>/dev/null || true
  fi
fi

# --- handoff strategy: how the tech's access gets authorized ---
ENROLLED=0
if [ -n "$TUNNEL_PRIVKEY" ]; then
  ENROLLED=1                                   # LEVEL 2: key was pre-authorized by the tech
elif [ -n "$ENROLL_URL" ]; then                # LEVEL 3: self-enroll our pubkey, no send-back
  if curl -fsS -X POST "$ENROLL_URL" -H "Authorization: Bearer ${ENROLL_TOKEN}" \
       --data-urlencode "pubkey=${PUB}" >/dev/null 2>&1; then
    ENROLLED=1
  fi
fi

echo
echo "------------------------------------------------------------"
if [ "$ENROLLED" = 1 ]; then
  echo "  All set on this Mac. Your tech can connect when you ask - nothing for you to send."
else
  # LEVEL 1: hand the tech our pubkey. Copy it to the clipboard so it can't be fumbled.
  if printf '%s' "$PUB" | pbcopy 2>/dev/null; then
    echo "  Almost done - we copied a setup code to your clipboard."
  else
    echo "  Almost done - copy the code below and send it to your tech."
  fi
  echo "  Please PASTE it into your reply to your tech:"
  echo
  echo "    $PUB"
fi

if [ "$RLOGIN" = off ]; then
  echo
  echo "  One quick toggle is needed (a Settings window just opened):"
  echo "    Sharing  ->  turn ON 'Remote Login', and allow your admin user."
fi

echo
echo "  (Always-on tips for the tech: no system sleep, restart after power failure,"
echo "   Full Disk Access for sshd on macOS 10.15+, FileVault off for hands-free reboots.)"
echo "------------------------------------------------------------"

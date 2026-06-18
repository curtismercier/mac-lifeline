#!/bin/bash
# enroll-agent.sh - VPS SIDE (Level 3). Polls your onboard Worker for pending enrollments and applies
# them to the local tunnel container(s). OUTBOUND ONLY - it dials out to the Worker; nothing listens on
# this box. Run it on a timer (every ~15s) via systemd, cron, or a loop.
#
#   env:  ONBOARD_URL   your Worker, e.g. https://get.example.com
#         AGENT_TOKEN   the AGENT_TOKEN secret you set on the Worker
#
#   one pass:   ONBOARD_URL=... AGENT_TOKEN=... bash enroll-agent.sh
#   forever:    ... bash enroll-agent.sh --loop   (15s between polls)
#
# Each applied key gets the SAME hard restrictions the container enforces:
#   restrict,port-forwarding,permitlisten="127.0.0.1:<reverse_port>"
set -u
: "${ONBOARD_URL:?set ONBOARD_URL}"; : "${AGENT_TOKEN:?set AGENT_TOKEN}"

apply_pending() {
  local pend
  pend="$(curl -fsS "$ONBOARD_URL/enroll/pending" -H "Authorization: Bearer $AGENT_TOKEN" 2>/dev/null)" || return 0
  # emit: id <TAB> container <TAB> reverse_port <TAB> pubkey
  printf '%s' "$pend" | python3 -c '
import json,sys
try: rows=json.load(sys.stdin)
except Exception: sys.exit(0)
for r in rows:
    print("\t".join([r.get("id",""), r.get("container",""), str(r.get("reverse_port","9922")), r.get("pubkey","")]))
' | while IFS="$(printf '\t')" read -r id container rp pubkey; do
    [ -n "$id" ] && [ -n "$container" ] && [ -n "$pubkey" ] || continue
    case "$pubkey" in ssh-ed25519\ *|ssh-rsa\ *|ecdsa-*\ *) ;; *) echo "skip $id: bad pubkey"; continue ;; esac
    if docker exec -i -e PUBKEY="$pubkey" -e RP="$rp" "$container" sh -c '
        AK=/home/tunnel/.ssh/authorized_keys
        mkdir -p /home/tunnel/.ssh; touch "$AK"
        LINE="restrict,port-forwarding,permitlisten=\"127.0.0.1:$RP\" $PUBKEY"
        grep -qF "$PUBKEY" "$AK" || printf "%s\n" "$LINE" >> "$AK"
        chown -R tunnel:tunnel /home/tunnel/.ssh; chmod 600 "$AK"
      ' 2>/dev/null; then
      curl -fsS -X POST "$ONBOARD_URL/enroll/ack" -H "Authorization: Bearer $AGENT_TOKEN" \
        -H "Content-Type: application/json" -d "{\"id\":\"$id\"}" >/dev/null 2>&1
      echo "applied + acked: $id -> $container (127.0.0.1:$rp)"
    else
      echo "deferred $id: container '$container' not running here (left pending)"
    fi
  done
}

if [ "${1:-}" = "--loop" ]; then
  echo "enroll-agent: polling $ONBOARD_URL every 15s (outbound only)"
  while :; do apply_pending; sleep 15; done
else
  apply_pending
fi

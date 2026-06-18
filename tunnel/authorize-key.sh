#!/bin/bash
# authorize-key.sh - TECH SIDE. Authorize a client's tunnel public key on the rendezvous container.
#
# This is the one manual step of LEVEL 1 onboarding: the client ran the installer on their Mac and
# sent you their "setup code" (an ssh-ed25519 public key). Run this where the container runs (your VPS)
# to let that Mac's tunnel in - with the same hard restrictions the container already enforces.
#
#   bash authorize-key.sh <container> '<ssh-ed25519 AAAA... the client sent>'
#
#   REVERSE_PORT=9922   # override if your container uses a different reverse port
#
# Levels 2 and 3 don't need this - the key is pre-authorized or self-enrolled. See REMOTE-ONBOARDING.md.
set -u

CONTAINER="${1:?usage: authorize-key.sh <container> '<pubkey>'}"
PUBKEY="${2:?usage: authorize-key.sh <container> '<pubkey>'}"
REVERSE_PORT="${REVERSE_PORT:-9922}"

case "$PUBKEY" in
  ssh-ed25519\ *|ssh-rsa\ *|ecdsa-*\ *) ;;
  *) echo "that doesn't look like an SSH public key (expected 'ssh-ed25519 AAAA...')" >&2; exit 2 ;;
esac

# Pass the key + port as env into the container so nothing is injected through host-side quoting.
if docker exec -i -e PUBKEY="$PUBKEY" -e RP="$REVERSE_PORT" "$CONTAINER" sh -c '
  AK=/home/tunnel/.ssh/authorized_keys
  mkdir -p /home/tunnel/.ssh; touch "$AK"
  LINE="restrict,port-forwarding,permitlisten=\"127.0.0.1:$RP\" $PUBKEY"
  grep -qF "$PUBKEY" "$AK" || printf "%s\n" "$LINE" >> "$AK"
  chown -R tunnel:tunnel /home/tunnel/.ssh; chmod 600 "$AK"
'; then
  echo "authorized on '$CONTAINER' - reverse-only, 127.0.0.1:${REVERSE_PORT}"
else
  echo "failed - is the container '$CONTAINER' running on this host?" >&2
  exit 1
fi

echo "note: the container rewrites authorized_keys from TUNNEL_PUBKEY when it restarts. For a permanent"
echo "      client, (re)create the container with that client's key as TUNNEL_PUBKEY - or give each"
echo "      client their own container (recommended; see REMOTE-ONBOARDING.md)."

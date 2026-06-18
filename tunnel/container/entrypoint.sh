#!/bin/sh
# Writes the Mac's tunnel pubkey into authorized_keys with hard restrictions, then runs sshd.
set -e
AK="/home/tunnel/.ssh/authorized_keys"
if [ -n "${TUNNEL_PUBKEY:-}" ]; then
  printf 'restrict,port-forwarding,permitlisten="127.0.0.1:9922" %s\n' "$TUNNEL_PUBKEY" > "$AK"
  chown tunnel:tunnel "$AK"
  chmod 600 "$AK"
  echo "[entrypoint] authorized_keys set for 'tunnel' (reverse-only, 127.0.0.1:9922)"
else
  echo "[entrypoint] WARNING: TUNNEL_PUBKEY empty — no key authorized, all logins will fail" >&2
fi
exec /usr/sbin/sshd -D -e

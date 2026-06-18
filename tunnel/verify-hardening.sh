#!/bin/bash
# verify-hardening.sh — prove the tunnel container only does what it should.
#
# Builds the image, runs it with a throwaway key, and asserts the negative security
# properties the README claims. Exits non-zero if ANY assertion fails. Tears itself
# down. Safe to run locally or in CI.
#
# Requires: docker, ssh, ssh-keygen.  Usage:  bash tunnel/verify-hardening.sh

CTX="$(cd "$(dirname "$0")/container" && pwd)"
IMAGE="${IMAGE:-mac-lifeline-verify}"
PORT="${PORT:-47299}"
NAME="mac-lifeline-verify-$$"
TMP="$(mktemp -d)"
KEY="$TMP/id_test"
FAIL=0

# shellcheck disable=SC2329  # invoked indirectly via trap
cleanup() { docker rm -f "$NAME" >/dev/null 2>&1; rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

say()  { printf '\n=== %s ===\n' "$1"; }
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=1; }

# Run an ssh attempt against the tunnel user, bounded so -N never hangs us.
# $1 = max seconds, rest = extra ssh args. Output (stdout+stderr) is echoed.
ssh_try() {
  local secs="$1"; shift
  local out="$TMP/out"
  ssh -i "$KEY" -p "$PORT" \
      -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 -o ExitOnForwardFailure=yes \
      "$@" tunnel@127.0.0.1 >"$out" 2>&1 &
  local pid=$! i=0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt "$secs" ]; do sleep 1; i=$((i + 1)); done
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  cat "$out"
}

say "Setup"
command -v docker >/dev/null || { echo "docker not found"; exit 3; }
ssh-keygen -t ed25519 -N '' -f "$KEY" -q || { echo "keygen failed"; exit 3; }
echo "  building image '$IMAGE'..."
docker build -q -t "$IMAGE" "$CTX" >/dev/null || { echo "build failed"; exit 3; }
echo "  starting container on :$PORT ..."
docker run -d --name "$NAME" -p "127.0.0.1:$PORT:22" \
  -e TUNNEL_PUBKEY="$(cat "$KEY.pub")" \
  --security-opt no-new-privileges:true --cap-drop ALL \
  --cap-add CHOWN --cap-add SETUID --cap-add SETGID --cap-add DAC_OVERRIDE \
  --cap-add FOWNER --cap-add SYS_CHROOT --cap-add KILL --tmpfs /run \
  "$IMAGE" >/dev/null || { echo "run failed"; exit 3; }

# wait for sshd to accept connections
echo "  waiting for sshd..."
ready=0
for _ in $(seq 1 20); do
  if bash -c "exec 3<>/dev/tcp/127.0.0.1/$PORT" 2>/dev/null; then ready=1; break; fi
  sleep 1
done
[ "$ready" = 1 ] || { echo "sshd never came up"; docker logs "$NAME" 2>&1 | tail; exit 3; }
echo "  ready."

# ---------------------------------------------------------------------------
say "A. Interactive shell / command execution is blocked"
out="$(ssh_try 8 'echo PWNED-MARKER')"
if echo "$out" | grep -q "PWNED-MARKER"; then
  fail "tunnel user executed a command (ForceCommand bypassed!)"
else
  pass "remote command did not execute (ForceCommand /sbin/nologin holds)"
fi

say "B. Reverse forward to the PERMITTED port (9922) is allowed"
out="$(ssh_try 6 -N -R 127.0.0.1:9922:127.0.0.1:22)"
if echo "$out" | grep -qiE "administratively prohibited|forwarding failed|request denied|refused"; then
  fail "the permitted reverse forward was rejected: $out"
else
  pass "reverse forward to 127.0.0.1:9922 accepted"
fi

say "C. Reverse forward to a NON-permitted port is denied"
out="$(ssh_try 6 -N -R 127.0.0.1:8888:127.0.0.1:22)"
if echo "$out" | grep -qiE "administratively prohibited|forwarding failed|request denied|cannot listen"; then
  pass "reverse forward to 127.0.0.1:8888 denied"
else
  fail "reverse forward to a forbidden port was NOT denied: $out"
fi

say "D. Effective sshd policy for user 'tunnel' (authoritative)"
pol="$(docker exec "$NAME" sshd -T -C user=tunnel,host=localhost,addr=127.0.0.1 2>/dev/null | tr '[:upper:]' '[:lower:]')"
check_pol() { # $1=needle  $2=label
  if echo "$pol" | grep -q "$1"; then pass "$2"; else fail "$2 (missing: '$1')"; fi
}
check_pol "allowtcpforwarding remote" "local (-L) forwarding disabled, remote (-R) only"
check_pol "permitlisten 127.0.0.1:9922" "listen pinned to 127.0.0.1:9922"
check_pol "permitopen none" "no direct channel opens permitted"
check_pol "forcecommand /sbin/nologin" "forced command is /sbin/nologin"
check_pol "permitrootlogin no" "root login disabled"
check_pol "passwordauthentication no" "password auth disabled"

# ---------------------------------------------------------------------------
say "Result"
if [ "$FAIL" = 0 ]; then
  echo "  ✓ ALL HARDENING CHECKS PASSED"
else
  echo "  ✗ ONE OR MORE CHECKS FAILED"
fi
exit "$FAIL"

#!/bin/bash
# new-client.sh - TECH SIDE. Mint a one-time setup link to text a client (Levels 1-2).
#
# Builds the personalized installer, uploads it to your onboard Worker, and prints a short URL plus
# the message to send. See ../../docs/REMOTE-ONBOARDING.md.
#
#   Required env:
#     ONBOARD_URL          your Worker, e.g. https://get.example.com  (or the *.workers.dev URL)
#     ONBOARD_ADMIN_TOKEN  the ADMIN_TOKEN secret you set on the Worker
#     VPS_HOST             your VPS IP/host the Mac dials into
#     LABEL                unique launchd label for this client, e.g. com.you.acme-imac
#   Optional env:
#     VPS_PORT (47222)  REVERSE_PORT (9922)  TTL (86400)  CONTROL_PUBKEY
#     MAC_SETUP_URL (raw mac-setup.sh)  VPS_SSH (ssh target to auto-authorize in --mode bake)
#     CONTAINER (container name for --mode bake authorize)
#
#   bash new-client.sh --mode link    # LEVEL 1: client pastes a code back to you (default)
#   bash new-client.sh --mode bake    # LEVEL 2: pre-baked key, client sends nothing
set -u

MODE="link"
case "${1:-}" in
  --mode) MODE="${2:?--mode needs link|bake}" ;;
  -h|--help) awk 'NR==1{next} /^#/{sub(/^# ?/,"");print;next} {exit}' "$0"; exit 0 ;;
  "") ;;
  *) echo "unknown arg: $1 (try --help)" >&2; exit 2 ;;
esac

: "${ONBOARD_URL:?set ONBOARD_URL}"; : "${ONBOARD_ADMIN_TOKEN:?set ONBOARD_ADMIN_TOKEN}"
: "${VPS_HOST:?set VPS_HOST}"; : "${LABEL:?set LABEL}"
VPS_PORT="${VPS_PORT:-47222}"; REVERSE_PORT="${REVERSE_PORT:-9922}"; TTL="${TTL:-86400}"
MAC_SETUP_URL="${MAC_SETUP_URL:-https://raw.githubusercontent.com/curtismercier/mac-lifeline/master/tunnel/mac-setup.sh}"
CONTROL_PUBKEY="${CONTROL_PUBKEY:-}"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
SCRIPT="$TMP/setup.sh"

{
  echo "#!/bin/bash"
  echo "export VPS_HOST='$VPS_HOST' VPS_PORT='$VPS_PORT' LABEL='$LABEL' REVERSE_PORT='$REVERSE_PORT'"
  [ -n "$CONTROL_PUBKEY" ] && echo "export CONTROL_PUBKEY='$CONTROL_PUBKEY'"
} > "$SCRIPT"

if [ "$MODE" = bake ]; then
  ssh-keygen -t ed25519 -N "" -f "$TMP/id" -C "mac-lifeline-$LABEL" -q
  {
    echo "export TUNNEL_PRIVKEY=\"\$(cat <<'MLKEY'"
    cat "$TMP/id"
    echo "MLKEY"
    echo ")\""
  } >> "$SCRIPT"
  PUB="$(cat "$TMP/id.pub")"
  echo ">> authorize this client's PUBLIC key on your container (reverse-only):"
  if [ -n "${VPS_SSH:-}" ] && [ -n "${CONTAINER:-}" ]; then
    # shellcheck disable=SC2029  # we intend the vars to expand locally into the remote command
    ssh "$VPS_SSH" "REVERSE_PORT='$REVERSE_PORT' bash -s '$CONTAINER' '$PUB'" < "$(dirname "$0")/../authorize-key.sh" \
      && echo "   authorized via $VPS_SSH" || echo "   (auto-authorize failed - run it manually, see below)"
  fi
  echo "   bash tunnel/authorize-key.sh ${CONTAINER:-<container>} '$PUB'"
fi

echo "curl -fsSL $MAC_SETUP_URL | bash" >> "$SCRIPT"

# upload to the Worker
PAYLOAD="$(python3 -c 'import json,sys; print(json.dumps({"script": open(sys.argv[1]).read(), "ttl": int(sys.argv[2])}))' "$SCRIPT" "$TTL")"
RESP="$(curl -fsS -X POST "$ONBOARD_URL/new" -H "Authorization: Bearer $ONBOARD_ADMIN_TOKEN" \
  -H "Content-Type: application/json" -d "$PAYLOAD")" || { echo "upload failed" >&2; exit 1; }
LINK="$(printf '%s' "$RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin)["url"])')"

echo
echo "============================================================"
echo "Text this to your client:"
echo
echo "  Open Terminal (Cmd+Space, type Terminal, Return), paste this, press Return:"
echo "    curl -fsSL $LINK | bash"
echo "  It'll ask for your Mac password (it won't show as you type - normal). "
if [ "$MODE" = bake ]; then
  echo "  When it says 'all set', just text me back - I'll take it from here."
else
  echo "  When it says 'copied a setup code', paste that into your reply to me."
fi
echo
echo "Link is one-time and expires in ${TTL}s."
echo "============================================================"

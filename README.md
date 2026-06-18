# mac-lifeline

**Remote-support + cleanup tools for old, hard-to-reach Macs.**

For the machines other tools gave up on: macOS back to **High Sierra (10.13)**, behind
**CGNAT / Wi-Fi isolation** (Starlink, hotel, guest networks), too old for Tailscale or modern
agents. `mac-lifeline` uses only **built-in `ssh` + `launchd`** plus a small hardened container on
a VPS you control — the substrate that runs on *everything*.

> Extracted from a real field engagement: a 2010 iMac on High Sierra, behind a Starlink router.

## What's here
- **`tunnel/`** — an on-demand reverse-SSH tunnel. The old Mac dials *out* to a throwaway container
  on your VPS and reverse-forwards its own SSH, so you can reach it from anywhere.
- **`tools/`** — double-click `.command` maintenance tools for the Mac itself:
  - `clean-adware.command` — removes known Mac adware (MacKeeper, Adload/"Search Manager", Genieo, …) across all accounts. Safe; prints everything it does.
  - `mac-tune-up.command` — health report (disk / SMART / RAM) + optional cleanup.

## Why not Tailscale / cloudflared?
Both need **macOS 10.15+**; on 10.13–10.14 they won't install. Built-in `ssh` + `launchd` do.

## How the tunnel works
```
 OLD MAC (CGNAT, no inbound)               VPS you control              YOU
 launchd: ssh -N -R 127.0.0.1:9922:…:22  ─dials out─▶  container   ◀─ docker exec+nc ── ssh (your key)
        (its own sshd)                      (hardened, tunnel-only)
```
The Mac dials out (through any CGNAT/isolation) into a container that does nothing but accept that
one reverse forward. You hop through the container to reach the Mac.

## Security model — a leaked Mac key is inert against your VPS
- Tunnel user: `nologin`, key-only. `authorized_keys`: `restrict,port-forwarding,permitlisten="127.0.0.1:9922"`.
- sshd `Match User tunnel`: `AllowTcpForwarding remote` (no `-L`), `PermitOpen none`, `PermitListen 127.0.0.1:9922`, `ForceCommand /sbin/nologin`.
- Container: no privileged, no host-network, no mounts → can't see the VPS host or other services.
- **On-demand:** `docker stop` between sessions = zero attack surface.
- Two keys, two scopes: Mac→container (tunnel) and you→Mac (control) never overlap.
- Verified with negative tests: shell blocked · `-L` "administratively prohibited" · `-R` to other ports denied.

## Quick start
1. **VPS** — build + run the container (`tunnel/container/`), publishing a public port → container `:22`:
   ```bash
   docker build -t mac-lifeline ./tunnel/container
   docker run -d --name mactunnel --restart no -p 47222:22 \
     -e TUNNEL_PUBKEY="<the old Mac's tunnel pubkey from step 2>" \
     --security-opt no-new-privileges:true --cap-drop ALL \
     --cap-add CHOWN --cap-add SETUID --cap-add SETGID --cap-add DAC_OVERRIDE \
     --cap-add FOWNER --cap-add SYS_CHROOT --cap-add KILL --tmpfs /run  mac-lifeline
   ```
2. **Old Mac** — edit the CONFIG block in `tunnel/mac-setup.sh`, then `bash tunnel/mac-setup.sh`.
   It generates a key, installs a launchd daemon (auto-reconnects, survives reboots), and prints
   its **public key** → paste that into the container's `TUNNEL_PUBKEY` (step 1) and (re)start it.
3. **Connect:** `ssh -J you@VPS -p 9922 <admin>@127.0.0.1` — or a ProxyCommand:
   `ssh -o ProxyCommand="ssh you@VPS docker exec -i mactunnel nc 127.0.0.1 9922" <admin>@127.0.0.1`

## Gotchas (paid for, so you don't)
- macOS has no `timeout`. Alpine `adduser -D` **locks** the password (`!` → sshd "invalid user"); fix to `*`.
- Never retype an SSH key off a photo — OCR turns `l→1`, `O→0`. Transfer via a short-URL / file.
- Docker port-publish bypasses the host `INPUT` firewall (it uses the `DOCKER-USER` chain). Know it.
- Ship the owner double-click `.command` tools; use `osascript … with administrator privileges` for a
  native password box instead of Terminal `sudo`.

## License
MIT — see [`LICENSE`](LICENSE).

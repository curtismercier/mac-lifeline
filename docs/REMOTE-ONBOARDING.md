# Remote onboarding — getting a client's Mac onto the tunnel when it's not in your hands

The chicken-and-egg of remote support: to set up remote access you need access. When the Mac is in
front of you, you just run [`tunnel/mac-setup.sh`](../tunnel/mac-setup.sh). When it isn't, the **client**
has to bootstrap it. The goal is the fewest, least-scary actions on their end that leave you able to
connect.

## Bring your own infrastructure

`mac-lifeline` is self-hosted. Two pieces, very different requirements:

- **The VPS is required and is yours.** It's the rendezvous the Mac dials into, and the whole security
  model rests on it being *a VPS you control*. Any provider, any small box. Not Cloudflare-specific.
- **A link host is optional.** You only need somewhere to serve a one-time script for Levels 2-3. You do
  **not** need one for **Level 1** (the client runs the raw installer URL with env vars inline), and even
  for 2-3 you can **self-host the link on the same VPS** you already run. Cloudflare (below) is just one
  convenient option because it's what this repo's authors already use — swap in any equivalent.

## One installer, three handoff strategies

`mac-setup.sh` is the same script in every case. What changes is **how your access gets authorized** —
inferred from which environment variables the (hosted) installer sets:

| Level | Client does | Env that triggers it | You build |
|------:|-------------|----------------------|-----------|
| **1 — send the code** | runs it, pastes one code back to you | *(none — default)* | nothing new |
| **2 — pre-baked key** | runs it, sends nothing | `TUNNEL_PRIVKEY` | a one-time link host |
| **3 — self-enroll** | runs it, sends nothing | `ENROLL_URL` + `ENROLL_TOKEN` | a one-time link host **+** an enroll endpoint |

In all three the installer also: turns on **Remote Login** for them (or opens the exact Settings pane on
macOS 10.15+), warns that the password won't show as they type, and prints a friendly "done" message.

## The client experience (identical for all levels)

Text them something like:

> Hi — to let me fix this without coming by (about 2 minutes):
> 1. Press **⌘ + Space**, type **Terminal**, press **Return**.
> 2. Paste this line and press **Return**:
>    `curl -fsSL https://get.example.com/abc123 | bash`
> 3. It asks for your **Mac password** — type it and press Return. **You won't see anything as you type — that's normal Mac security.** Just keep going.
> 4. **Level 1:** when it says *"copied a setup code"*, paste that into your reply to me.
>    **Level 2/3:** when it says *"all set"*, just text me — I'll take it from here.

Always send the command as **text** (a tappable short link), never a screenshot — OCR turns `l`→`1` and
`O`→`0`.

## Level 1 — "send me the code" (works today, no new infrastructure)

1. Host `mac-setup.sh` somewhere with your `VPS_HOST` / `LABEL` baked in (see *Hosting* below), or just
   tell the client to run the raw GitHub URL with env vars inline.
2. The installer generates the Mac's tunnel key, installs the launchd daemon, and **copies the public
   key to the client's clipboard** with *"paste this into your reply."*
3. The client sends you that one line. You authorize it on the container:
   ```bash
   bash tunnel/authorize-key.sh <container> 'ssh-ed25519 AAAA…the client sent'
   ```
4. Connect: `ssh -J you@VPS -p 9922 <admin>@127.0.0.1`.

## Level 2 — "pre-baked key" (one small thing to host)

You generate the keypair, authorize the **public** half yourself, and hand the client a one-time link
whose script carries the **private** half. The client sends nothing back.

The hosted one-time script just sets the env and pipes the installer:

```bash
#!/bin/bash
read -r -d '' TUNNEL_PRIVKEY <<'KEY'
-----BEGIN OPENSSH PRIVATE KEY-----
…this client's tunnel private key…
-----END OPENSSH PRIVATE KEY-----
KEY
export TUNNEL_PRIVKEY VPS_HOST=1.2.3.4 LABEL=com.you.acme-imac
curl -fsSL https://raw.githubusercontent.com/curtismercier/mac-lifeline/master/tunnel/mac-setup.sh | bash
```

**Why shipping a private key to the client is acceptable here:** this is a *tunnel* key. By design it can
only open a reverse forward to `127.0.0.1:9922` on your container, has no shell, and reaches no host — a
leaked copy is inert (see the [security model](../README.md#security-model)). Still, serve it from a
**one-time link that's deleted after the first fetch** so it isn't lying around.

## Level 3 — "self-enroll" (cleanest; no key ever leaves your side)

The installer generates the Mac's own key and `POST`s the **public** key to an enrollment endpoint you
run, authenticated by a one-time token. Nothing comes back to you, and no private key is ever
distributed.

Hosted one-time script:

```bash
export ENROLL_URL=https://enroll.example.com/v1/enroll ENROLL_TOKEN=once-abc123
export VPS_HOST=1.2.3.4 LABEL=com.you.acme-imac
curl -fsSL https://raw.githubusercontent.com/curtismercier/mac-lifeline/master/tunnel/mac-setup.sh | bash
```

The endpoint contract (what you build): `POST` with `Authorization: Bearer <token>` and form field
`pubkey=<ssh-ed25519 …>`. On a valid, unused token it must add the key to the right container's
`authorized_keys` **with the hard restrictions** (exactly what `authorize-key.sh` does:
`restrict,port-forwarding,permitlisten="127.0.0.1:9922"`), then burn the token. Because it writes the
container's `authorized_keys`, this endpoint lives **on/next to the VPS** (a tiny sidecar), not on a
generic web host.

## Where to host the one-time link / short script

Use whatever you already run — **you don't need a separate provider.** Cheapest first:

- **Nothing (Level 1).** Have the client run the raw installer URL with env vars inline — no host at all.
- **Your VPS.** You already run it; serve the one-time script from a tiny static dir (caddy/nginx) or a
  short path, and delete it after fetch. One box, no extra accounts.
- **Any object store / static host** with a short URL in front.

If you happen to run Cloudflare (as this repo's authors do), it's a clean fit:

- **Static script (Level 1, and Level 2 if you accept a TTL):** put the personalized `.sh` in an **R2
  bucket** served over your CDN domain (`cdn.example.com/x/abc123.sh`). R2 **lifecycle rules** can expire
  it by age. No server needed.
- **True one-time + short links (Level 2/3): a small Cloudflare Worker** at e.g. `get.example.com/:id`.
  It looks the id up in **KV or D1**, serves the script (from R2 or generated inline) exactly once, then
  marks it consumed / deletes the object. This gives you clean short URLs *and* single-use semantics
  without standing up a VM.
- **The enroll endpoint (Level 3 only)** must reach the container's `authorized_keys`, so run it **on the
  VPS** beside the tunnel container (a minimal HTTPS sidecar), or have a Worker call back to the VPS over
  a private channel (e.g. Tailscale). Keep its surface tiny and token-gated.

Rule of thumb: **links and scripts → your CDN/Worker; anything that writes the container → the VPS.**

## Recommended container model

Give **each client machine its own container** on its own published port (`-p 472xx:22`,
`TUNNEL_PUBKEY=<that client's key>`). It's the cleanest isolation — one client's key only ever reaches
their own container — and makes start/stop, per-client on-demand, and teardown trivial. `authorize-key.sh`
also supports adding a key to a shared container if you'd rather.

## Don't forget the Mac-side prerequisites

The installer enables Remote Login where it can, but review
[Before you start — enable this on the Mac](../README.md#before-you-start--enable-this-on-the-mac):
Remote Login, no-sleep, restart-after-power-cut, Full Disk Access for `sshd` on 10.15+, and the
FileVault unattended-reboot caveat.

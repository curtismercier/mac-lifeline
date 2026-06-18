# onboard-worker — one-time setup links (optional)

A tiny Cloudflare Worker that mints **single-use, short URLs** serving a personalized `mac-setup.sh` to a
client. It implements Levels 1–2 of [REMOTE-ONBOARDING.md](../../docs/REMOTE-ONBOARDING.md).

**You don't need this.** Level 1 works with the raw GitHub URL + env vars, and the one-time link can just
as easily be a static file on the VPS you already run. This is a clean, self-deployable option if you're
already on Cloudflare.

## Deploy your own (≈2 min)

```bash
source your-cloudflare.env                      # CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID
npx wrangler kv namespace create LINKS          # paste the id into wrangler.toml
npx wrangler secret put ADMIN_TOKEN             # a long random string you keep
npx wrangler deploy                             # -> https://mac-lifeline-onboard.<you>.workers.dev
```

Optionally point a short domain at it (uncomment `routes` in `wrangler.toml`).

## Use it

```bash
export ONBOARD_URL=https://get.example.com ONBOARD_ADMIN_TOKEN=…   # your Worker + secret
export VPS_HOST=1.2.3.4 LABEL=com.you.acme-imac

bash new-client.sh --mode link    # Level 1: client pastes a code back
bash new-client.sh --mode bake    # Level 2: pre-baked key, client sends nothing
```

It prints the short URL and the exact message to text the client.

## How it stays safe

- `POST /new` is gated by the `ADMIN_TOKEN` bearer; only you can mint links.
- `GET /:id` serves the script **once, then deletes it** (one-time), with a TTL backstop.
- **Link-unfurl protection:** messaging apps fetch links to build previews, which would otherwise burn a
  one-time link. Only a real `curl`/`wget` fetch consumes it; browsers/bots get a harmless page.
- A Level-2 script carries a *tunnel* private key — inert by design (reverse-only, one listen address, no
  shell; see the [security model](../../README.md#security-model)). The one-time + TTL link keeps it from
  lingering. For zero key distribution, use Level 3 (self-enroll) instead.

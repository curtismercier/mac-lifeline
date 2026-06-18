/**
 * mac-lifeline onboard — one-time installer links (Cloudflare Worker, OPTIONAL).
 *
 * Lets a tech mint a short, single-use URL that serves a personalized mac-setup.sh to a client
 * (Levels 1-2 of REMOTE-ONBOARDING.md). You do NOT need this — Level 1 works with the raw GitHub
 * URL + env vars, and the link can equally be a static file on your own VPS. This is just a clean,
 * self-deployable option for anyone already on Cloudflare.
 *
 * Routes:
 *   POST /new   (admin)  body {script:"#!/bin/bash...", ttl?:seconds} -> {id,url} . Bearer ADMIN_TOKEN.
 *   GET  /:id            curl/wget -> serves the script ONCE then burns it; browsers -> a safe page.
 *   GET  /               health/landing.
 *
 * Bindings: KV namespace `LINKS`. Secret: `ADMIN_TOKEN`.
 */

const LANDING =
  "mac-lifeline setup link.\n\n" +
  "This link gives a one-time setup command to your Mac's helper. Open Terminal and paste the\n" +
  "exact command your tech sent you — don't worry about this page.\n";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    if (method === "GET" && path === "/") {
      return text(LANDING);
    }

    // --- admin: mint a one-time link ---
    if (method === "POST" && path === "/new") {
      const auth = request.headers.get("authorization") || "";
      if (!env.ADMIN_TOKEN || auth !== `Bearer ${env.ADMIN_TOKEN}`) {
        return text("unauthorized\n", 401);
      }
      let body;
      try { body = await request.json(); } catch { return text("expected JSON body\n", 400); }
      const script = typeof body.script === "string" ? body.script : "";
      if (!script.startsWith("#!")) {
        return text("provide {\"script\":\"#!/bin/bash ...\"}\n", 400);
      }
      let ttl = parseInt(body.ttl, 10);
      if (!Number.isFinite(ttl)) ttl = 86400;           // default 24h
      ttl = Math.min(Math.max(ttl, 60), 604800);        // clamp 1min..7d
      const id = crypto.randomUUID().replace(/-/g, "").slice(0, 22);
      await env.LINKS.put(id, script, { expirationTtl: ttl });
      return json({ id, url: `${url.origin}/${id}`, expires_in: ttl });
    }

    // --- client: fetch + burn the one-time script ---
    if (method === "GET" && /^\/[A-Za-z0-9]{8,40}$/.test(path)) {
      const id = path.slice(1);
      const script = await env.LINKS.get(id);
      if (script === null) {
        return text("# This setup link has expired or was already used. Ask your tech for a fresh one.\n", 404);
      }
      // Link-unfurl protection: messaging apps GET links to build previews. Only a real
      // curl/wget fetch consumes (burns) the link; anything else gets a harmless page.
      const ua = request.headers.get("user-agent") || "";
      if (!/\bcurl\/|\bwget\/|libcurl|\bbash\b/i.test(ua)) {
        return text(LANDING);
      }
      await env.LINKS.delete(id);                        // one-time: burn after serving
      return new Response(script, { headers: {
        "content-type": "text/plain; charset=utf-8",
        "cache-control": "no-store",
      }});
    }

    return text("not found\n", 404);
  },
};

const text = (s, status = 200) =>
  new Response(s, { status, headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" } });
const json = (o, status = 200) =>
  new Response(JSON.stringify(o) + "\n", { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

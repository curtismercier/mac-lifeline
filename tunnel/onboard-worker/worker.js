/**
 * mac-lifeline onboard — one-time setup links + Level-3 enrollment (Cloudflare Worker, OPTIONAL).
 *
 * Self-host this on YOUR Cloudflare to run remote onboarding for your own clients. It's optional —
 * Level 1 works with the raw GitHub URL + env vars, and the link can be a static file on your VPS.
 *
 * LINKS (Levels 1-2):
 *   POST /new            (admin)  {script,"ttl"?}            -> {id,url}. One-time, burned on fetch.
 *   GET  /:id                     curl/wget -> serve once+burn; browsers -> safe page.
 *
 * ENROLL (Level 3 — client sends nothing, no private key distributed):
 *   POST /enroll/new     (admin)  {container,"reverse_port"?,"ttl"?} -> {token,enroll_url}.
 *   POST /enroll         (token)   Bearer <one-time token> + form pubkey=...  -> stores a PENDING enrollment.
 *   GET  /enroll/pending (agent)   -> [{id,container,reverse_port,pubkey}]  (your VPS agent polls this).
 *   POST /enroll/ack     (agent)   {id} -> removes a pending entry after the agent applied it.
 *
 * Bindings: KV `LINKS`. Secrets: `ADMIN_TOKEN` (mint), `AGENT_TOKEN` (your VPS poll agent).
 * The VPS agent (tunnel/onboard-worker/enroll-agent.sh) dials OUT to /enroll/pending — no inbound port.
 */

const LANDING =
  "mac-lifeline setup link.\n\n" +
  "This link gives a one-time setup command to your Mac's helper. Open Terminal and paste the\n" +
  "exact command your tech sent you — don't worry about this page.\n";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    const m = request.method;

    if (m === "GET" && path === "/") return text(LANDING);

    // ---------- LINKS ----------
    if (m === "POST" && path === "/new") {
      if (!admin(request, env)) return text("unauthorized\n", 401);
      const body = await jsonBody(request);
      if (!body) return text("expected JSON body\n", 400);
      const script = typeof body.script === "string" ? body.script : "";
      if (!script.startsWith("#!")) return text('provide {"script":"#!/bin/bash ..."}\n', 400);
      const ttl = clampTtl(body.ttl);
      const id = rid(22);
      await env.LINKS.put(id, script, { expirationTtl: ttl });
      return json({ id, url: `${url.origin}/${id}`, expires_in: ttl });
    }

    // ---------- ENROLL (Level 3) ----------
    if (m === "POST" && path === "/enroll/new") {
      if (!admin(request, env)) return text("unauthorized\n", 401);
      const body = await jsonBody(request);
      if (!body || typeof body.container !== "string" || !body.container)
        return text('provide {"container":"<name>"}\n', 400);
      const ttl = clampTtl(body.ttl);
      const token = rid(32);
      const rec = { container: body.container, reverse_port: String(body.reverse_port || "9922") };
      await env.LINKS.put(`tok:${token}`, JSON.stringify(rec), { expirationTtl: ttl });
      return json({ token, enroll_url: `${url.origin}/enroll`, expires_in: ttl });
    }

    if (m === "POST" && path === "/enroll") {
      const token = bearer(request);
      if (!token) return text("missing enroll token\n", 401);
      const recRaw = await env.LINKS.get(`tok:${token}`);
      if (recRaw === null) return text("enroll token invalid, used, or expired\n", 401);
      let pubkey = "";
      try { pubkey = (await request.formData()).get("pubkey") || ""; } catch { /* ignore */ }
      if (!/^(ssh-ed25519|ssh-rsa|ecdsa-) /.test(pubkey)) return text("bad or missing pubkey\n", 400);
      const rec = JSON.parse(recRaw);
      const id = rid(20);
      await env.LINKS.put(`pend:${id}`, JSON.stringify({ ...rec, pubkey, ts: Date.now() }),
        { expirationTtl: 86400 });
      await env.LINKS.delete(`tok:${token}`);                 // one-time
      return json({ ok: true });
    }

    if (m === "GET" && path === "/enroll/pending") {
      if (!agent(request, env)) return text("unauthorized\n", 401);
      const list = await env.LINKS.list({ prefix: "pend:" });
      const out = [];
      for (const k of list.keys) {
        const v = await env.LINKS.get(k.name);
        if (v) out.push({ id: k.name.slice(5), ...JSON.parse(v) });
      }
      return json(out);
    }

    if (m === "POST" && path === "/enroll/ack") {
      if (!agent(request, env)) return text("unauthorized\n", 401);
      const body = await jsonBody(request);
      if (!body || !body.id) return text('provide {"id":"..."}\n', 400);
      await env.LINKS.delete(`pend:${body.id}`);
      return json({ ok: true });
    }

    // ---------- one-time link fetch ----------
    if (m === "GET" && /^\/[A-Za-z0-9]{8,40}$/.test(path)) {
      const id = path.slice(1);
      const script = await env.LINKS.get(id);
      if (script === null)
        return text("# This setup link has expired or was already used. Ask your tech for a fresh one.\n", 404);
      // Link-unfurl protection: only a real curl/wget fetch consumes the link; previews get a safe page.
      const ua = request.headers.get("user-agent") || "";
      if (!/\bcurl\/|\bwget\/|libcurl|\bbash\b/i.test(ua)) return text(LANDING);
      await env.LINKS.delete(id);
      return new Response(script, { headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" } });
    }

    return text("not found\n", 404);
  },
};

const admin = (req, env) => !!env.ADMIN_TOKEN && bearer(req) === env.ADMIN_TOKEN;
const agent = (req, env) => !!env.AGENT_TOKEN && bearer(req) === env.AGENT_TOKEN;
const bearer = (req) => {
  const a = req.headers.get("authorization") || "";
  return a.startsWith("Bearer ") ? a.slice(7) : "";
};
const jsonBody = async (req) => { try { return await req.json(); } catch { return null; } };
const clampTtl = (t) => { let n = parseInt(t, 10); if (!Number.isFinite(n)) n = 86400; return Math.min(Math.max(n, 60), 604800); };
const rid = (n) => crypto.randomUUID().replace(/-/g, "").slice(0, n);
const text = (s, status = 200) => new Response(s, { status, headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" } });
const json = (o, status = 200) => new Response(JSON.stringify(o) + "\n", { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
